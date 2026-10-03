import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceServer: AutomationService {
  package func connectedDevices() async -> [ApplicationServiceDeviceDescription] {
    await deviceManager.connectedDeviceDescriptions().map(
      ApplicationServiceDeviceDescription.init(snapshot:)
    )
  }
}
