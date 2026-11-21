import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

/// PR #68 and issue #55: the extension route sends SET_CONFIGURATION only to a device that isn't
/// already in the requested configuration, because the request terminates the interface the
/// extension service runs on.
struct DriverKitConfigurationGateTests {
  private static let configureOne = USBTransportOpenOptions(configurationValue: 1)

  private static func parent(configuration: UInt8?) -> USBDriverKitParentDevice {
    USBDriverKitParentDevice(
      vendorID: 0x045E,
      productID: 0x02D1,
      currentConfiguration: configuration
    )
  }

  @Test
  func configuredParentReceivesNoSetConfiguration() {
    let parent = Self.parent(configuration: 1)

    let configuration = USBDriverKitTransportProvider.configurationToSet(
      options: Self.configureOne,
      parent: parent
    )

    #expect(configuration == nil)
  }

  @Test
  func unconfiguredParentReceivesSetConfiguration() {
    let parent = Self.parent(configuration: 0)

    let configuration = USBDriverKitTransportProvider.configurationToSet(
      options: Self.configureOne,
      parent: parent
    )

    #expect(configuration == 1)
  }

  @Test
  func unreadableParentReceivesSetConfiguration() {
    let configuration = USBDriverKitTransportProvider.configurationToSet(
      options: Self.configureOne,
      parent: nil
    )

    #expect(configuration == 1)
  }

  @Test
  func optionsWithoutConfigurationSendNone() {
    let parent = Self.parent(configuration: 0)

    let configuration = USBDriverKitTransportProvider.configurationToSet(
      options: USBTransportOpenOptions(),
      parent: parent
    )

    #expect(configuration == nil)
  }
}
