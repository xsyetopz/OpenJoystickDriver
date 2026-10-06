import Foundation

enum VirtualHostReportType: Sendable { case input, output, feature }

enum VirtualHostReportError: Error, Equatable, Sendable {
  case unsupported
  case malformed
  case tooLarge
  case closed
}

/// A complete host report: numbered reports include their ID as byte zero; unnumbered reports
/// contain only data.
struct VirtualHostReportRequest: Sendable {
  let type: VirtualHostReportType
  let reportID: UInt8
  let payload: [UInt8]

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
