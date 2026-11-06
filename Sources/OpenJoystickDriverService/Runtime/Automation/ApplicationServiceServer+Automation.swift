import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer: AutomationService {
  /// Returns the controllers that the service drives.
  package func connectedDevices() async -> [ApplicationServiceDeviceDescription] {
    await deviceManager.connectedDeviceDescriptions().map(
      ApplicationServiceDeviceDescription.init(snapshot:)
    )
  }
}
