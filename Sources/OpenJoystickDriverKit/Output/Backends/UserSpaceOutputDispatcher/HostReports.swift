import CoreHID
import Foundation
import IOKit.hid

/// Shared request contract for CoreHID and IOKit's synchronous report callbacks.
final class UserSpaceHostReportHandler: @unchecked Sendable {
  private let lock = NSLock()
  private let identifier: DeviceIdentifier
  private let input: UserSpaceInputReportState
  private let sender: UserSpaceReportSender
  private let isOpen: @Sendable () -> Bool
  private let onRumble: UserSpaceOutputDispatcher.RumbleCommandHandler?
  private let onRumbleStatus: @Sendable (String) -> Void

  init(
    identifier: DeviceIdentifier,
    input: UserSpaceInputReportState,
    sender: UserSpaceReportSender,
    isOpen: @escaping @Sendable () -> Bool,
    onRumble: UserSpaceOutputDispatcher.RumbleCommandHandler?,
    onRumbleStatus: @escaping @Sendable (String) -> Void
  ) {
    self.identifier = identifier
    self.input = input
    self.sender = sender
    self.isOpen = isOpen
    self.onRumble = onRumble
    self.onRumbleStatus = onRumbleStatus
  }

  /// Native callbacks follow the IOKit/HIDAPI convention: numbered buffers include byte-zero ID.
  /// Returning a task lets CoreHID await publication; IOKit acknowledges validated enqueueing.
  func setReport(
    type: VirtualHostReportType,
    reportID: UInt32,
    bytes: [UInt8]
  ) throws -> Task<Void, Error> {
    try lock.withLock {
      guard isOpen() else { throw VirtualHostReportError.closed }
      let request = try VirtualHostReportRequest(
        type: type,
        reportID: reportID,
        bytes: bytes,
        framing: .completeReport
      )
      let response = try input.hostSession.setReport(request)
      return sender.submit { [self] in
        guard isOpen() else { throw VirtualHostReportError.closed }
        if let command = response.rumble {
          let status =
            "app report id=\(reportID) L=\(command.left) R=\(command.right) "
            + "LT=\(command.leftTrigger) RT=\(command.rightTrigger)"
          onRumbleStatus(status)
          print("[UserSpaceOutputDispatcher] App rumble report: \(identifier) \(status)")
          onRumble?(identifier, command)
        }
        return response.reports(currentInput: input.currentReport())
      }
    }
  }

  func getReport(type: VirtualHostReportType, reportID: UInt32, maxSize: Int) throws -> [UInt8] {
    guard isOpen() else { throw VirtualHostReportError.closed }
    return try input.hostSession.getReport(
      type: type,
      reportID: reportID,
      maxSize: maxSize,
      currentInput: input.currentReport()
    )
  }

  static func reportType(_ type: IOHIDReportType) throws -> VirtualHostReportType {
    switch type {
    case kIOHIDReportTypeInput: .input
    case kIOHIDReportTypeOutput: .output
    case kIOHIDReportTypeFeature: .feature
    default: throw VirtualHostReportError.unsupported
    }
  }

  static func ioKitError(_ error: any Error) -> IOReturn {
    switch error {
    case VirtualHostReportError.unsupported: kIOReturnUnsupported
    case VirtualHostReportError.malformed: kIOReturnBadArgument
    case VirtualHostReportError.tooLarge: kIOReturnMessageTooLarge
    case VirtualHostReportError.closed: kIOReturnNotOpen
    case is CancellationError: kIOReturnAborted
    default: kIOReturnError
    }
  }

  @available(macOS 15, *)
  static func coreHIDError(_ error: any Error) -> HIDDeviceError {
    switch error {
    case let error as HIDDeviceError: error
    case VirtualHostReportError.unsupported: .unsupported
    case VirtualHostReportError.malformed: .badArgument
    case VirtualHostReportError.tooLarge: .messageTooLarge
    case VirtualHostReportError.closed: .notReady
    case is CancellationError: .aborted
    default: .ioError
    }
  }
}
