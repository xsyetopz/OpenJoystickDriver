import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct HIDSeizeDecisionTests {
  /// A device observed as a HID gamepad, or as one with no usable report descriptor.
  private static func device(_ model: ControllerModelID, gamepad: Bool = false) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      transportProperty: "USB",
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(
            hasGamePadOrJoystickCollection: gamepad,
            hasUsableElements: gamepad,
            primaryUsage: HIDUsageSignature(usagePage: 1, usage: gamepad ? 5 : 6),
            reportDescriptor: gamepad ? Data(GamepadHIDDescriptor.descriptor) : nil,
            reports: [PhysicalHIDReportSignature(kind: .input, reportIDs: [1])]
          )
        )
      ]
    )
  }

  /// A device with no record whose descriptor the classifier refuses is not served, so the stream
  /// never seizes it and another app still reads its input.
  @Test
  func hidDeviceWithNoRecordTheClassifierRefusesNotSeized() {
    #expect(
      !HIDDeviceStream.seizesInput(
        device: Self.device(ControllerModelID(vendorID: 0xFFFF, productID: 0xFFFF)),
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: DeviceCatalog()
      )
    )
  }

  /// A HID object of a model the record reaches through raw USB is not a device OJD serves over
  /// HID, so the stream never seizes it.
  @Test
  func hidDeviceOfRawUSBModelNotSeized() throws {
    let catalog = DeviceCatalog()
    let model = try #require(catalog.rawUSBModels.first)

    #expect(
      !HIDDeviceStream.seizesInput(
        device: Self.device(model),
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: catalog
      )
    )
  }

  @Test
  func hidDeviceOfHIDModelSeized() throws {
    let catalog = DeviceCatalog()
    let model = try #require(catalog.hidModels.first)

    #expect(
      HIDDeviceStream.seizesInput(
        device: Self.device(model),
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: catalog
      )
    )
  }

  /// A model with no record is served from its HID descriptor, so it is seized.
  @Test
  func hidDeviceWithNoRecordSeized() {
    #expect(
      HIDDeviceStream.seizesInput(
        device: Self.device(
          ControllerModelID(vendorID: 0xFFFF, productID: 0xFFFF),
          gamepad: true
        ),
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: DeviceCatalog()
      )
    )
  }

  @Test
  func nativeGamepadAndItsSiblingNotSeized() throws {
    let catalog = DeviceCatalog()
    let model = try #require(catalog.hidModels.first)

    #expect(
      !HIDDeviceStream.seizesInput(
        device: Self.device(model),
        nativePassThrough: true,
        siblingIsNative: false,
        catalog: catalog
      )
    )
    #expect(
      !HIDDeviceStream.seizesInput(
        device: Self.device(model),
        nativePassThrough: false,
        siblingIsNative: true,
        catalog: catalog
      )
    )
  }
}
