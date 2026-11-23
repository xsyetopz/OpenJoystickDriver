import Foundation

/// One raw write to a connected controller, for a controller-mod author who tries bytes before
/// writing a record.
///
/// The bytes are the whole report, as in ``ControllerTemplateReport``: a nonzero report ID leads
/// them, and an unnumbered report (ID 0) carries none.
public struct ControllerRawOutput: Codable, Equatable, Sendable {
  /// Where the bytes go.
  public enum Destination: String, Codable, CaseIterable, Sendable {
    /// A HID output report.
    case hidOutput = "HIDOutput"
    /// A HID feature report.
    case hidFeature = "HIDFeature"
    /// A USB interrupt OUT packet.
    case usbInterrupt = "USBInterrupt"
  }

  /// The most bytes one write carries.
  public static let maxByteCount = 64
  /// The transfer timeout of a USB packet, in milliseconds.
  static let usbTimeoutMilliseconds: UInt32 = 1_000

  /// Where the bytes go.
  public let destination: Destination
  /// The HID report ID; zero for an unnumbered report and for USB.
  public let reportID: UInt8
  /// The USB OUT endpoint; nil for HID.
  public let endpoint: UInt8?
  /// The bytes of the report or packet.
  public let bytes: [UInt8]

  /// Creates a write; ``isValid`` tells whether the controller may receive it.
  public init(
    destination: Destination,
    reportID: UInt8 = 0,
    endpoint: UInt8? = nil,
    bytes: [UInt8]
  ) {
    self.destination = destination
    self.reportID = reportID
    self.endpoint = endpoint
    self.bytes = bytes
  }

  /// Whether the write is well formed: 1 to ``maxByteCount`` bytes, a nonzero report ID leading
  /// the bytes, and an endpoint exactly for USB.
  public var isValid: Bool {
    guard (1...Self.maxByteCount).contains(bytes.count) else { return false }
    switch destination {
    case .hidOutput, .hidFeature:
      return endpoint == nil && (reportID == 0 || bytes[0] == reportID)
    case .usbInterrupt: return reportID == 0 && endpoint != nil
    }
  }

  /// The write the pipeline performs.
  var write: PhysicalOutputWrite {
    let report = PhysicalHIDOutputReport(reportID: reportID, bytes: bytes)
    switch destination {
    case .hidOutput: return .hidOutput(report)
    case .hidFeature: return .hidFeature(report)
    case .usbInterrupt:
      return .usb(
        PhysicalUSBOutputPacket(
          endpoint: endpoint ?? 0,
          bytes: bytes,
          timeoutMilliseconds: Self.usbTimeoutMilliseconds
        )
      )
    }
  }

  /// The bytes of `text`, hex pairs of either case separated by whitespace; nil for anything else.
  public static func parseHex(_ text: String) -> [UInt8]? {
    let pairs = text.split(whereSeparator: \.isWhitespace)
    let values = pairs.compactMap { pair -> UInt8? in
      pair.count == 2 && pair.allSatisfy(\.isHexDigit) ? UInt8(pair, radix: 16) : nil
    }
    return !pairs.isEmpty && values.count == pairs.count ? values : nil
  }

  /// The bytes as uppercase hex pairs separated by spaces.
  public var hex: String {
    bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16, uppercase: true) }
      .joined(separator: " ")
  }
}
