import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct InputClaimRetryTests {
  /// While another client seizes a device, macOS refuses OJD's shared open as well, so a device
  /// with a refused seize has no shared open and is still retried.
  @Test
  func everyTrackedDeviceAtLocationWithRefusedOrFailedSeizeIsRetried() {
    let ownerships: [UInt64: HIDInputOwnership] = [
      10: .ownedByAnotherClient, 11: .acquisitionFailed, 12: .exclusive, 20: .ownedByAnotherClient,
    ]
    let tracked: [UInt64: HIDDeviceConnection] = [
      10: Self.connection(locationID: 1), 11: Self.connection(locationID: 1),
      12: Self.connection(locationID: 1), 20: Self.connection(locationID: 2),
    ]

    let candidates = HIDDeviceStream.inputClaimRetryCandidates(
      tracked: tracked,
      locationID: 1
    ) { ownerships[$0] }

    #expect(candidates == [10, 11])
  }

  private static func connection(locationID: UInt32) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: 0x0268,
        productName: "PLAYSTATION(R)3 Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}
