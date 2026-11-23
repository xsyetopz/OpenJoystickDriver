import Testing

@testable import OpenJoystickDriverKit

/// The rumble template of a `HIDDescriptor` record, which the driver encodes into a HID report.
struct HIDDescriptorRumbleTests {
  private static let model = ControllerModelID(vendorID: 0x2DC8, productID: 0x301B)
  private static let running = RumbleIntensities(lowFrequency: UnipolarValue(0x8000))

  private static func template(resend: Int? = nil) throws -> RumbleOutputTemplate {
    try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .output, reportID: 2, length: 8)),
      motors: [.lowFrequency: .init(byte: 3), .highFrequency: .init(byte: 2)],
      resendIntervalMilliseconds: resend
    )
  }

  @Test
  func driverWithoutTemplateHasNoOutput() {
    let driver = HIDDescriptorDriver(model: Self.model)
    #expect(driver.outputCapabilities == .none)
    #expect(throws: ControllerOutputError.self) {
      try driver.encode(.setRumble(Self.running, duration: .held))
    }
  }

  @Test
  func templateGivesDriverRumbleAndEncodesItIntoHIDReport() throws {
    let driver = HIDDescriptorDriver(
      model: Self.model,
      usageMap: nil,
      rumbleTemplate: try Self.template()
    )
    #expect(driver.outputCapabilities == .dualMainRumble)
    let writes = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    guard case .hidOutput(let report)? = writes.first else {
      Issue.record("no HID output report: \(writes)")
      return
    }
    #expect(report.bytes == [2, 0, 0, 0x80, 0, 0, 0, 0])
  }

  @Test
  func resendIntervalRepeatsLastReportWhileMotorRuns() throws {
    let driver = HIDDescriptorDriver(
      model: Self.model,
      usageMap: nil,
      rumbleTemplate: try Self.template(resend: 40)
    )
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 40_000_000)
    #expect(driver.keepAliveWrites().isEmpty)
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(driver.keepAliveWrites() == sent)
    _ = try driver.encode(.stopRumble)
    #expect(driver.keepAliveWrites().isEmpty)
  }

  /// The DragonRise reports Linux `hid-dr.c` sends: `0x51` with both motors, the `FA FE` commit,
  /// and `F3 00` to stop.
  @Test
  func followUpAndStopReportsReachHIDWrites() throws {
    let template = try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .output, reportID: 0, length: 7)),
      bytes: [0x51, 0, 0, 0, 0, 0, 0],
      motors: [.highFrequency: .init(byte: 2), .lowFrequency: .init(byte: 4)],
      followUp: [[0xFA, 0xFE, 0, 0, 0, 0, 0]],
      stop: [0xF3, 0, 0, 0, 0, 0, 0]
    )
    let driver = HIDDescriptorDriver(model: Self.model, usageMap: nil, rumbleTemplate: template)
    let report = { (bytes: [UInt8]) in
      PhysicalOutputWrite.hidOutput(PhysicalHIDOutputReport(reportID: 0, bytes: bytes))
    }
    let sent = try driver.encode(.setRumble(Self.running, duration: .held)).writes
    #expect(sent == [report([0x51, 0, 0, 0, 0x80, 0, 0]), report([0xFA, 0xFE, 0, 0, 0, 0, 0])])
    let stopped = try driver.encode(.stopRumble).writes
    #expect(stopped == [report([0xF3, 0, 0, 0, 0, 0, 0])])
  }
}
