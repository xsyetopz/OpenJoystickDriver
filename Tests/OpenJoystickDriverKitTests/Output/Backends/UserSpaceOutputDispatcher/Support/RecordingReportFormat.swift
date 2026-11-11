import Foundation

@testable import OpenJoystickDriverKit

/// A persona's real report format that remembers the state each input report was built from, so a
/// test reads delivered report bytes back as controller state without decoding the persona's
/// layout.
final class RecordingReportFormat: VirtualGamepadReportFormat, @unchecked Sendable {
  private let base: any VirtualGamepadReportFormat
  private let lock = NSLock()
  private var states: [[UInt8]: VirtualGamepadState] = [:]

  /// The format `persona` publishes.
  init(persona: VirtualHIDProfileID) {
    base = persona.makeProfile().reportFormat
  }

  var descriptor: [UInt8] { base.descriptor }
  var inputReportPayloadSize: Int { base.inputReportPayloadSize }
  var inputReportID: UInt8? { base.inputReportID }
  var outputReportPayloadSize: Int? { base.outputReportPayloadSize }
  var outputReportID: UInt8? { base.outputReportID }

  func buildInputReport(from state: VirtualGamepadState) -> [UInt8] {
    let report = base.buildInputReport(from: state)
    lock.withLock { states[report] = state }
    return report
  }

  func buildAuxiliaryInputReports(from state: VirtualGamepadState) -> [[UInt8]] {
    base.buildAuxiliaryInputReports(from: state)
  }

  /// The state `report` was built from.
  func state(of report: [UInt8]) -> VirtualGamepadState? { lock.withLock { states[report] } }
}
