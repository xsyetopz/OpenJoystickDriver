import Foundation
import OpenJoystickDriverKit

extension XPCService {
  // MARK: - OpenJoystickDriverXPCProtocol

  /// Returns a list of connected device descriptions.
  public func listDevices(reply: @escaping ([String]) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let devices = await dm.connectedDeviceDescriptions()
      let strings = devices.map { d in
        let sn = d.serialNumber ?? "none"
        let mappings = d.mappingFlags.isEmpty ? "none" : d.mappingFlags.joined(separator: ",")
        let backends =
          d.preferredBackends.isEmpty ? "none" : d.preferredBackends.joined(separator: ",")
        return "\(d.name) (VID:\(d.vendorID)" + " PID:\(d.productID) \(d.parser)"
          + " [\(d.connection)] SN:\(sn))" + " protocol=\(d.protocolVariant)"
          + " endpoints=in:0x\(String(d.inputEndpoint, radix: 16))"
          + " out:0x\(String(d.outputEndpoint, radix: 16))"
          + " setConfig=\(d.needsSetConfiguration)" + " settleMs=\(d.postHandshakeSettleMs)"
          + " mappings=\(mappings)" + " backends=\(backends)"
      }
      callback.call(strings)
    }
  }

  /// Returns the current daemon status including input monitoring state and connected devices.
  public func getStatus(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    let pm = permissionManager
    Task {
      let inputState = await pm.inputMonitoringState
      let devices = await dm.connectedDeviceDescriptions()
      let userEnabled = userSpaceEnabled
      let userStatus = currentUserSpaceStatus()
      let payload = XPCStatusPayload(
        inputMonitoring: "\(inputState)",
        connectedDevices: devices,
        userSpaceVirtualDeviceEnabled: userEnabled,
        userSpaceVirtualDeviceStatus: userStatus,
        virtualDeviceMode: virtualDeviceMode.rawValue,
        effectiveOutputMode: effectiveOutputMode.rawValue,
        compatibilityIdentity: compatibilityIdentity.rawValue
      )
      do {
        let data = try JSONEncoder().encode(payload)
        callback.call(data)
      } catch {
        print("[XPCService] getStatus encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func requestInputMonitoringAccess(reply: @escaping (String) -> Void) {
    let callback = SendableReply(call: reply)
    let pm = permissionManager
    Task {
      let state = await pm.requestAccess()
      callback.call("\(state)")
    }
  }

  /// Returns the current input state for the specified device as encoded JSON data.
  public func getDeviceInputState(vendorID: Int, productID: Int, reply: @escaping (Data?) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let state = await dm.inputState(for: identifier)
      callback.call(try? JSONEncoder().encode(state))
    }
  }

  /// Returns the recent packet log for the specified device as encoded JSON data.
  public func getPacketLog(vendorID: Int, productID: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let log = await dm.packetLog(for: identifier)
      do {
        let data = try JSONEncoder().encode(log)
        callback.call(data)
      } catch {
        print("[XPCService] getPacketLog encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func sendPhysicalRumble(
    vendorID: Int,
    productID: Int,
    left: Int,
    right: Int,
    lt: Int,
    rt: Int,
    durationMs: Int,
    reply: @escaping (Bool) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let ok = await dm.sendRumble(
        for: identifier,
        left: UInt8(clamping: left),
        right: UInt8(clamping: right),
        lt: UInt8(clamping: lt),
        rt: UInt8(clamping: rt),
        durationMs: durationMs
      )
      callback.call(ok)
    }
  }

  /// Enables or disables virtual output suppression and reports success.
  public func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void) {
    dispatcher.suppressOutput = suppress
    reply(true)
  }

  public func setVirtualDeviceMode(_ modeRaw: String, reply: @escaping (Bool) -> Void) {
    guard let mode = VirtualDeviceMode(rawValue: modeRaw) else {
      reply(false)
      return
    }
    applyMode(mode)
    reply(true)
  }

  public func getVirtualDeviceMode(reply: @escaping (String) -> Void) {
    reply(virtualDeviceMode.rawValue)
  }

  public func setUserSpaceVirtualDeviceEnabled(_ enabled: Bool, reply: @escaping (Bool) -> Void) {
    // Legacy API: map to virtual device modes.
    if enabled { applyMode(.compatUserSpace) } else { applyMode(.driverKit) }
    reply(true)
  }

  public func getUserSpaceVirtualDeviceEnabled(reply: @escaping (Bool) -> Void) {
    reply(userSpaceEnabled)
  }

  public func getUserSpaceVirtualDeviceStatus(reply: @escaping (String) -> Void) {
    reply(currentUserSpaceStatus())
  }

  public func setCompatibilityIdentity(_ raw: String, reply: @escaping (Bool) -> Void) {
    guard let id = CompatibilityIdentity(rawValue: raw) else {
      reply(false)
      return
    }
    // Transactional switch:
    // - If user-space is enabled, do not tear down the current device until the new one is ready.
    // - If creation fails, keep the existing device alive and do not change the persisted identity.
    let ok = userSpaceLock.withLock { () -> Bool in
      if userSpaceEnabled, let old = userSpaceDispatcher {
        do {
          let build = try buildUserSpaceDispatcher(identity: id)
          dispatcher.setSecondary(build.dispatcher)
          userSpaceDispatcher = build.dispatcher
          foregroundConsumerDispatcherPool = build.foregroundConsumerPool
          userSpaceStatus = build.status
          compatibilityIdentity = id
          UserDefaults.standard.set(id.rawValue, forKey: Self.compatibilityIdentityDefaultsKey)
          old.close()
          primeUserSpaceDevices(build.dispatcher)
          return true
        } catch {
          if !userSpaceStatus.hasPrefix("error:") {
            userSpaceStatus =
              "error: Failed to switch Compatibility identity (\(id.rawValue)). Kept "
              + "previous Compatibility device running. \(error)"
          } else {
            userSpaceStatus += " (kept previous Compatibility device running)"
          }
          return false
        }
      }

      // If user-space isn't currently enabled, just persist the choice. It will be applied on next enable.
      compatibilityIdentity = id
      UserDefaults.standard.set(id.rawValue, forKey: Self.compatibilityIdentityDefaultsKey)
      return true
    }
    if ok && id.disablesDriverKitMirror && virtualDeviceMode == .both { applyMode(.both) }
    reply(ok)
  }

  public func getCompatibilityIdentity(reply: @escaping (String) -> Void) {
    reply(compatibilityIdentity.rawValue)
  }

  public func getVirtualDeviceDiagnostics(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    Task {
      let enabled = userSpaceEnabled
      let status = currentUserSpaceStatus()
      let mode = effectiveOutputMode
      let devices = VirtualDeviceDiagnostics.enumerateHIDGamepads()
      let stats = dextDispatcher.outputStatsSnapshot()
      let payload = XPCVirtualDeviceDiagnosticsPayload(
        userSpaceVirtualDeviceEnabled: enabled,
        userSpaceVirtualDeviceStatus: status,
        outputMode: mode.rawValue,
        hidGamepads: devices,
        driverKitOutputStats: stats
      )
      do { callback.call(try JSONEncoder().encode(payload)) } catch {
        print("[XPCService] getVirtualDeviceDiagnostics encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func setOutputMode(_ mode: String, reply: @escaping (Bool) -> Void) {
    reply(setOutputModeInternal(mode))
  }

  public func getOutputMode(reply: @escaping (String) -> Void) {
    // Legacy API: return the *effective* output routing, not the requested mode.
    // This prevents UI desync when Auto falls back to user-space.
    reply(effectiveOutputMode.rawValue)
  }

  public func runVirtualDeviceSelfTest(seconds: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let secs = max(1, min(30, seconds))
    Task {
      let payload = await runVirtualDeviceSelfTestInternal(seconds: secs)
      do { callback.call(try JSONEncoder().encode(payload)) } catch {
        print("[XPCService] runVirtualDeviceSelfTest encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func resetSettings(reply: @escaping (Bool) -> Void) {
    // Clear persisted keys so the daemon comes up in a known-good baseline.
    UserDefaults.standard.removeObject(forKey: Self.userSpaceEnabledDefaultsKey)
    UserDefaults.standard.removeObject(forKey: Self.compatibilityIdentityDefaultsKey)
    UserDefaults.standard.removeObject(forKey: Self.outputModeDefaultsKey)
    UserDefaults.standard.removeObject(forKey: Self.virtualDeviceModeDefaultsKey)

    userSpaceLock.withLock {
      dispatcher.setSecondary(nil)
      userSpaceDispatcher?.close()
      userSpaceDispatcher = nil
      foregroundConsumerDispatcherPool = nil
      userSpaceEnabled = false
      userSpaceStatus = "off"
    }

    compatibilityIdentity = .sdl2_3
    virtualDeviceMode = .compatUserSpace
    effectiveOutputMode = .primaryOnly
    applyMode(.compatUserSpace)
    reply(true)
  }
}
