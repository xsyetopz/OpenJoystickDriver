import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer {
  /// Returns the current application service status including input monitoring state and
  /// connected devices.
  public func getStatus() async -> Data {
    let permissions = await permissionManager.refreshAccessState()
    let devices = describingVirtualHIDProfiles(
      await deviceManager.connectedDeviceDescriptions().map {
        ($0.logicalControllerID, ApplicationServiceDeviceDescription(snapshot: $0))
      }
    )
    let unboundDevices = await deviceManager.unboundDeviceDescriptions().map(
      ApplicationServiceUnboundDevice.init(snapshot:)
    )
    let passThroughDevices = await deviceManager.passThroughDeviceDescriptions().map(
      ApplicationServicePassThroughDevice.init(snapshot:)
    )
    let userSnapshot = userSpaceStatusSnapshot()
    let payload = ApplicationServiceStatusPayload(
      inputRead: permissions.inputRead,
      inputInject: permissions.inputInject,
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

  /// Asks for every access that the service requires and returns the resulting state.
  public func requestRequiredAccess() async -> PermissionManager.Snapshot {
    await permissionManager.requestRequiredAccess()
  }

  /// Asks for the access `requirement` names and returns the resulting state.
  public func requestAccess(
    _ requirement: PermissionManager.Requirement
  ) async -> PermissionManager.Snapshot { await permissionManager.requestAccess(requirement) }

  /// Returns the current input state of the controller `controller` names as encoded JSON data.
  public func getControllerState(for controller: ControllerReference) async -> Data? {
    let state = await deviceManager.controllerState(for: controller)
    return try? JSONEncoder().encode(state)
  }

  /// Returns the values the controller's virtual gamepad last reported as encoded JSON data; nil
  /// when no virtual gamepad publishes the controller.
  public func getVirtualOutputState(for controller: ControllerReference) async -> Data? {
    guard let identifier = await deviceManager.connectedIdentifier(for: controller),
      let state = await automaticUserSpaceDispatcher()?.virtualOutputState(for: identifier)
    else { return nil }
    return try? JSONEncoder().encode(ApplicationServiceVirtualOutputState(state))
  }

  /// Returns the recent packet log of the controller `controller` names as encoded JSON data.
  public func getPacketLog(for controller: ControllerReference) async -> Data {
    let log = await deviceManager.packetLog(for: controller)
    do { return try JSONEncoder().encode(log) } catch {
      print("[ApplicationServiceServer] getPacketLog encode error: \(error)")
      return Data()
    }
  }

  /// Sends one output command to the selected controller; `ControllerOutputResult` reports what
  /// became of it, including the rumble channels the controller lacks.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for controller: ControllerReference
  ) async -> ControllerOutputResult {
    await deviceManager.sendControllerOutput(command, for: controller)
  }

  /// Suspends the controller and returns the encoded result.
  public func suspendController(_ controller: ControllerReference) async -> Data {
    let result = await deviceManager.suspendController(controller)
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  /// Resumes the suspended controller and returns the encoded result.
  public func resumeController(_ controller: ControllerReference) async -> Data {
    let result = await deviceManager.resumeController(controller)
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  /// Disconnects the wireless controller and returns the encoded result.
  public func disconnectWirelessController(_ controller: ControllerReference) async -> Data {
    let result = await deviceManager.disconnectWirelessController(controller)
    return (try? JSONEncoder().encode(result)) ?? Data()
  }

  /// Returns the user-space virtual device status and the HID gamepads on the system as encoded
  /// JSON.
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

  /// Returns the per-stage frame timings of every connected controller as encoded JSON: the
  /// frames read within the last `lastSeconds` seconds of the uptime clock, or the whole ring when
  /// `lastSeconds` is nil.
  public func getFrameTimings(lastSeconds: Int?) async -> Data {
    let snapshot = await deviceManager.frameTimingsSnapshot(
      lastSeconds: lastSeconds,
      now: DispatchTime.now().uptimeNanoseconds
    )
    do { return try JSONEncoder().encode(snapshot) } catch {
      print("[ApplicationServiceServer] getFrameTimings encode error: \(error)")
      return Data()
    }
  }

  /// Clears the virtual HID profile overrides, publishes again and retargets every controller; true
  /// when all of it succeeded.
  public func resetSettings() async -> Bool {
    await virtualOutputTransitionCoordinator.enqueue { [weak self] in
      guard let self else { return false }
      return await self.performResetSettingsAsync()
    }
  }

  /// Clears the overrides, activates the backend if it is not live, and retargets the controllers.
  private func performResetSettingsAsync() async -> Bool {
    let cleared = resetVirtualHIDProfileSettings()
    let live = await performVirtualOutputBackendActivation()
    let retargeted = await retargetConnectedControllers()
    return cleared && live && retargeted
  }
}
