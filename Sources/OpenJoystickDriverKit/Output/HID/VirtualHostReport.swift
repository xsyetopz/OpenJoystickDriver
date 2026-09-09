import Foundation

enum VirtualHostReportType: Sendable { case input, output, feature }

enum VirtualHostReportError: Error, Equatable, Sendable {
  case unsupported
  case malformed
  case tooLarge
  case closed
}

/// The protocol boundary never guesses framing from a payload's first byte.
struct VirtualHostReportRequest: Sendable {
  enum Framing: Sendable {
    /// Numbered reports include their ID as byte zero; unnumbered reports contain only data.
    case completeReport
    /// The caller has already removed the report ID.
    case payload
  }

  let type: VirtualHostReportType
  let reportID: UInt8
  let payload: [UInt8]

  init(type: VirtualHostReportType, reportID: UInt32, bytes: [UInt8], framing: Framing) throws {
    guard let identifier = UInt8(exactly: reportID) else { throw VirtualHostReportError.malformed }
    self.type = type
    self.reportID = identifier
    if framing == .completeReport, identifier != 0 {
      guard bytes.first == identifier else { throw VirtualHostReportError.malformed }
      payload = Array(bytes.dropFirst())
    } else {
      payload = bytes
    }
  }

  var completeReport: [UInt8] { reportID == 0 ? payload : [reportID] + payload }
}

struct VirtualHostReportResponse: Sendable {
  var inputReport: [UInt8]?
  var rumble: VirtualRumbleCommand?

  /// Nintendo acknowledgements carry the latest controller state when they reach the sender.
  func reports(currentInput: [UInt8]) -> [[UInt8]] {
    guard var report = inputReport else { return [] }
    if report.first == 0x21, currentInput.first == 0x30, report.count >= 13,
      currentInput.count >= 13
    {
      report.replaceSubrange(1..<13, with: currentInput[1..<13])
    }
    return [report]
  }
}
