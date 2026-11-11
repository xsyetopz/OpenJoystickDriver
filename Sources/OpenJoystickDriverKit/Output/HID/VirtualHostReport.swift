import Foundation

/// The kind of a HID report that the host requests.
public enum VirtualHostReportType: Sendable {
  /// An input report.
  case input
  /// An output report.
  case output
  /// A feature report.
  case feature
}

/// Why a host report request fails.
package enum VirtualHostReportError: Error, Equatable, Sendable {
  /// The format declares no such report.
  case unsupported
  /// The length or header does not match the report ID.
  case malformed
  /// The payload is larger than the report the format declares.
  case tooLarge
  /// The dispatcher is closed.
  case closed
}

/// A complete report from the host.
///
/// A numbered report includes its ID as byte zero; an unnumbered report holds only data.
struct VirtualHostReportRequest: Sendable {
  /// The kind of the report.
  let type: VirtualHostReportType
  /// The report ID; 0 for an unnumbered report.
  let reportID: UInt8
  /// The bytes after the report ID.
  let payload: [UInt8]

  /// Creates a request from the report ID and bytes that the host sent.
  ///
  /// - Throws: ``VirtualHostReportError/malformed`` when `reportID` exceeds one byte, or when a
  ///   numbered report does not begin with its ID.
  init(type: VirtualHostReportType, reportID: UInt32, bytes: [UInt8]) throws {
    guard let identifier = UInt8(exactly: reportID) else { throw VirtualHostReportError.malformed }
    self.type = type
    self.reportID = identifier
    if identifier != 0 {
      guard bytes.first == identifier else { throw VirtualHostReportError.malformed }
      payload = Array(bytes.dropFirst())
    } else {
      payload = bytes
    }
  }
}
