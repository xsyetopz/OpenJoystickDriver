import Foundation

/// Owns the current virtual state and the exact report exposed through both push and get-report
/// APIs.
final class UserSpaceInputReportState: @unchecked Sendable {
  let hostSession: VirtualHostProtocolSession
  private let format: any VirtualGamepadReportFormat
  private let lock = NSLock()
  private var state = VirtualGamepadState()
  private var report: [UInt8]

  init(format: any VirtualGamepadReportFormat) {
    self.hostSession = VirtualHostProtocolSession(format: format)
    self.format = format
    self.report = format.buildInputReport(from: VirtualGamepadState())
  }

  func update(_ body: (inout VirtualGamepadState) -> Void) -> [UInt8] {
    lock.withLock {
      body(&state)
      report = format.buildInputReport(from: state)
      return report
    }
  }

  func currentReport() -> [UInt8] { lock.withLock { report } }
}
