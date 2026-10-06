import Foundation

/// Owns the current virtual state and the exact report exposed through both push and get-report
/// APIs.
final class UserSpaceInputReportState: Sendable {
  private struct Current {
    var state = VirtualGamepadState()
    var report: [UInt8]
    var remapped = false
    /// The input report input delivery last published; nil once another path published.
    var deliveredReport: [UInt8]?
    /// The auxiliary input reports last handed to delivery, index-aligned with the format's.
    var deliveredAuxiliaryReports: [[UInt8]]
    /// Set once the published device closes; host report requests then fail.
    var closed = false
  }

  private let format: any VirtualGamepadReportFormat
  private let current: Locked<Current>

  var isRemapped: Bool { current.withLock { $0.remapped } }

  init(format: any VirtualGamepadReportFormat) {
    self.format = format
    let neutral = VirtualGamepadState()
    self.current = Locked(
      Current(
        report: format.buildInputReport(from: neutral),
        deliveredAuxiliaryReports: format.buildAuxiliaryInputReports(from: neutral)
      )
    )
  }

  /// The controller state last built.
  func currentState() -> VirtualGamepadState { current.withLock { $0.state } }

  func update(remapped: Bool = false, _ body: (inout VirtualGamepadState) -> Void) -> [UInt8] {
    current.withLock { current in
      current.remapped = remapped
      body(&current.state)
      current.report = format.buildInputReport(from: current.state)
      return current.report
    }
  }

  func currentReport() -> [UInt8] { current.withLock { $0.report } }

  /// Records `report` for delivery and returns whether consumers do not hold it yet.
  func claimDelivery(of report: [UInt8]) -> Bool {
    current.withLock { current in
      guard report != current.deliveredReport else { return false }
      current.deliveredReport = report
      return true
    }
  }

  /// The auxiliary input reports whose bytes differ from those last returned here.
  func claimChangedAuxiliaryReports() -> [[UInt8]] {
    current.withLock { current in
      let reports = format.buildAuxiliaryInputReports(from: current.state)
      let changed = reports.enumerated().filter { index, report in
        index >= current.deliveredAuxiliaryReports.count
          || current.deliveredAuxiliaryReports[index] != report
      }.map(\.element)
      current.deliveredAuxiliaryReports = reports
      return changed
    }
  }

  func reset() -> [UInt8] {
    current.withLock { current in
      current.state = VirtualGamepadState()
      current.remapped = false
      current.deliveredReport = nil
      current.report = format.buildInputReport(from: current.state)
      return current.report
    }
  }

  func close() { current.withLock { $0.closed = true } }

  var isClosed: Bool { current.withLock { $0.closed } }

  /// The command a host output report requests of this device's format.
  func consumerOutput(
    _ request: VirtualHostReportRequest
  ) throws(VirtualHostReportError) -> ControllerOutputCommand {
    guard request.type == .output else { throw .unsupported }
    return try ConsumerOutputCodec.decode(request, in: format)
  }

  /// The current input report a host requests, bounded to `maxSize` and including its ID when the
  /// format declares one; the format answers no other report.
  func hostReport(type: VirtualHostReportType, reportID: UInt32, maxSize: Int) throws -> [UInt8] {
    try current.withLock { current in
      guard !current.closed else { throw VirtualHostReportError.closed }
      guard maxSize > 0, let identifier = UInt8(exactly: reportID) else {
        throw VirtualHostReportError.malformed
      }
      guard type == .input, identifier == format.inputReportID ?? 0 else {
        throw VirtualHostReportError.unsupported
      }
      return Array(current.report.prefix(maxSize))
    }
  }
}
