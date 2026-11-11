import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct SteamControllerDriverTests {
  static let family = PhysicalProtocolID.valveSteamController
  static let model = ControllerModelID(vendorID: 0x28DE, productID: 0x1102)

  @Test
  func testSteamControllerProfilesExposeOperationalFlags() throws {
    let registry = ProtocolDriverRegistry()
    let models = [
      ControllerModelID(vendorID: 10462, productID: 4354),
      ControllerModelID(vendorID: 10462, productID: 4418),
    ]

    let wired = try #require(registry.record(for: models[0]))
    #expect(
      wired.physicalProtocolID == .valveSteamController && wired.physicalProtocolVariant == .wired
    )
    #expect(wired.parameters.isEmpty)

    let wireless = try #require(registry.record(for: models[1]))
    #expect(
      wireless.physicalProtocolID == .valveSteamController
        && wireless.physicalProtocolVariant == .dongle
    )
    #expect(wireless.parameters.isEmpty)
  }

  @Test
  func testSteamControllerReportParsesPrimaryControls() throws {
    let parser = try catalogParser(ControllerModelID(vendorID: 10462, productID: 4354))
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(
        buttons: (0xFC, 0x70, 0x44),
        triggers: (255, 128),
        left: (32767, -32767),
        rightPad: (-32767, 32767)
      )
    )

    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.east)))
    #expect(events.contains(.press(.west)))
    #expect(events.contains(.press(.north)))
    #expect(events.contains(.press(.leftShoulder)))
    #expect(events.contains(.press(.rightShoulder)))
    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.leftStickClick)))
    #expect(events.contains(.press(.rightTrackpadClick)))
    #expect(events.contains(.leftTrigger(1.0)))
    #expect(events.contains(.rightTrigger(128.0 / 255.0)))
    #expect(events.contains(.leftStick(x: 1.0, y: 1.0)))
    #expect(events.contains(.rightStick(x: -1.0, y: -1.0)))
  }

  @Test
  func testSteamGripBitsHaveDistinctSources() throws {
    let parser = SteamControllerDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x80, 0x01))
    )
    #expect(events?.state.pressed == [.leftPaddle2, .rightPaddle2])
    let releases = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())
    #expect(releases?.state.pressed.isEmpty == true)
  }

  @Test
  func testLeftPadTouchDoesNotCreateVirtualLeftStickMotion() throws {
    let parser = SteamControllerDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0, 0x08), left: (32767, -32767))
    )

    #expect(!events.contains(.leftStick(x: 1.0, y: 1.0)))
  }

  @Test
  func testLeftPadAndJoyBitDoesNotReplaceStickWithPadCoordinates() throws {
    let parser = SteamControllerDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0, 0x88), left: (32767, -32767))
    )

    #expect(!events.contains(.leftStick(x: 1.0, y: 1.0)))
  }

  @Test
  func testLeftPadTouchStaysOmitted() throws {
    let parser = SteamControllerDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0, 0x80))
    )

    #expect(events?.state.pressed.isEmpty == true && events?.state.leftStick == .center)
  }

  @Test
  func testSteamControllerReportParsesDpadDirections() throws {
    let parser = SteamControllerDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport())

    let upEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x01, 0))
    )
    let rightEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x02, 0))
    )
    let downEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x08, 0))
    )
    let leftEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x04, 0))
    )

    #expect(upEvents.contains(.hat(.north)))
    #expect(rightEvents.contains(.hat(.east)))
    #expect(downEvents.contains(.hat(.south)))
    #expect(leftEvents.contains(.hat(.west)))
  }

  @Test
  func testSteamControllerDisablesAndRestoresLizardModeWithFeatureReports() {
    let parser = SteamControllerDriver()

    let startup = parser.activationWrites().hidFeatures
    #expect(startup.map(\.reportID) == [0, 0, 0])
    #expect(startup.map { $0.bytes.count } == [64, 64, 64])
    #expect(startup[0].bytes[0] == 0x81)
    #expect(startup[1].bytes[0] == 0x8E)
    #expect(
      Array(startup[2].bytes.prefix(14)) == ProtocolPacketFixtures.Steam.startupSettingsPrefix
    )

    let shutdown = parser.deactivationWrites().hidFeatures
    #expect(shutdown.map(\.reportID) == [0, 0])
    #expect(shutdown.map { $0.bytes.count } == [64, 64])
    #expect(shutdown[0].bytes[0] == 0x85)
    #expect(shutdown[1].bytes[0] == 0x8E)
  }

  @Test
  func testSteamControllerBrightnessMatchesSDLSettingReport() {
    let report = SteamControllerDriver().encoded(.setLightBrightness(UnipolarValue(byte: 197)))
      .onlyReport

    #expect(report.reportID == 0)
    #expect(report.bytes.count == 64)
    #expect(Array(report.bytes.prefix(5)) == [0x87, 3, 45, 197, 0])
    #expect(report.bytes.dropFirst(5).allSatisfy { $0 == 0 })
  }

  @Test
  func testSteamControllerHapticReportsMatchLinuxFeatureCommand() {
    let reports = hapticReports(SteamControllerDriver(), left: 255, right: 128, durationMs: 450)

    #expect(reports.count == 2)
    #expect(reports.allSatisfy { $0.reportID == 0 && $0.bytes.count == 64 })
    #expect(Array(reports[0].bytes.prefix(10)) == [0x8F, 8, 1, 0xFF, 0xFF, 0, 0, 7, 0, 0x06])
    #expect(Array(reports[1].bytes.prefix(10)) == [0x8F, 8, 0, 0xFF, 0xFF, 0, 0, 7, 0, 0xF7])
    #expect(reports.flatMap { $0.bytes.dropFirst(10) }.allSatisfy { $0 == 0 })
  }

  @Test
  func testSteamControllerHapticIntensityAndSafeHoldFallback() {
    let low = hapticReports(SteamControllerDriver(), left: 1, right: 0, durationMs: 0)

    #expect(low.count == 1)
    #expect(Array(low[0].bytes.prefix(10)) == [0x8F, 8, 1, 0xE8, 0xFD, 0, 0, 1, 0, 0xE8])
    #expect(hapticReports(SteamControllerDriver(), left: 0, right: 0, durationMs: 10).isEmpty)
  }

  @Test
  func testSteamWirelessHapticsRequireLogicalControllerConnection() throws {
    let parser = SteamControllerDriver(isWirelessReceiver: true)
    #expect(hapticReports(parser, left: 255, right: 0, durationMs: 100).isEmpty)

    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02))
    #expect(hapticReports(parser, left: 255, right: 0, durationMs: 100).count == 1)

    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.wirelessReport(status: 0x01))
    #expect(hapticReports(parser, left: 255, right: 0, durationMs: 100).isEmpty)
  }

  @Test
  func testSteamWirelessReceiverStatusRequestReport() {
    let wired = SteamControllerDriver()
    #expect(wired.presenceRequestWrite() == nil)

    let wireless = SteamControllerDriver(isWirelessReceiver: true)
    let report = wireless.presenceRequestWrite().map { [$0] }?.hidFeatures.first

    #expect(report?.reportID == 0)
    #expect(report?.bytes.count == 64)
    #expect(report?.bytes.first == 0xB4)
  }

  @Test
  func testSteamControllerTracksWirelessConnectDisconnectLifecycle() throws {
    let parser = SteamControllerDriver(isWirelessReceiver: true)
    #expect(parser.sessionPlan.requiresInputConnectionBeforeOutput)

    let preConnectEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
    )
    #expect(preConnectEvents == nil)

    let connectEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02)
    )
    #expect(connectEvents == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)
    #expect(parser.consumeInputConnectionStateChange() == nil)

    let inputEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
    )
    #expect(inputEvents.contains(.press(.south)))

    let disconnectEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.wirelessReport(status: 0x01)
    )
    #expect(disconnectEvents == nil)
    #expect(parser.consumeInputConnectionStateChange() == .disconnected)

    let postDisconnectEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
    )
    #expect(postDisconnectEvents == nil)
  }

  @Test
  func testSteamWirelessStatusReportMarksReceiverConnectedWhenConnectEventWasMissed() throws {
    let parser = SteamControllerDriver(isWirelessReceiver: true)

    let statusEvents = try parser.parseReport(ProtocolPacketFixtures.Steam.statusReport)

    #expect(statusEvents == nil)
    #expect(parser.consumeInputConnectionStateChange() == .connected)

    let inputEvents = try parser.parseReport(
      ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
    )
    #expect(inputEvents.contains(.press(.south)))
  }

  @Test
  func testSteamControllerIgnoresUnknownNonStateReports() throws {
    let parser = SteamControllerDriver()
    var unknownEvent = Array(ProtocolPacketFixtures.Steam.inputReport())
    unknownEvent[2] = 0x04

    let events = try parser.parseReport(Data(unknownEvent))

    #expect(events == nil)
  }

  @Test
  func rawMotionUsesReceiptTimeAndSuppressesDuplicateSequenceNumbers() throws {
    let parser: any PhysicalProtocolDriver = SteamControllerDriver()
    var report = Array(ProtocolPacketFixtures.Steam.inputReport())
    report[4] = 255
    report[5] = 255
    report[6] = 255
    report[7] = 255
    ProtocolPacketFixtures.Steam.writeInt16LE(-32_768, into: &report, at: 28)
    ProtocolPacketFixtures.Steam.writeInt16LE(32_767, into: &report, at: 30)
    ProtocolPacketFixtures.Steam.writeInt16LE(-1, into: &report, at: 32)
    ProtocolPacketFixtures.Steam.writeInt16LE(123, into: &report, at: 34)
    let first = try parser.parseReport(Data(report), at: 100)
    guard let sample = first?.motion.first else {
      Issue.record("Expected motion sample")
      return
    }
    let count = 2.0 / 32_768
    #expect(isClose(sample.acceleration, metresPerSecondSquared(-2, 32_767 * count, -count)))
    #expect(isClose(sample.angularVelocity, radiansPerSecond(123 * 2_000 / 32_768, 0, 0)))
    #expect(sample.timestamp.basis == .hostEstimate)
    #expect(sample.timestamp.rawCounter == .max)
    #expect(sample.timestamp.monotonic.nanoseconds == 100)
    #expect(sample.timestamp.tickNanosecondsNumerator == nil)
    #expect(try parser.parseReport(Data(report), at: 110)?.motion.isEmpty == true)
    report.replaceSubrange(4..<8, with: [0, 0, 0, 0])
    let second = try parser.parseReport(Data(report), at: 120)
    guard let wrapped = second?.motion.first else {
      Issue.record("Expected sample after packet counter wrap")
      return
    }
    #expect(wrapped.timestamp.monotonic.nanoseconds == 120)
    #expect(wrapped.timestamp.sequenceIndex == 1)
    report[4] = 1
    let backward = try parser.parseReport(Data(report), at: 90)
    guard let clamped = backward?.motion.first else {
      Issue.record("Expected sample with clamped receipt time")
      return
    }
    #expect(clamped.timestamp.monotonic.nanoseconds == 120)
  }

  @Test
  func receiverReconnectResetsMotionClockAndDuplicateTracking() throws {
    let parser = SteamControllerDriver(isWirelessReceiver: true)
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.wirelessReport(status: 2))
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport(), at: 100)
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.wirelessReport(status: 1))
    #expect(try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport()) == nil)
    _ = try parser.parseReport(ProtocolPacketFixtures.Steam.wirelessReport(status: 2))
    let events = try parser.parseReport(ProtocolPacketFixtures.Steam.inputReport(), at: 10)
    guard let sample = events?.motion.first else {
      Issue.record("Expected fresh receiver-session motion sample")
      return
    }
    // A new receiver session re-anchors time; the sequence index keeps counting.
    #expect(sample.timestamp.sequenceIndex == 1)
    #expect(sample.timestamp.monotonic.nanoseconds == 10)
  }

  /// The feature reports of one trackpad haptic request.
  func hapticReports(
    _ parser: SteamControllerDriver,
    left: UInt8,
    right: UInt8,
    durationMs: Int
  ) -> [PhysicalHIDOutputReport] {
    let intensities: [PhysicalRumbleMotor: UInt8] = [.leftHaptic: left, .rightHaptic: right]
    return parser.encoded(
      .setRumble(RumbleIntensities(bytes: intensities), duration: .milliseconds(durationMs))
    )?.writes.hidFeatures ?? []
  }
}
