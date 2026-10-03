import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Returns the current application service status including input monitoring state and
  /// connected devices.
  public func getStatus() async -> Data {
    let permissions = await permissionManager.refreshAccessState()
    let devices = describingVirtualHIDProfiles(await connectedDevices())
    let unboundDevices = await deviceManager.unboundDeviceDescriptions().map(
      ApplicationServiceUnboundDevice.init(snapshot:)
    )
    let passThroughDevices = await deviceManager.passThroughDeviceDescriptions().map(
      ApplicationServicePassThroughDevice.init(snapshot:)
    )
    let userSnapshot = userSpaceStatusSnapshot()
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "\(permissions.inputMonitoring)",
      accessibility: "\(permissions.accessibility)",
      connectedDevices: devices,
      unboundDevices: unboundDevices,
      passThroughDevices: passThroughDevices,
      userSpaceVirtualDeviceEnabled: userSnapshot.enabled,
      userSpaceVirtualDeviceStatus: userSnapshot.status,
      virtualHIDProfileOverrideError: virtualHIDProfileOverrides.loadError?.statusDescription
    )
    do { return try JSONEncoder().encode(payload) } catch {
      print("[ApplicationServiceServer] getStatus encode error: \(error)")
      return Data()
    }
  }

  public func requestRequiredAccess() async -> PermissionManager.Snapshot {
    await permissionManager.requestRequiredAccess()
  }

  public func requestAccess(
    _ requirement: PermissionManager.Requirement
  ) async -> PermissionManager.Snapshot { await permissionManager.requestAccess(requirement) }

  /// Returns the current input state for the specified device as encoded JSON data.
  public func getControllerState(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data? {
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return nil
    }
    let identifier = DeviceIdentifier(vendorID: vendor, productID: product)
    let state = await deviceManager.controllerState(
      for: identifier,
      runtimeIdentifier: runtimeIdentifier
    )
    return try? JSONEncoder().encode(state)
  }

  /// Returns the values the device's virtual gamepad last reported as encoded JSON data; nil
  /// when no virtual gamepad publishes the device.
  public func getVirtualOutputState(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data? {
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID),
      let state = await automaticUserSpaceDispatcher()?.virtualOutputState(
        matching: DeviceIdentifier(vendorID: vendor, productID: product),
        runtimeIdentifier: runtimeIdentifier
      )
    else { return nil }
    return try? JSONEncoder().encode(ApplicationServiceVirtualOutputState(state))
  }

  /// Returns the recent packet log for the specified device as encoded JSON data.
  public func getPacketLog(vendorID: Int, productID: Int, runtimeIdentifier: String?) async -> Data
  {
    guard let vendor = UInt16(exactly: vendorID), let product = UInt16(exactly: productID) else {
      return Data()
    }
    let identifier = DeviceIdentifier(vendorID: vendor, productID: product)
    let log = await deviceManager.packetLog(for: identifier, runtimeIdentifier: runtimeIdentifier)
    do { return try JSONEncoder().encode(log) } catch {
      print("[ApplicationServiceServer] getPacketLog encode error: \(error)")
      return Data()
    }
  }

  /// Sends one output command to the selected controller; `ControllerOutputResult` reports what
  /// became of it, including the rumble channels the controller lacks.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) async -> ControllerOutputResult {
    await deviceManager.sendControllerOutput(
      command,
      for: DeviceIdentifier(vendorID: vendorID, productID: productID),
      runtimeIdentifier: runtimeIdentifier
    )
  }

  public func suspendController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data {
    let result = await deviceManager.suspendController(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID),
      runtimeIdentifier: runtimeIdentifier
    )
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  public func resumeController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data {
    let result = await deviceManager.resumeController(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID),
      runtimeIdentifier: runtimeIdentifier
    )
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  public func disconnectWirelessController(
    vendorID: Int,
    productID: Int,
    runtimeIdentifier: String?
  ) async -> Data {
    let result = await deviceManager.disconnectWirelessController(
      vendorID: UInt16(clamping: vendorID),
      productID: UInt16(clamping: productID),
      runtimeIdentifier: runtimeIdentifier
    )
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  public func getVirtualDeviceDiagnostics() -> Data {
    let userSnapshot = userSpaceStatusSnapshot()
    let payload = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: userSnapshot.enabled,
      userSpaceVirtualDeviceStatus: userSnapshot.status,
      hidGamepads: VirtualDeviceDiagnostics.enumerateHIDGamepads()
    )
    do { return try JSONEncoder().encode(payload) } catch {
      print("[ApplicationServiceServer] getVirtualDeviceDiagnostics encode error: \(error)")
      return Data()
    }
  }

  public func resetSettings() async -> Bool {
    await virtualOutputTransitionCoordinator.enqueue { [weak self] in
      guard let self else { return false }
      return await self.performResetSettingsAsync()
    }
  }

  private func performResetSettingsAsync() async -> Bool {
    resetVirtualHIDProfileSettings()
    let live = await performVirtualOutputBackendActivation()
    let retargeted = await retargetConnectedControllers()
    return live && retargeted
  }
}
