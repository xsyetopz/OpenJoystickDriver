/// One HID report a controller record names by kind, report ID and byte length. The length
/// counts the report-ID byte, which leads the report when the ID is nonzero.
public struct ControllerTemplateReport: Hashable, Sendable {
  /// `output` or `feature`; a record never writes an input report.
  public let kind: PhysicalHIDReportKind
  public let reportID: UInt8
  public let length: Int

  /// The byte offsets a template may set: every byte after a nonzero report ID.
  var writableBytes: Range<Int> { (reportID == 0 ? 0 : 1)..<length }

  init(kind: PhysicalHIDReportKind, reportID: UInt8, length: Int) {
    self.kind = kind
    self.reportID = reportID
    self.length = length
  }
}

/// A controller record's rumble report: every byte is zero except the report ID and one
/// intensity byte (0–255) per motor. It drives a vendor rumble report without its own driver.
public struct RumbleOutputTemplate: Equatable, Sendable {
  /// Motors a template may name. Trackpad haptics belong to the Steam drivers.
  static let templateMotors: [PhysicalRumbleMotor] = [
    .leftMain, .rightMain, .leftTrigger, .rightTrigger,
  ]

  public let report: ControllerTemplateReport
  /// The byte offset of each motor's intensity.
  public let motorBytes: [PhysicalRumbleMotor: Int]

  /// Fails unless the report is an output or feature report, at least one template motor is
  /// named, and every motor byte is a distinct writable byte of the report.
  init(
    report: ControllerTemplateReport,
    motorBytes: [PhysicalRumbleMotor: Int]
  )
    throws(ControllerRecordProblem)
  {
    guard report.kind != .input else {
      throw ControllerRecordProblem("a rumble template writes an output or feature report")
    }
    guard (2...64).contains(report.length) else {
      throw ControllerRecordProblem("a rumble report is 2...64 bytes long")
    }
    guard !motorBytes.isEmpty,
      motorBytes.keys.allSatisfy(Self.templateMotors.contains)
    else { throw ControllerRecordProblem("a rumble template names at least one motor") }
    guard motorBytes.values.allSatisfy(report.writableBytes.contains),
      Set(motorBytes.values).count == motorBytes.count
    else {
      throw ControllerRecordProblem(
        "rumble motor bytes must be distinct and follow the report ID inside the report"
      )
    }
    self.report = report
    self.motorBytes = motorBytes
  }

  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    PhysicalControllerOutputCapabilities(rumbleMotors: Array(motorBytes.keys))
  }

  /// Rumble through this template; the motors run until the next report.
  func encode(
    _ command: ControllerOutputCommand
  ) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch command {
    case .setRumble(let intensities, _): PhysicalOutputPlan(writes: [write(intensities)])
    case .stopRumble: PhysicalOutputPlan(writes: [write(.off)])
    default: throw .unsupportedCapability(command.capability)
    }
  }

  /// The report carrying these intensities; motors the template does not name are dropped.
  func write(_ intensities: RumbleIntensities) -> PhysicalOutputWrite {
    var bytes = [UInt8](repeating: 0, count: report.length)
    if report.reportID != 0 { bytes[0] = report.reportID }
    for (motor, offset) in motorBytes { bytes[offset] = intensities[motor].byte }
    let hidReport = PhysicalHIDOutputReport(reportID: report.reportID, bytes: bytes)
    return report.kind == .feature ? .hidFeature(hidReport) : .hidOutput(hidReport)
  }
}
