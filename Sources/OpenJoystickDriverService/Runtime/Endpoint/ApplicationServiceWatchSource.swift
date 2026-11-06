import Foundation
import OpenJoystickDriverKit

/// Reads controllers from the service in-process, for the endpoint's stream.
///
/// Holds the server weakly, because the server owns the endpoint that owns this source.
struct ApplicationServiceWatchSource: ControllerWatchSource {
  /// The server that supplies the controllers; nil once it is gone.
  weak var server: ApplicationServiceServer?

  /// Returns the connected controllers, with their virtual HID profiles described.
  func devices() async throws -> [ApplicationServiceDeviceDescription] {
    guard let server else { return [] }
    return server.describingVirtualHIDProfiles(
      await server.deviceManager.connectedDeviceDescriptions().map {
        ($0.logicalControllerID, ApplicationServiceDeviceDescription(snapshot: $0))
      }
    )
  }

  /// Returns the current state of `device`, or nil when it is not connected.
  func state(of device: ApplicationServiceDeviceDescription) async throws -> ControllerState? {
    await server?.deviceManager.controllerState(for: .session(device.sessionToken))
  }

  /// Returns the virtual output state of `device`, or nil when no virtual output covers it.
  func output(
    of device: ApplicationServiceDeviceDescription
  ) async throws
    -> ApplicationServiceVirtualOutputState?
  {
    guard let server,
      let identifier = await server.deviceManager.connectedIdentifier(
        for: .session(device.sessionToken)
      ),
      let state = await server.automaticUserSpaceDispatcher()?.virtualOutputState(for: identifier)
    else { return nil }
    return ApplicationServiceVirtualOutputState(state)
  }
}
