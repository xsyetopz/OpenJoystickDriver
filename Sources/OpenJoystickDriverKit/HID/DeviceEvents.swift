import Foundation
import IOKit.hid

/// A semantic value decoded by IOKit from one HID input element.
public struct HIDElementValue: Sendable, Equatable {
  public let usagePage: UInt32
  public let usage: UInt32
  public let logicalMinimum: Int
  public let logicalMaximum: Int
  public let integerValue: Int

  public init(
    usagePage: UInt32,
    usage: UInt32,
    logicalMinimum: Int,
    logicalMaximum: Int,
    integerValue: Int
  ) {
    self.usagePage = usagePage
    self.usage = usage
    self.logicalMinimum = logicalMinimum
    self.logicalMaximum = logicalMaximum
    self.integerValue = integerValue
  }
}

/// An event from the IOKit HID subsystem for a class-0x03 controller.
///
/// ``HIDManager`` sends these to ``DeviceManager`` to report when a
/// HID controller is plugged in, unplugged, or sends an input report.
public enum HIDDeviceEvent: Sendable {
  /// A HID controller was plugged in. Carries its USB identifiers and name.
  case connected(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String?,
    locationID: UInt32,
    productName: String?,
    transport: String?
  )
  /// A previously connected HID controller was unplugged.
  case disconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
  /// The controller sent a raw input report (button presses, stick positions, etc.).
  case inputReport(locationID: UInt32, reportID: UInt8, data: Data)
  /// IOKit decoded one descriptor-defined input element.
  case inputValue(locationID: UInt32, value: HIDElementValue)
}
