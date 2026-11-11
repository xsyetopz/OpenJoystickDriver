import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiDriverExchangeTests {
  private static let wii = PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote
  private static let timeout: UInt64 = 500_000_000

  private let driver = WiiDriver(tuning: nil, irFormat: nil)

  /// Parses `report` at `nanoseconds` and returns the writes it queued.
  @discardableResult
  private func feed(_ report: Data, at nanoseconds: UInt64 = 0) throws -> [PhysicalOutputWrite] {
    _ = try driver.parseReport(report, at: nanoseconds)
    return driver.drainPendingWrites()
  }

  private func feed(_ fixture: String, at nanoseconds: UInt64 = 0) throws -> [PhysicalOutputWrite] {
    try feed(WiiFixtures.report(fixture), at: nanoseconds)
  }

  private func reportIDs(_ writes: [PhysicalOutputWrite]) -> [UInt8] {
    writes.compactMap { if case .hidOutput(let report) = $0 { report.reportID } else { nil } }
  }

  private func output(_ report: Data) -> PhysicalOutputWrite {
    .hidOutput(PhysicalHIDOutputReport(reportID: report[0], bytes: Array(report)))
  }

  /// A memory reply of `data` at the 16-bit `address`, with `error` in the low nibble.
  private func reply(address: UInt16, data: [UInt8], error: UInt8 = 0) -> Data {
    let padded = data + [UInt8](repeating: 0, count: 16 - data.count)
    return Data(
      [0x21, 0, 0, UInt8(data.count - 1) << 4 | error, UInt8(address >> 8), UInt8(address & 0xFF)]
        + padded
    )
  }

  private func acknowledgement(error: UInt8) -> Data { Data([0x22, 0, 0, 0x16, error]) }

  /// The calibration block of a remote: zero near 0x200, gravity 0x40 above it.
  private static let calibrationBlock: [UInt8] = [
    0x80, 0x82, 0x84, 0b00_01_10_11, 0xC0, 0xC2, 0xC4, 0b00_11_10_01, 0, 0,
  ]

  @Test
  func everyChoiceOfTheDescriptionSendsItsModeWithTheContinuousBitRule() throws {
    let wii = try #require(Self.wii)
    for choice in wii.modeChoices {
      driver.requestedFeatures = choice.features
      let mode = try #require(wii.reportModes.first { $0.id == choice.mode })
      let continuous: UInt8 = mode.blocks.contains { $0.kind != .buttons } ? 0x04 : 0
      let writes = try feed("20-status-no-extension")
      #expect(
        writes.contains(output(Data([0x12, continuous, choice.mode]))),
        "mode \(String(choice.mode, radix: 16))"
      )
      driver.resetProtocolState()
    }
  }

  @Test
  func aStatusReportYieldsExactlyOneModeWrite() throws {
    let writes = try feed("20-status-no-extension")
    #expect(reportIDs(writes).filter { $0 == 0x12 }.count == 1)
    #expect(writes.first == output(Data([0x12, 0x04, 0x31])))
    #expect(reportIDs(try feed("20-status-battery-low")).filter { $0 == 0x12 }.count == 1)
  }

  @Test
  func theCalibrationReadRequestsTheEEPROMBlockOnce() throws {
    let writes = try feed("20-status-no-extension")
    #expect(writes.last == output(Data([0x17, 0x00, 0x00, 0x00, 0x16, 0x00, 0x0A])))
    #expect(reportIDs(try feed("20-status-no-extension")) == [0x12])
  }

  @Test
  func aSuccessfulReadSetsTheCalibration() throws {
    _ = try feed("20-status-no-extension")
    #expect(try feed(reply(address: 0x0016, data: Self.calibrationBlock)).isEmpty)
    #expect(
      driver.accelerometerCalibration
        == WiiDriver.AccelerometerCalibration(Self.calibrationBlock)
    )
    #expect(driver.accelerometerCalibration?.zero == .init(x: 0x201, y: 0x20A, z: 0x213))
    #expect(driver.accelerometerCalibration?.gravity == .init(x: 0x303, y: 0x30A, z: 0x311))
    #expect(driver.failure == nil)
  }

  @Test
  func anAllZeroBlockLeavesTheCalibrationUnset() throws {
    _ = try feed("20-status-no-extension")
    _ = try feed("21-read-success")
    #expect(driver.accelerometerCalibration == nil)
    #expect(driver.failure == nil)
  }

  @Test
  func anErrorNibbleEndsTheReadWithTheError() throws {
    _ = try feed("20-status-no-extension")
    _ = try feed("21-read-error")
    #expect(driver.failure == .init(purpose: .accelerometerCalibration, step: 0, reason: .error(7)))
    #expect(driver.accelerometerCalibration == nil)
  }

  @Test
  func aReplyForAnotherAddressIsRefusedAndNamed() throws {
    _ = try feed("20-status-no-extension")
    _ = try feed(reply(address: 0x0020, data: Self.calibrationBlock))
    #expect(driver.refusedReply == .addressMismatch(expected: 0x0016, received: 0x0020))
    #expect(driver.accelerometerCalibration == nil)
    #expect(driver.failure == nil)
    _ = try feed(reply(address: 0x0016, data: Self.calibrationBlock))
    #expect(driver.accelerometerCalibration != nil)
  }

  @Test
  func aLongReadIsReassembledFromRepliesAtRisingAddresses() throws {
    let wii = try #require(Self.wii)
    #expect(wii.scripts.accelerometerCalibration == [.read(address: 0x16, length: 10)])
    _ = try feed("20-status-no-extension")
    // Two replies of five bytes each reassemble the ten-byte block.
    let block = Self.calibrationBlock
    _ = try feed(reply(address: 0x0016, data: Array(block[0..<5])))
    #expect(driver.accelerometerCalibration == nil)
    _ = try feed(reply(address: 0x001B, data: Array(block[5..<10])))
    #expect(driver.accelerometerCalibration == WiiDriver.AccelerometerCalibration(block))
  }

  /// Runs the calibration read to its end and returns the handshake's first write.
  private func startHandshake() throws -> [PhysicalOutputWrite] {
    _ = try feed("20-status-extension")
    return try feed(reply(address: 0x0016, data: Self.calibrationBlock))
  }

  @Test
  func theHandshakeSendsTheScriptStepByStep() throws {
    let expected = try WiiFixtureFolder.sequences.byteStrings("handshake-rumble-off").map(output)
    #expect(try startHandshake() == [expected[0]])
    #expect(try feed(acknowledgement(error: 0)) == [expected[1]])
    #expect(try feed(acknowledgement(error: 0)) == [expected[2]])
  }

  @Test(arguments: ["Nunchuk", "ClassicController", "ClassicControllerPro", "MotionPlus"])
  func eachKnownIdGivesItsKindAndOneModeWrite(kind: String) throws {
    _ = try startHandshake()
    _ = try feed(acknowledgement(error: 0))
    _ = try feed(acknowledgement(error: 0))
    let id = try WiiFixtureFolder.extensions.bytes("id-\(kind)")
    let writes = try feed(reply(address: 0x00FA, data: Array(id)))
    #expect(driver.extensionKind == .known(kind))
    #expect(writes == [output(Data([0x12, 0x04, 0x35]))])
    #expect(driver.failure == nil)
  }

  @Test
  func anUnknownIdKeepsItsBytesAndKeepsTheCoreMode() throws {
    _ = try startHandshake()
    _ = try feed(acknowledgement(error: 0))
    _ = try feed(acknowledgement(error: 0))
    let writes = try feed(reply(address: 0x00FA, data: [1, 2, 3, 4, 5, 6]))
    #expect(driver.extensionKind == .unknown([1, 2, 3, 4, 5, 6]))
    #expect(writes.isEmpty)
  }

  @Test
  func anAcknowledgementErrorEndsTheHandshakeWithoutAFurtherWrite() throws {
    _ = try startHandshake()
    #expect(try feed(acknowledgement(error: 3)).isEmpty)
    #expect(driver.failure == .init(purpose: .extensionHandshake, step: 0, reason: .error(3)))
    #expect(driver.extensionKind == nil)
  }

  @Test
  func aMissingReplyEndsTheHandshakeAtTheTimeoutWithoutAFurtherWrite() throws {
    _ = try feed("20-status-extension", at: 0)
    _ = try feed(reply(address: 0x0016, data: Self.calibrationBlock), at: 1_000)
    let before = Self.timeout + 1_000
    #expect(try feed(Data([0x30, 0, 0]), at: before - 1).isEmpty)
    #expect(driver.failure == nil)
    #expect(try feed(Data([0x30, 0, 0]), at: before).isEmpty)
    #expect(driver.failure == .init(purpose: .extensionHandshake, step: 0, reason: .timeout))
    #expect(try feed(acknowledgement(error: 0), at: before + 1).isEmpty)
  }

  @Test
  func removalReturnsTheExtensionControlsToNeutralAndRestoresTheMode() throws {
    _ = try startHandshake()
    _ = try feed(acknowledgement(error: 0))
    _ = try feed(acknowledgement(error: 0))
    _ = try feed(reply(address: 0x00FA, data: [0, 0, 0xA4, 0x20, 0, 0]))
    func nunchuk(stickX: UInt8) -> Data {
      Data([0x35, 0, 0, 0x80, 0x80, 0x80, stickX, 0x80, 0x80, 0x80, 0x80, 0x03])
        + Data(repeating: 0, count: 10)
    }
    _ = try feed(nunchuk(stickX: 0x80))
    #expect(try feed(nunchuk(stickX: 0xFF)).isEmpty)
    #expect(driver.state.leftStick.x.rawValue > 32_000)
    let event = try driver.parseReport(WiiFixtures.report("20-status-no-extension"), at: 5)
    #expect(event?.state.leftStick == .center)
    #expect(driver.extensionKind == nil)
    #expect(driver.drainPendingWrites() == [output(Data([0x12, 0x04, 0x31]))])
  }

  @Test
  func removalDuringTheHandshakeDropsItAndNoReplyIsAwaited() throws {
    _ = try startHandshake()
    #expect(try feed("20-status-no-extension").count == 1)
    #expect(try feed(acknowledgement(error: 0)).isEmpty)
    #expect(driver.failure == nil)
  }

  @Test
  func pluggingInAgainStartsANewHandshake() throws {
    _ = try startHandshake()
    _ = try feed("20-status-no-extension")
    let writes = try feed("20-status-extension")
    #expect(reportIDs(writes) == [0x12, 0x16])
  }
}
