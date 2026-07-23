import OpenJoystickDriverKit

struct ConnectedControllersStatus: Sendable {
  let isAvailable: Bool
  let descriptions: [ApplicationServiceDeviceDescription]

  init(descriptions: [ApplicationServiceDeviceDescription]) {
    self.isAvailable = true
    self.descriptions = descriptions
  }

  private init() {
    self.isAvailable = false
    self.descriptions = []
  }

  static let unavailable = Self()

  var count: Int? { isAvailable ? descriptions.count : nil }
}
