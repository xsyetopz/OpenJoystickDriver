import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Third-party DualSense-protocol controllers follow SDL's `HIDAPI_DriverPS5` non-Sony path.
struct DualSenseDriverThirdPartyTests {
  private static let probe = PhysicalHIDFeatureReadRequest(reportID: 0x03, length: 48)

  /// SDL's capability reply: `0x28` at byte 2, features in bytes 4 and 20.
  private static func capabilityReply(features: UInt8, extra: UInt8 = 0) -> Data {
    var reply = [UInt8](repeating: 0, count: 48)
    reply[0] = 0x03
    reply[2] = 0x28
    reply[4] = features
    reply[20] = extra
    return Data(reply)
  }

  /// A USB report `0x01` in SDL's alternate layout, payload offsets as in `PS5StatePacketAlt_t`.
  private static func alternateReport(
    sequence: UInt32 = 1,
    buttons1: UInt8 = 0,
    triggers: (UInt8, UInt8) = (0, 0),
    timestamp: UInt16 = 0,
    touchCounter: UInt8 = 0x80
  ) -> Data {
    var payload = [UInt8](repeating: 0, count: 63)
    payload[0...3] = [0x80, 0x80, 0x80, 0x80]
    payload[4] = triggers.0
    payload[5] = triggers.1
    payload[7] = 0x08
    payload[8] = buttons1
    for index in 0..<4 { payload[11 + index] = UInt8(truncatingIfNeeded: sequence >> (index * 8)) }
    payload[27] = UInt8(truncatingIfNeeded: timestamp)
    payload[28] = UInt8(truncatingIfNeeded: timestamp >> 8)
    payload[31] = touchCounter
    payload[32...34] = [0x10, 0x20, 0x30]
    payload[35] = 0x80
    return Data([0x01] + payload)
  }

  private static func at(_ nanoseconds: UInt64) -> MonotonicTimestamp {
    MonotonicTimestamp(nanoseconds: nanoseconds)
  }

  @Test
  func sonyControllerReadsOnlyCalibrationAndKeepsFullOutput() {
    let driver = DualSenseDriver()
    #expect(driver.startupFeatureReads().map(\.reportID) == [0x05])
    #expect(driver.outputCapabilities.supportsAdaptiveTriggers)
    #expect(!driver.sessionPlan.requiresInputConnectionBeforeOutput)
  }

  @Test
  func thirdPartyProbeSetsFeaturesAndOutput() throws {
    let driver = DualSenseDriver(vendorID: 0x0F0D)
    #expect(driver.startupFeatureReads().map(\.reportID) == [0x03, 0x05])
    #expect(!driver.outputCapabilities.supportsRumble)
    #expect(throws: ControllerOutputError.self) { try driver.encode(.stopRumble) }

    // Vibration and the player indicator, no lightbar.
    #expect(
      driver.consumeFeatureReply(
        Self.capabilityReply(features: 0x08, extra: 0x80),
        request: Self.probe
      )
    )
    let output = driver.outputCapabilities
    #expect(output.supportsRumble)
    #expect(output.supportsPlayerIndicator)
    #expect(!output.lightingFeatures.contains(.programmableColor))
    #expect(!output.supportsAdaptiveTriggers)
    _ = try driver.encode(.stopRumble)
    #expect(throws: ControllerOutputError.self) {
      try driver.encode(.setRGB(ControllerColor(red: 1, green: 2, blue: 3)))
    }
  }

  @Test
  func probeReplyWithoutMarkerIsRejected() {
    let driver = DualSenseDriver(vendorID: 0x0F0D)
    var reply = [UInt8](Self.capabilityReply(features: 0x4E))
    reply[2] = 0x27
    #expect(!driver.consumeFeatureReply(Data(reply), request: Self.probe))
    #expect(!driver.consumeFeatureReply(Data(reply.prefix(47)), request: Self.probe))
    #expect(driver.outputCapabilities == .none)
  }

  @Test
  func naconRevolution5ProHasVibrationItsProbeOmits() {
    let driver = DualSenseDriver(vendorID: 0x3285, quirks: [.forcedVibration])
    #expect(driver.consumeFeatureReply(Self.capabilityReply(features: 0x42), request: Self.probe))
    #expect(driver.outputCapabilities.supportsRumble)
  }

  @Test
  func unprobedThirdPartyControllerReportsNoTouchOrMotion() throws {
    let driver = DualSenseDriver(vendorID: 0x0F0D)
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0x01
    report[8] = 0x08
    report[33] = 0x00  // A standard-layout active contact.
    let event = try #require(try driver.parse(report: Data(report), receivedAt: Self.at(1)))
    #expect(event.touchFrames.isEmpty)
    #expect(event.motion.isEmpty)
  }

  @Test
  func razerWolverineUsesAlternateLayoutWithoutAProbe() throws {
    let driver = DualSenseDriver(
      vendorID: 0x1532,
      quirks: [.unprobedSensors, .unprobedTouchpad]
    )
    let first = try #require(
      try driver.parse(
        report: Self.alternateReport(timestamp: 0xFFF0, touchCounter: 0x05),
        receivedAt: Self.at(1_000)
      )
    )
    let contact = try #require(first.touchFrames.first?.contacts.first)
    #expect(contact.isActive)
    #expect(first.touchFrames.first?.contacts.last?.isActive == false)
    #expect(!first.motion.isEmpty)
    // The 16-bit microsecond timestamp wraps: 0xFFF0 to 0x0010 is 32 µs.
    let second = try #require(
      try driver.parse(report: Self.alternateReport(timestamp: 0x0010), receivedAt: Self.at(9_000))
    )
    let motion = try #require(second.motion.first)
    #expect(motion.timestamp.monotonic.nanoseconds == 1_000 + 32_000)
    #expect(driver.outputCapabilities == .none)
  }

  @Test
  func digitalTriggerWithIdleAnalogByteReadsFullyPulled() throws {
    let driver = DualSenseDriver(vendorID: 0x1532, quirks: [.unprobedTouchpad])
    let event = try #require(
      try driver.parse(
        report: Self.alternateReport(buttons1: 0x0C, triggers: (0, 64)),
        receivedAt: Self.at(1)
      )
    )
    #expect(event.state.leftTrigger == UnipolarValue(normalized: 1))
    #expect(event.state.rightTrigger == UnipolarValue(normalized: 64 / 255))
  }

  @Test
  func dongleConnectsOnNewSequencesAndDisconnectsWhenTheyStop() throws {
    let driver = DualSenseDriver(vendorID: 0x1532, quirks: [.unprobedTouchpad, .receiver])
    #expect(driver.sessionPlan.requiresInputConnectionBeforeOutput)
    // The first report only anchors the sequence.
    #expect(
      try driver.parse(report: Self.alternateReport(sequence: 7), receivedAt: Self.at(0)) == nil
    )
    #expect(driver.consumeInputConnectionStateChange() == nil)
    #expect(
      try driver.parse(report: Self.alternateReport(sequence: 8), receivedAt: Self.at(1)) != nil
    )
    #expect(driver.consumeInputConnectionStateChange() == .connected)
    // A repeated sequence carries no input, and disconnects only after 500 ms.
    #expect(
      try driver.parse(report: Self.alternateReport(sequence: 8), receivedAt: Self.at(400_000_000))
        == nil
    )
    #expect(driver.consumeInputConnectionStateChange() == nil)
    _ = try driver.parse(
      report: Self.alternateReport(sequence: 8),
      receivedAt: Self.at(500_000_001)
    )
    #expect(driver.consumeInputConnectionStateChange() == .disconnected)
    #expect(
      try driver.parse(report: Self.alternateReport(sequence: 9), receivedAt: Self.at(600_000_000))
        != nil
    )
    #expect(driver.consumeInputConnectionStateChange() == .connected)
  }

  @Test
  func wiredThirdPartyControllerNeedsNoConnection() throws {
    let driver = DualSenseDriver(vendorID: 0x1532, quirks: [.unprobedTouchpad])
    #expect(!driver.sessionPlan.requiresInputConnectionBeforeOutput)
    #expect(
      try driver.parse(report: Self.alternateReport(sequence: 1), receivedAt: Self.at(0)) != nil
    )
    #expect(
      try driver.parse(report: Self.alternateReport(sequence: 1), receivedAt: Self.at(1)) != nil
    )
  }
}
