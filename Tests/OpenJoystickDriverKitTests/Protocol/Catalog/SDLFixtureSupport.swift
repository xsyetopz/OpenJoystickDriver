import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A pad's element list, device identity, database line and the usage map the line must give, read
/// from `SDLMappingFixtures/`.
struct SDLMappingFixture: Decodable {
  /// The identity SDL builds the GUID from.
  struct Device: Decodable {
    let vendorID: UInt16
    let productID: UInt16
    let version: UInt16
    let manufacturer: String?
    let product: String
  }

  let note: String
  let device: Device
  let elements: [HIDElementDescription]
  let line: String
  let expectedTier: String
  /// The entries of the usage map as `page/usage kind control [detail]`; the order is not significant.
  let expected: [String]
  /// The database control names the conversion leaves out, in line order.
  let expectedUnmapped: [String]

  /// The fixture files, by name.
  static func all() throws -> [String: SDLMappingFixture] {
    let urls = try #require(
      Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "SDLMappingFixtures")
    )
    return try Dictionary(
      uniqueKeysWithValues: urls.map {
        (
          $0.deletingPathExtension().lastPathComponent,
          try JSONDecoder().decode(Self.self, from: Data(contentsOf: $0))
        )
      }
    )
  }

  /// The physical device the fixture describes, over one HID interface that lists its elements.
  var physicalDevice: PhysicalDevice {
    PhysicalDevice(
      vendorID: device.vendorID,
      productID: device.productID,
      deviceRelease: device.version,
      manufacturer: device.manufacturer,
      productName: device.product,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(
            reportDescriptor: Data(GamepadHIDDescriptor.descriptor),
            elements: elements
          )
        )
      ]
    )
  }

  /// The database line's comma-separated fields after the name.
  var fields: [String] {
    Array(line.split(separator: ",", omittingEmptySubsequences: true).map(String.init).dropFirst(2))
  }
}

extension HIDUsageMap {
  /// The entries as `page/usage kind control [detail]`, the way the fixtures write them.
  var rendered: [String] {
    entries.map { entry in
      let usage = "\(entry.usage.usagePage)/\(entry.usage.usage)"
      return switch entry.binding {
      case .button(let control): "\(usage) button \(control.rawValue)"
      case .buttonTrigger(let control): "\(usage) buttonTrigger \(control.rawValue)"
      case .axis(let axis):
        "\(usage) axis \(axis.control.rawValue)" + (axis.isInverted ? " inverted" : "")
      case .hat: "\(usage) hat"
      case .halfAxis(let half):
        "\(usage) halfAxis \(half.control.rawValue) \(half.half.rawValue)"
          + (half.isInverted ? " inverted" : "")
      case .axisDpad(let half):
        "\(usage) axisDpad \(half.control.rawValue) \(half.half.rawValue) \(half.threshold)"
      case .axisButton(let half):
        "\(usage) axisButton \(half.control.rawValue) \(half.half.rawValue) \(half.threshold)"
      }
    }
  }
}

/// An input element of the given usage, listed at `order`.
func sdlElement(
  _ page: UInt32,
  _ usage: UInt32,
  cookie: UInt32? = nil,
  order: Int,
  range: ClosedRange<Int> = 0...255
) -> HIDElementDescription {
  HIDElementDescription(
    usagePage: page,
    usage: usage,
    cookie: cookie ?? UInt32(100 + order),
    logicalMinimum: range.lowerBound,
    logicalMaximum: range.upperBound,
    arrivalOrder: order
  )
}
