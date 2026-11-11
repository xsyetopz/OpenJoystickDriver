import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct HIDSeizeDecisionTests {
  /// A HID object of a model the record reaches through raw USB is not a device OJD serves over
  /// HID, so the stream never seizes it.
  @Test
  func aHIDDeviceOfARawUSBModelIsNotSeized() throws {
    let catalog = DeviceCatalog()
    let model = try #require(catalog.rawUSBModels.first)

    #expect(
      !HIDDeviceStream.seizesInput(
        model: model,
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: catalog
      )
    )
  }

  @Test
  func aHIDDeviceOfAHIDModelIsSeized() throws {
    let catalog = DeviceCatalog()
    let model = try #require(catalog.hidModels.first)

    #expect(
      HIDDeviceStream.seizesInput(
        model: model,
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: catalog
      )
    )
  }

  /// A model with no record is served from its HID descriptor, so it is seized.
  @Test
  func aHIDDeviceWithNoRecordIsSeized() {
    #expect(
      HIDDeviceStream.seizesInput(
        model: ControllerModelID(vendorID: 0xFFFF, productID: 0xFFFF),
        nativePassThrough: false,
        siblingIsNative: false,
        catalog: DeviceCatalog()
      )
    )
  }

  @Test
  func aNativeGamepadAndItsSiblingAreNotSeized() throws {
    let catalog = DeviceCatalog()
    let model = try #require(catalog.hidModels.first)

    #expect(
      !HIDDeviceStream.seizesInput(
        model: model, nativePassThrough: true, siblingIsNative: false, catalog: catalog)
    )
    #expect(
      !HIDDeviceStream.seizesInput(
        model: model, nativePassThrough: false, siblingIsNative: true, catalog: catalog)
    )
  }
}
