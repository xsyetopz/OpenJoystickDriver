import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
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
          + " [\(d.connection)] SN:\(sn))" + " protocol=\(d.protocolVariant.rawValue)"
          + " endpoints=in:0x\(String(d.inputEndpoint, radix: 16))"
          + " out:0x\(String(d.outputEndpoint, radix: 16))"
          + " setConfig=\(d.needsSetConfiguration)" + " settleMs=\(d.postHandshakeSettleMs)"
          + " mappings=\(mappings)" + " backends=\(backends)"
      }
      callback.call(strings)
    }
  }

  /// Returns the current application service status including input monitoring state and connected devices.
  public func getStatus(reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    let pm = permissionManager
    Task {
      let permissions = await pm.refreshAccessState()
      let devices = await dm.connectedDeviceDescriptions()
      let userEnabled = userSpaceEnabled
      let userStatus = currentUserSpaceStatus()
      let payload = ApplicationServiceStatusPayload(
        inputMonitoring: "\(permissions.inputMonitoring)",
        accessibility: "\(permissions.accessibility)",
        connectedDevices: devices,
        userSpaceVirtualDeviceEnabled: userEnabled,
        userSpaceVirtualDeviceStatus: userStatus,
        compatibilityIdentity: compatibilityIdentity.rawValue
      )
      do {
        let data = try JSONEncoder().encode(payload)
        callback.call(data)
      } catch {
        print("[ApplicationServiceServer] getStatus encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func requestRequiredAccess(reply: @escaping (PermissionManager.Snapshot) -> Void) {
    let callback = SendableReply(call: reply)
    let pm = permissionManager
    Task {
      let snapshot = await pm.requestRequiredAccess()
      callback.call(snapshot)
    }
  }

  /// Returns the current input state for the specified device as encoded JSON data.
  public func getDeviceInputState(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data?) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let state = await dm.inputState(for: identifier, runtimeIdentifier: runtimeIdentifier)
      callback.call(try? JSONEncoder().encode(state))
    }
  }

  /// Returns the recent packet log for the specified device as encoded JSON data.
  public func getPacketLog(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    reply: @escaping (Data) -> Void
  ) {
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(vendorID: UInt16(vendorID), productID: UInt16(productID))
      let log = await dm.packetLog(for: identifier, runtimeIdentifier: runtimeIdentifier)
      do {
        let data = try JSONEncoder().encode(log)
        callback.call(data)
      } catch {
        print("[ApplicationServiceServer] getPacketLog encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func sendPhysicalRumble(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
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
        runtimeIdentifier: runtimeIdentifier,
        left: UInt8(clamping: left),
        right: UInt8(clamping: right),
        lt: UInt8(clamping: lt),
        rt: UInt8(clamping: rt),
        durationMs: durationMs
      )
      callback.call(ok)
    }
  }

  public func setPhysicalPlayerIndicator(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    playerIndex: Int,
    reply: @escaping (Bool) -> Void
  ) {
    guard let indicator = PhysicalPlayerIndicator(rawValue: playerIndex) else {
      reply(false)
      return
    }
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(
        vendorID: UInt16(clamping: vendorID),
        productID: UInt16(clamping: productID)
      )
      callback.call(
        await dm.sendPlayerIndicator(
          for: identifier,
          runtimeIdentifier: runtimeIdentifier,
          indicator: indicator
        )
      )
    }
  }

  public func setPhysicalColor(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    red: Int,
    green: Int,
    blue: Int,
    reply: @escaping (Bool) -> Void
  ) {
    guard [red, green, blue].allSatisfy({ (0...255).contains($0) }) else {
      reply(false)
      return
    }
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(
        vendorID: UInt16(clamping: vendorID),
        productID: UInt16(clamping: productID)
      )
      callback.call(
        await dm.setPhysicalColor(
          for: identifier,
          runtimeIdentifier: runtimeIdentifier,
          red: UInt8(red),
          green: UInt8(green),
          blue: UInt8(blue)
        )
      )
    }
  }

  public func setPhysicalBrightness(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?,
    brightness: Int,
    reply: @escaping (Bool) -> Void
  ) {
    guard (0...255).contains(brightness) else {
      reply(false)
      return
    }
    let callback = SendableReply(call: reply)
    let dm = deviceManager
    Task {
      let identifier = DeviceIdentifier(
        vendorID: UInt16(clamping: vendorID),
        productID: UInt16(clamping: productID)
      )
      callback.call(
        await dm.setPhysicalBrightness(
          for: identifier,
          runtimeIdentifier: runtimeIdentifier,
          brightness: UInt8(brightness)
        )
      )
    }
  }

  /// Enables or disables virtual output suppression and reports success.
  public func setSuppressOutput(_ suppress: Bool, reply: @escaping (Bool) -> Void) {
    let callback = SendableReply(call: reply)
    Task {
      do {
        try await remappingRouter.setOutputSuppressed(suppress)
        callback.call(true)
      } catch {
        callback.call(false)
      }
    }
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
          dispatcher.setBackend(build.dispatcher)
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

      // A failed backend remains explicit; persist the chosen identity for the next service start.
      compatibilityIdentity = id
      UserDefaults.standard.set(id.rawValue, forKey: Self.compatibilityIdentityDefaultsKey)
      return true
    }
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
      let devices = VirtualDeviceDiagnostics.enumerateHIDGamepads()
      let stats = await driverKitDispatcher.outputStatsSnapshot()
      let payload = ApplicationServiceVirtualDeviceDiagnosticsPayload(
        userSpaceVirtualDeviceEnabled: enabled,
        userSpaceVirtualDeviceStatus: status,
        hidGamepads: devices,
        driverKitOutputStats: stats
      )
      do { callback.call(try JSONEncoder().encode(payload)) } catch {
        print("[ApplicationServiceServer] getVirtualDeviceDiagnostics encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func runVirtualDeviceSelfTest(seconds: Int, reply: @escaping (Data) -> Void) {
    let callback = SendableReply(call: reply)
    let secs = max(1, min(30, seconds))
    Task {
      let payload = await runVirtualDeviceSelfTestInternal(seconds: secs)
      do { callback.call(try JSONEncoder().encode(payload)) } catch {
        print("[ApplicationServiceServer] runVirtualDeviceSelfTest encode error: \(error)")
        callback.call(Data())
      }
    }
  }

  public func resetSettings(reply: @escaping (Bool) -> Void) {
    // Clear persisted keys so the application service comes up in a known-good baseline.
    UserDefaults.standard.removeObject(forKey: Self.compatibilityIdentityDefaultsKey)
    UserDefaults.standard.removeObject(forKey: "UserSpaceVirtualDeviceEnabled")
    UserDefaults.standard.removeObject(forKey: "OutputMode")
    UserDefaults.standard.removeObject(forKey: "VirtualDeviceMode")

    userSpaceLock.withLock {
      dispatcher.setBackend(nil)
      userSpaceDispatcher?.close()
      userSpaceDispatcher = nil
      foregroundConsumerDispatcherPool = nil
      userSpaceEnabled = false
      userSpaceStatus = "off"
    }

    compatibilityIdentity = .sdl2_3
    reply(initializeCompatibilityBackend())
  }

  func getRemappingSnapshot(
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.snapshot()) }
  }

  func getRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<RemappingProfile>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.profile(id: id)) }
  }

  func createRemappingProfile(
    _ profile: RemappingProfile,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.create(profile)) }
  }

  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      callback.call(
        await remappingRequests.update(profile, expectedCurrent: expectedCurrent)
      )
    }
  }

  func importRemappingProfile(
    _ profile: RemappingProfile,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.importProfile(profile)) }
  }

  func deleteRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.delete(id: id)) }
  }

  func activateRemappingProfile(
    id: UUID,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.activate(id: id)) }
  }

  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16,
    reply: @escaping (RemappingRequestResult<ApplicationServiceRemappingSnapshotPayload>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task {
      callback.call(
        await remappingRequests.deactivate(vendorID: vendorID, productID: productID)
      )
    }
  }

  func getRemappingPostEventAccess(
    reply: @escaping (RemappingRequestResult<RemappingPostEventAccessState>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.currentPostEventAccess()) }
  }

  func requestRemappingPostEventAccess(
    reply: @escaping (RemappingRequestResult<RemappingPostEventAccessState>) -> Void
  ) {
    let callback = SendableReply(call: reply)
    Task { callback.call(await remappingRequests.requestPostEventAccess()) }
  }
}
