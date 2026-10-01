/// One fixed report a controller record sends when OJD starts a controller it owns, after the
/// driver's own startup writes. It suits a pad whose enable sequence never changes.
public struct RecordStartupWrite: Equatable, Sendable {
  /// Transports a startup write may be limited to; OJD reaches a HID controller over these.
  static let transports: [PhysicalTransport] = [.usb, .bluetoothClassic, .bluetoothLE]

  public let report: ControllerTemplateReport
  /// Every byte after a nonzero report ID, or the whole report when the ID is zero.
  public let bytes: [UInt8]
  /// The wait before this write, after the previous one.
  public let delayMilliseconds: Int
  /// The only transport this write is sent on; nil sends it on every transport.
  public let transport: PhysicalTransport?

  /// Fails unless the report is an output or feature report, `bytes` fills every writable byte
  /// of it, the delay is 0...1000 ms, and the transport is one a HID controller uses.
  init(
    report: ControllerTemplateReport,
    bytes: [UInt8],
    delayMilliseconds: Int = 0,
    transport: PhysicalTransport? = nil
  )
    throws(ControllerRecordProblem)
  {
    guard report.kind != .input else {
      throw ControllerRecordProblem("a startup write sends an output or feature report")
    }
    guard (2...64).contains(report.length) else {
      throw ControllerRecordProblem("a startup report is 2...64 bytes long")
    }
    guard bytes.count == report.writableBytes.count else {
      throw ControllerRecordProblem(
        "a startup write lists every byte after the report ID: \(report.writableBytes.count)"
      )
    }
    guard (0...1000).contains(delayMilliseconds) else {
      throw ControllerRecordProblem("a startup delay is 0...1000 ms")
    }
    guard transport.map(Self.transports.contains) ?? true else {
      throw ControllerRecordProblem("a startup transport is usb, bluetooth-classic or bluetooth-le")
    }
    self.report = report
    self.bytes = bytes
    self.delayMilliseconds = delayMilliseconds
    self.transport = transport
  }

  /// Whether this write is sent over `observed`, the controller's host transport.
  func applies(to observed: PhysicalTransport?) -> Bool {
    transport.map { $0 == observed } ?? true
  }

  /// The report this write sends.
  var write: PhysicalOutputWrite {
    let reportBytes = report.reportID == 0 ? bytes : [report.reportID] + bytes
    let hidReport = PhysicalHIDOutputReport(reportID: report.reportID, bytes: reportBytes)
    return report.kind == .feature ? .hidFeature(hidReport) : .hidOutput(hidReport)
  }
}
