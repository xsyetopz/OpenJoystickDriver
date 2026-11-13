import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct OwnershipReevaluationTests {
  private static let changedModel = ControllerModelID(vendorID: 0x3537, productID: 0x100B)

  /// Only the locations where a listed model's native flag changed are cycled, siblings included.
  @Test
  func reevaluationCyclesEveryDeviceAtLocationWhoseNativeFlagChanged() {
    let changed = Self.gameSir(productID: 0x100B, locationID: 1, native: true)
    let sibling = Self.gameSir(productID: 0x100B, locationID: 1, native: true, interface: 1)
    let unchanged = Self.gameSir(productID: 0x100B, locationID: 2, native: false)
    let unlisted = Self.gameSir(productID: 0x1053, locationID: 3, native: true)
    let tracked: [UInt64: HIDDeviceConnection] = [
      10: changed, 11: sibling, 20: unchanged, 30: unlisted,
    ]

    let cycled = HIDDeviceStream.ownershipReevaluation(
      tracked: tracked,
      models: [Self.changedModel]
    ) { deviceID, connection in
      HIDDeviceStream.Admission(
        nativePassThrough: deviceID == 10 ? false : connection.physicalDevice.nativePassThrough,
        systemListsGameController: false
      )
    }

    #expect(cycled == [10, 11])
  }

  /// A served device is admitted again when GameController starts or stops listing it, so the
  /// second-controller warning follows the list; a device macOS serves has no such warning.
  @Test(arguments: [(false, true), (true, false)])
  func reevaluationCyclesOnlyServedDeviceWhoseListingChanged(native: Bool, cycles: Bool) {
    let device = Self.gameSir(productID: 0x100B, locationID: 1, native: native)

    let cycled = HIDDeviceStream.ownershipReevaluation(
      tracked: [10: device],
      models: [Self.changedModel]
    ) { _, _ in
      HIDDeviceStream.Admission(nativePassThrough: native, systemListsGameController: true)
    }

    #expect(cycled == (cycles ? [10] : []))
  }

  private static func gameSir(
    productID: UInt16,
    locationID: UInt32,
    native: Bool,
    interface: UInt8 = 0
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x3537,
        productID: productID,
        productName: "GameSir",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: interface,
            hostTransport: .usb,
            accessBackend: .hid,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ],
        nativePassThrough: native
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}
