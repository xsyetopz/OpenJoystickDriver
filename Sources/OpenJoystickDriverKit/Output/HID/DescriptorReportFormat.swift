import Foundation
import IOKit
import IOKit.hid

/// Builds input reports according to a HID report descriptor (subset parser).
///
/// This is used for Compatibility identities where consumers switch behavior based on VID/PID
/// (often SDL-based). In those cases, spoofing VID/PID alone is not enough: the descriptor and
/// report bytes must match what the consumer expects.
public struct HIDDescriptorReportFormat: VirtualGamepadReportFormat, @unchecked Sendable {
  public let descriptor: [UInt8]
  public let inputReportPayloadSize: Int
  public let inputReportID: UInt8?
  public let outputReportPayloadSize: Int?
  public let outputReportID: UInt8?

  private let packer: HIDReportPacker

  public enum Error: Swift.Error, CustomStringConvertible, Sendable {
    case noSuitableInputReport
    case cannotParseDescriptor

    public var description: String {
      switch self {
      case .noSuitableInputReport:
        return "Descriptor does not contain a usable GamePad-style input report (buttons/axes/hat)."
      case .cannotParseDescriptor: return "Failed to parse HID report descriptor."
      }
    }
  }

  public init(
    descriptor: [UInt8],
    outputReportID: UInt8? = nil,
    outputReportPayloadSize: Int? = nil,
    buttonUsageMap: [Int: Int] = [:]
  ) throws {
    self.descriptor = descriptor
    guard let parsed = HIDReportDescriptorParser.parse(descriptor: descriptor) else {
      throw Error.cannotParseDescriptor
    }
    guard
      let packer = HIDReportPacker.bestEffortGamepadPacker(
        from: parsed,
        buttonUsageMap: buttonUsageMap
      )
    else { throw Error.noSuitableInputReport }
    self.packer = packer
    self.inputReportID = packer.reportID == 0 ? nil : packer.reportID
    self.inputReportPayloadSize = packer.payloadSizeBytes
    self.outputReportID = outputReportID
    self.outputReportPayloadSize = outputReportPayloadSize
  }

  public func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    packer.pack(state: state)
  }

  // MARK: - Descriptor sourcing helpers

  /// Copies the HID report descriptor from a currently connected physical HID device.
  ///
  /// This avoids hardcoding descriptor bytes in the repo and lets developers confirm
  /// the exact descriptor used by their controller on their macOS build.
  public static func copyPhysicalReportDescriptor(vendorID: Int, productID: Int) -> [UInt8]? {
    copyPhysicalReportDescriptor(vendorID: vendorID, productID: productID, preferredTransport: nil)
  }

  /// Copies the HID report descriptor from a currently connected physical HID device,
  /// optionally preferring a specific transport ("USB", "Bluetooth", ...).
  ///
  /// This function explicitly filters out OpenJoystickDriver-created virtual devices.
  @available(macOS, introduced: 10.15, obsoleted: 15.0)
  public static func copyPhysicalReportDescriptor(
    vendorID: Int,
    productID: Int,
    preferredTransport: String?
  ) -> [UInt8]? {
    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: vendorID, kIOHIDProductIDKey as String: productID
    ]
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
    _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) }

    let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []

    func strProp(_ dev: IOHIDDevice, _ key: String) -> String? {
      IOHIDDeviceGetProperty(dev, key as CFString) as? String
    }

    func score(_ dev: IOHIDDevice) -> Int {
      let transport = strProp(dev, kIOHIDTransportKey as String)
      let serial = strProp(dev, kIOHIDSerialNumberKey as String) ?? strProp(dev, "SerialNumber")
      // Exclude OJD virtual devices.
      if UserSpaceVirtualDeviceConstants.isOJDUserSpaceSerial(serial)
        || !PhysicalHIDBackendEventAdapter().acceptsDescriptor(
          syntheticProperty: IOHIDDeviceGetProperty(dev, "kIOHIDGCSyntheticDeviceKey" as CFString)
        )
      {
        return Int.min / 2
      }

      var s = 0
      if let preferredTransport, let transport, transport == preferredTransport { s += 10_000 }
      if let transport, transport != "Virtual" { s += 1_000 }
      if transport == "USB" { s += 100 }
      return s
    }

    let candidates = devices.map { ($0, score($0)) }.sorted { a, b in a.1 > b.1 }

    for (dev, s) in candidates {
      if s <= Int.min / 4 { continue }
      if let data = IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data {
        return [UInt8](data)
      }
    }
    return nil
  }
}
