import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiDriverOutputTests {
  private static let on = ControllerOutputCommand.setRumble(
    RumbleIntensities(lowFrequency: .max),
    duration: .held
  )

  private func reports(_ plan: PhysicalOutputPlan) -> [[UInt8]] {
    plan.writes.compactMap { if case .hidOutput(let report) = $0 { report.bytes } else { nil } }
  }

  @Test(arguments: [false, true])
  func everyOutputReportCarriesTheRumbleBit(rumbling: Bool) throws {
    let session = WiiSession()
    session.driver.enableIR(.irExtended, at: MonotonicTimestamp(nanoseconds: 0))
    if rumbling { _ = try session.driver.encode(Self.on) }
    session.note(session.driver.startupWrites())
    try session.startUp()
    try session.answer(from: session.log.count - 1, count: 7)
    let sent =
      session.log.map(\.report) + [
        try reports(session.driver.encode(.setPlayerIndicator(.player3))).flatMap { $0 }
      ]
    let ids = Set(sent.map { $0[0] })
    // Status request, mode, calibration read, IR report steps, memory writes, LEDs.
    #expect(ids == [0x15, 0x12, 0x17, 0x13, 0x1A, 0x16, 0x11])
    for report in sent {
      #expect(report[1] & 1 == (rumbling ? 1 : 0), "report \(String(report[0], radix: 16))")
    }
    let stop = try session.driver.encode(.stopRumble)
    #expect(reports(stop) == [[0x10, 0]])
  }

  @Test
  func theIRSequenceMatchesTheFixtureWithTheRumbleBitOn() throws {
    let session = WiiSession()
    session.driver.enableIR(.irExtended, at: MonotonicTimestamp(nanoseconds: 0))
    _ = try session.driver.encode(Self.on)
    try session.startUp()
    try session.answer(from: 2, count: 7)
    let expected = try WiiFixtureFolder.sequences.byteStrings("ir-rumble-on").map(Array.init)
    #expect(session.log.dropFirst(2).map(\.report) == expected)
  }

  @Test
  func theMotorIsBinaryAndRunsForAnyIntensityAboveZero() throws {
    let driver = WiiDriver()
    let faint = ControllerOutputCommand.setRumble(
      RumbleIntensities(lowFrequency: UnipolarValue(1)),
      duration: .held
    )
    #expect(reports(try driver.encode(faint)) == [[0x10, 1]])
    #expect(reports(try driver.encode(.setRumble(.off, duration: .held))) == [[0x10, 0]])
    #expect(reports(try driver.encode(Self.on)) == [[0x10, 1]])
    #expect(reports(try driver.encode(.stopRumble)) == [[0x10, 0]])
  }

  @Test
  func eachPlayerLightsItsOwnLEDAndOffLightsNone() throws {
    let driver = WiiDriver()
    let expected: [PhysicalPlayerIndicator: UInt8] = [
      .off: 0, .player1: 0x10, .player2: 0x20, .player3: 0x40, .player4: 0x80,
    ]
    for (player, bits) in expected {
      #expect(reports(try driver.encode(.setPlayerIndicator(player))) == [[0x11, bits]])
    }
    _ = try driver.encode(Self.on)
    #expect(reports(try driver.encode(.setPlayerIndicator(.player2))) == [[0x11, 0x21]])
  }
}
