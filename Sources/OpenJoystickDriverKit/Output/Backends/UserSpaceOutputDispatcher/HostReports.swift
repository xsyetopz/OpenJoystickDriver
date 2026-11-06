import Foundation

/// Request contract for a virtual device's synchronous report callbacks.
package final class UserSpaceHostReportHandler: Sendable {
  /// Serializes consuming a request with enqueueing it, so publication follows callback order.
  private let lock = NSLock()
  /// The controller the device belongs to.
  private let identifier: LogicalControllerID
  /// The input report state of the device.
  private let input: UserSpaceInputReportState
  /// The sender that publishes the reports.
  private let sender: UserSpaceReportSender
  /// Whether the dispatcher is open.
  private let isOpen: @Sendable () -> Bool
  /// The handler for the output commands that the host sends; nil when none is set.
  private let onOutput: UserSpaceOutputDispatcher.OutputCommandHandler?
  /// The handler that receives the text of the latest rumble request.
  private let onRumbleStatus: @Sendable (String) -> Void

  /// Creates a handler from its parts.
  init(
    identifier: LogicalControllerID,
    input: UserSpaceInputReportState,
    sender: UserSpaceReportSender,
    isOpen: @escaping @Sendable () -> Bool,
    onOutput: UserSpaceOutputDispatcher.OutputCommandHandler?,
    onRumbleStatus: @escaping @Sendable (String) -> Void
  ) {
    self.identifier = identifier
    self.input = input
    self.sender = sender
    self.isOpen = isOpen
    self.onOutput = onOutput
    self.onRumbleStatus = onRumbleStatus
  }

  /// Native callbacks follow the IOKit/HIDAPI convention: numbered buffers include byte-zero ID.
  ///
  /// The callback acknowledges validated enqueueing, not publication.
  func setReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) throws -> UserSpaceReportSender.SubmissionReceipt {
    try lock.withLock {
      guard isOpen(), !input.isClosed else { throw VirtualHostReportError.closed }
      let request = try VirtualHostReportRequest(type: type, reportID: reportID, bytes: bytes)
      let command = try input.consumerOutput(request)
      return sender.submit { [self] in
        guard isOpen() else { throw VirtualHostReportError.closed }
        if let rumble = Self.rumbleIntensities(command) {
          let status =
            "app report id=\(reportID) L=\(rumble.lowFrequency.byte) "
            + "R=\(rumble.highFrequency.byte) LT=\(rumble.leftTrigger.byte) "
            + "RT=\(rumble.rightTrigger.byte)"
          onRumbleStatus(status)
          print("[UserSpaceOutputDispatcher] App rumble report: \(identifier) \(status)")
        }
        onOutput?(identifier, command)
        return []
      }
    }
  }

  /// Validates and enqueues a host set-report request; the native callback acknowledges only that.
  package func acknowledgeSetReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) throws {
    _ = try setReport(type: type, reportID: reportID, bytes: bytes)
  }

  /// The report of `type` and `reportID` that the host asks for, at most `maxSize` bytes.
  ///
  /// - Throws: ``VirtualHostReportError/closed`` when the dispatcher is closed, or the error of the
  ///   input report state.
  package func getReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    maxSize: Int
  ) throws -> [UInt8] {
    guard isOpen() else { throw VirtualHostReportError.closed }
    return try input.hostReport(type: type, reportID: reportID, maxSize: maxSize)
  }

  /// The requested rumble intensities of a rumble command; stop-rumble requests them all off.
  private static func rumbleIntensities(_ command: ControllerOutputCommand) -> RumbleIntensities? {
    switch command {
    case .setRumble(let intensities, _): intensities
    case .stopRumble: .off
    default: nil
    }
  }
}
