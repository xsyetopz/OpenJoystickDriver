import Testing

@testable import OpenJoystickDriverKit

struct DeviceManagerIdentitySelectionTests {
  @Test
  func opaqueIdentifierMustBelongToRequestedModel() {
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

  @Test
  func opaqueIdentifierSelectsExactDeviceWithinRequestedModel() {
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

  @Test
  func virtualOutputFeedbackReachesTheOwningControllerAmongIdenticalModels() {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
    let second = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 2)

    // Without the exact runtime identifier, two same-model controllers are ambiguous.
    #expect(
      DeviceManager.connectedIdentifier(
        among: [first, second],
        matching: first,
        runtimeIdentifier: nil
      ) == nil
    )
    for owner in [first, second] {
      #expect(
        DeviceManager.connectedIdentifier(
          among: [first, second],
          matching: owner,
          runtimeIdentifier: owner.runtimeIdentifier
        ) == owner
      )
    }
  }
}
