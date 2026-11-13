import Foundation
import Testing

@testable import OpenJoystickDriverKit

private final class PointerDemandingDispatcher: OutputDispatcher, PointerInputDemand,
  @unchecked Sendable
{
  var suppressOutput = false
  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {}
  func activateOutput(for _: LogicalControllerID) {}
  func wantsPointerInput(from _: LogicalControllerID) -> Bool { true }
}

struct WiiDriverIRTests {
  private static let spacing: UInt64 = 50_000_000

  /// A session that has finished the IR setup of `format`, with the writes it made kept.
  private func readySession(
    _ format: ProtocolDescription.WiiRemote.BlockKind = .irExtended
  ) throws -> WiiSession {
    let session = WiiSession(irFormat: format)
    try session.startUp()
    try session.answer(from: 2, count: 7)
    #expect(session.driver.isIRReady)
    return session
  }

  /// A 0x33 report: neutral buttons, `acceleration` high bytes, then the 12 IR bytes.
  private func report33(_ ir: [UInt8], acceleration: [UInt8] = [0x80, 0x80, 0xC4]) -> [UInt8] {
    [0x33, 0, 0] + acceleration + ir
  }

  /// The three bytes of an extended-format point.
  private func extended(_ x: Int, _ y: Int, size: Int = 5) -> [UInt8] {
    [UInt8(x & 0xFF), UInt8(y & 0xFF), UInt8((y >> 8) << 6 | (x >> 8) << 4 | size)]
  }

  private static let empty = [UInt8](repeating: 0xFF, count: 3)

  private func fixture(_ name: String) throws -> [UInt8] {
    Array(try WiiFixtureFolder.ir.bytes(name))
  }

  @Test
  func setupWritesAllSevenStepsAtLeastFiftyMillisecondsApartAndMatchesFixture() throws {
    let session = WiiSession(irFormat: .irExtended)
    try session.startUp()
    // Every step is acknowledged the moment it is written, so only the spacing delays the next.
    try session.answer(from: 2, count: 7)
    let writes = session.log.dropFirst(2)
    #expect(
      writes.map(\.report)
        == (try WiiFixtureFolder.sequences.byteStrings("ir-rumble-off")).map(Array.init)
    )
    for (earlier, later) in zip(writes, writes.dropFirst()) {
      #expect(later.at - earlier.at >= Self.spacing)
    }
    #expect(session.driver.failure == nil)
  }

  @Test
  func spacingOfTwentyMillisecondsIsRefused() throws {
    func decode(_ milliseconds: Int) throws {
      let json = Data("{\"irWriteIntervalMs\": \(milliseconds)}".utf8)
      _ = try JSONDecoder().decode(ControllerRecordDocument.Tuning.self, from: json)
    }
    try decode(50)
    #expect(throws: DecodingError.self) { try decode(20) }
  }

  @Test
  func noPointAppearsBeforeSetupEnds() throws {
    let session = WiiSession(irFormat: .irExtended)
    try session.startUp()
    let event = try session.feed(
      report33(extended(400, 300) + extended(623, 467) + Self.empty + Self.empty)
    )
    #expect(event?.touchFrames.isEmpty == true)
  }

  @Test(arguments: [0, 1, 2, 4])
  func extendedFixtureYieldsItsVisiblePoints(count: Int) throws {
    let session = try readySession()
    let event = try session.feed(report33(try fixture("extended-\(count)-points")))
    let frame = try #require(event?.touchFrames.first)
    #expect(frame.contacts.filter(\.isActive).count == count)
    #expect(session.driver.irPoints.compactMap { $0 }.count == count)
    #expect(session.driver.pointer.isTracking == (count >= 2))
  }

  @Test
  func extendedTwoPointFixtureDecodesPositionAndSize() throws {
    let session = try readySession()
    try session.feed(report33(try fixture("extended-2-points")))
    #expect(session.driver.irPoints[0] == .init(x: 400, y: 380, size: 5))
    #expect(session.driver.irPoints[1] == .init(x: 620, y: 384, size: 6))
    #expect(session.driver.irPoints[2] == nil)
  }

  @Test
  func basicFixtureYieldsFourPoints() throws {
    let session = try readySession(.irBasic)
    // Mode 0x37: buttons, acceleration, ten IR bytes, six extension bytes.
    try session.feed(
      [0x37, 0, 0, 0x80, 0x80, 0xC4] + (try fixture("basic-4-points"))
        + [UInt8](repeating: 0, count: 6)
    )
    #expect(session.driver.irPoints.compactMap { $0 }.count == 4)
    #expect(session.driver.irPoints.map { $0?.size } == [0, 0, 0, 0])
  }

  @Test
  func fullPairsFillSlotsOneToTwoAndThreeToFour() throws {
    let session = try readySession(.irFull)
    try session.feed([0x3E, 0, 0, 0x80] + (try fixture("full-pair-a")))
    #expect(session.driver.irPoints.map { $0 != nil } == [true, true, false, false])
    try session.feed([0x3F, 0, 0, 0x80] + (try fixture("full-pair-b")))
    #expect(session.driver.irPoints.map { $0 != nil } == [true, true, true, true])
  }

  @Test
  func centeredPointerIsZero() throws {
    let session = try readySession()
    // The midpoint of the two points is (511.5, 383.5), the center of the 1024 by 768 grid.
    try session.feed(report33(extended(400, 300) + extended(623, 467) + Self.empty + Self.empty))
    #expect(session.driver.pointer.isTracking)
    #expect(abs(session.driver.pointer.x) < 1e-6)
    #expect(abs(session.driver.pointer.y) < 1e-6)
  }

  @Test
  func rollOfRecordedAccelerometerSampleTurnsPointer() throws {
    // The midpoint lies 100.5 grid units right of center.
    let ir = extended(600, 383) + extended(624, 384) + Self.empty + Self.empty
    let level = try readySession()
    try level.feed(report33(ir, acceleration: [0x80, 0x80, 0xC4]))
    #expect(abs(level.driver.pointer.x - -100.5 / 511.5) < 0.01)
    #expect(abs(level.driver.pointer.y) < 0.01)
    // Gravity on the X axis: a quarter turn.
    let rolled = try readySession()
    try rolled.feed(report33(ir, acceleration: [0xC1, 0x80, 0x84]))
    #expect(abs(rolled.driver.pointer.x) < 0.01)
    #expect(abs(rolled.driver.pointer.y - -100.5 / 383.5) < 0.01)
  }

  @Test
  func losingPointHoldsPointerAndClearsTracking() throws {
    let session = try readySession()
    try session.feed(report33(extended(600, 383) + extended(624, 384) + Self.empty + Self.empty))
    let held = session.driver.pointer
    #expect(held.isTracking)
    let event = try session.feed(report33(try fixture("extended-1-points")))
    #expect(session.driver.pointer == .init(x: held.x, y: held.y, isTracking: false))
    #expect(event?.state.pressed.contains(.pointerTracking) == false)
  }

  @Test
  func defaultDriverRunsSevenStepScriptAtStartupInBasicFormat() throws {
    let session = WiiSession()
    try session.startUp()
    try session.answer(from: 2, count: 7)
    var expected = try WiiFixtureFolder.sequences.byteStrings("ir-rumble-off").map(Array.init)
    // The mode step of the extended script writes its mode byte at index 6 of the sixth report.
    expected[5][6] = 1
    #expect(session.log.dropFirst(2).map(\.report) == expected)
    #expect(session.driver.isIRReady)
    #expect(session.log.contains { $0.report[0] == 0x12 && $0.report[2] == 0x37 })
  }

  @Test
  func decodedFrameSetsPointerAxesAndTracking() throws {
    let session = try readySession()
    let event = try session.feed(
      report33(extended(600, 383) + extended(624, 384) + Self.empty + Self.empty)
    )
    let state = try #require(event?.state)
    #expect(abs(state.pointer.x.normalized - session.driver.pointer.x) < 1e-3)
    #expect(abs(state.pointer.y.normalized - session.driver.pointer.y) < 1e-3)
    #expect(state.pointer.x != .center)
    #expect(state.pressed.contains(.pointerTracking))
  }

  @Test
  func fewerThanTwoPointsHoldAxesAndClearTracking() throws {
    let session = try readySession()
    let held = try #require(
      try session.feed(report33(extended(600, 383) + extended(624, 384) + Self.empty + Self.empty))
    ).state.pointer
    let event = try session.feed(report33(try fixture("extended-1-points")))
    #expect(event?.state.pointer == held)
    #expect(event?.state.pressed.contains(.pointerTracking) == false)
  }

  @Test
  func hidPathHandsDeferredWritesToTransport() async throws {
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x057E, productID: 0x0306),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: WiiDriver(),
      dispatcher: CapturingOutputDispatcher()
    )
    await pipeline.start()
    let writes = await pipeline.feedHIDData(Data(try WiiFixtures.report("20-status-no-extension")))
    let ids = writes.compactMap { write -> UInt8? in
      if case .hidOutput(let report) = write { report.bytes[0] } else { nil }
    }
    // The report mode, then the first calibration read.
    #expect(ids.contains(0x12))
    #expect(ids.contains(0x17))
    await pipeline.stop()
  }

  @Test
  func disconnectEndsSessionAndSetupRunsAgainBeforeAnyPoint() throws {
    let session = try readySession()
    let ir = report33(extended(600, 383) + extended(624, 384) + Self.empty + Self.empty)
    try session.feed(ir)
    #expect(session.driver.pointer.isTracking)

    session.driver.resetProtocolState()
    #expect(!session.driver.isIRReady)
    #expect(session.driver.state == .neutral)
    #expect(session.driver.irPoints.allSatisfy { $0 == nil })

    let before = session.log.count
    try session.startUp()
    #expect(session.log.count == before + 3)
    // The setup restarts with its first report, and no point shows until all seven steps ran.
    #expect(session.log.last?.report == [0x13, 0x04])
    let early = try session.feed(ir)
    #expect(early?.touchFrames.isEmpty == true)
    try session.answer(from: before + 2, count: 7)
    let event = try session.feed(ir)
    #expect(event?.touchFrames.first?.contacts.filter(\.isActive).count == 2)
  }

  /// The first session writes of a session with IR available but no profile that binds the pointer.
  private func unboundSession() throws -> WiiSession {
    let session = WiiSession(irFormat: .irBasic)
    session.driver.setPointerInputWanted(false)
    try session.startUp()
    return session
  }

  @Test
  func withNoPointerBindingSessionUsesNonIRModeAndWritesNoIRStep() throws {
    let session = try unboundSession()
    let reports = session.log.map(\.report)
    #expect(reports.contains([0x12, 0x04, 0x31]))
    #expect(!reports.contains { $0.first == 0x13 || $0.first == 0x1A })
    #expect(!session.driver.isIRReady)
  }

  @Test
  func bindingPointerLaterRunsSetupAndSwitchesReportMode() throws {
    let session = try unboundSession()
    session.driver.setPointerInputWanted(true)
    let before = session.log.count
    session.advance()
    try session.feed([0x30, 0, 0])
    let written = session.log.dropFirst(before).map(\.report)
    #expect(written.first == [0x13, 0x04])
    #expect(written.contains([0x12, 0x04, 0x37]))
    try session.answer(from: before, count: 8)
    #expect(session.driver.isIRReady)
  }

  @Test
  func unbindingPointerDisablesCameraClearsPointerAndRestoresNonIRMode() throws {
    let session = try readySession(.irBasic)
    let before = session.log.count
    session.driver.setPointerInputWanted(false)
    session.advance()
    let event = try session.feed([0x30, 0, 0])
    #expect(event?.state.pointer == StickPosition(x: 0, y: 0))
    let written = session.log.dropFirst(before).map(\.report)
    #expect(written.first == [0x13, 0x00])
    #expect(written.contains([0x12, 0x04, 0x31]))
    try session.answer(from: before, count: 3)
    #expect(session.log.dropFirst(before).map(\.report).contains([0x1A, 0x00]))
    #expect(!session.driver.isIRReady)
    #expect(!session.driver.pointer.isTracking)
  }

  @Test
  func cameraTurnsOnAgainAfterReconnectWhileProfileStillBindsPointer() throws {
    let session = try readySession(.irBasic)
    session.driver.resetProtocolState()
    let before = session.log.count
    try session.startUp()
    #expect(session.log.dropFirst(before).map(\.report).contains([0x13, 0x04]))
  }

  /// The report mode the pipeline hands to the transport for the first status report.
  private func firstReportMode(dispatcher: any OutputDispatcher) async throws -> UInt8? {
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x057E, productID: 0x0306),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: WiiDriver(),
      dispatcher: dispatcher
    )
    await pipeline.start()
    let writes = await pipeline.feedHIDData(Data(try WiiFixtures.report("20-status-no-extension")))
    await pipeline.stop()
    return writes.compactMap { write -> UInt8? in
      if case .hidOutput(let report) = write, report.bytes[0] == 0x12 {
        report.bytes[2]
      } else {
        nil
      }
    }.first
  }

  @Test
  func pipelineAsksForIROnlyThroughDispatcherThatWantsPointer() async throws {
    #expect(try await firstReportMode(dispatcher: PointerDemandingDispatcher()) == 0x37)
    #expect(try await firstReportMode(dispatcher: CapturingOutputDispatcher()) == 0x31)
  }
}
