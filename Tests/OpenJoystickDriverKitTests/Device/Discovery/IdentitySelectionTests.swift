import Testing

@testable import OpenJoystickDriverKit

struct DeviceManagerIdentitySelectionTests {
  @Test func opaqueIdentifierMustBelongToRequestedModel() {
    let requestedModel = DeviceIdentifier(vendorID: 1, productID: 2)
    let requestedDevice = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let otherModelDevice = DeviceIdentifier(vendorID: 3, productID: 4, locationID: 2)

    let selected = DeviceManager.connectedIdentifier(
      among: [requestedDevice, otherModelDevice],
      matching: requestedModel,
      runtimeIdentifier: otherModelDevice.runtimeIdentifier
    )

    #expect(selected == nil)
  }

  @Test func opaqueIdentifierSelectsExactDeviceWithinRequestedModel() {
    let model = DeviceIdentifier(vendorID: 1, productID: 2)
    let first = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let second = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 2)

    let selected = DeviceManager.connectedIdentifier(
      among: [first, second],
      matching: model,
      runtimeIdentifier: second.runtimeIdentifier
    )

    #expect(selected == second)
  }
}
