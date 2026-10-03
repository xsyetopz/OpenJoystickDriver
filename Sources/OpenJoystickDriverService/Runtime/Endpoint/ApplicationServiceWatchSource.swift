import Foundation
import OpenJoystickDriverKit

/// Reads controllers from the service in-process, for the endpoint's stream.
///
/// Holds the server weakly, because the server owns the endpoint that owns this source.
struct ApplicationServiceWatchSource: ControllerWatchSource {
  weak var server: ApplicationServiceServer?

  func devices() async throws -> [ApplicationServiceDeviceDescription] {
    guard let server else { return [] }
    return server.describingVirtualHIDProfiles(await server.connectedDevices())
  }

  func state(of device: ApplicationServiceDeviceDescription) async throws -> ControllerState? {
    await server?.deviceManager.controllerState(
      for: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID),
      runtimeIdentifier: device.runtimeIdentifier
    )
  }

  func output(
    of device: ApplicationServiceDeviceDescription
  ) async throws
    -> ApplicationServiceVirtualOutputState?
  {
    guard
      let state = await server?.automaticUserSpaceDispatcher()?.virtualOutputState(
        matching: DeviceIdentifier(vendorID: device.vendorID, productID: device.productID),
        runtimeIdentifier: device.runtimeIdentifier
      )
    else { return nil }
    return ApplicationServiceVirtualOutputState(state)
  }
}
