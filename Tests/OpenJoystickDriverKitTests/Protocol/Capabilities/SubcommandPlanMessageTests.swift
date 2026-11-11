import Testing

@testable import OpenJoystickDriverKit

@Suite
struct SubcommandPlanMessageTests {
  private static func message(_ build: () throws -> Void) -> String? {
    do {
      try build()
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "057e-2009.plist"
      )
    }
  }

  @Test
  func aCounterModulusOutsideItsRangeNamesTheRange() throws {
    let indicator = try PlayerIndicatorSubcommand(
      subcommand: 0x30,
      patterns: Dictionary(uniqueKeysWithValues: PhysicalPlayerIndicator.allCases.map { ($0, 0) })
    )
    #expect(
      Self.message {
        _ = try SubcommandPlan(
          reportID: 1,
          counterModulus: 1,
          requests: [],
          playerIndicator: indicator
        )
      }
        == "057e-2009.plist, session.subcommands.counterModulus: A subcommand counterModulus "
        + "must be 2...256. Fix: Set counterModulus to 2...256."
    )
  }

  @Test
  func aPlayerIndicatorWithoutPatternsNamesTheIndicators() {
    #expect(
      Self.message { _ = try PlayerIndicatorSubcommand(subcommand: 0x30, patterns: [:]) }
        == "057e-2009.plist, session.subcommands.playerIndicator.patterns: A player indicator "
        + "must name a pattern for every indicator. Fix: Give patterns off, player1, player2, "
        + "player3 and player4."
    )
  }

  @Test
  func aRequestWithoutDataNamesTheCount() {
    #expect(
      Self.message { _ = try SubcommandRequest(subcommand: 1, data: []) }
        == "057e-2009.plist, session.subcommands.requests[].data: A subcommand request must "
        + "name 1...16 data bytes. Fix: Give data 1...16 bytes."
    )
  }

  @Test
  func anSPIReadLengthOutsideItsRangeNamesTheRange() {
    let read = SubcommandRequest.SPIRead(address: 0, length: 0, purpose: .factoryMotionCalibration)
    #expect(
      Self.message { _ = try SubcommandRequest(subcommand: 0x10, spiRead: read) }
        == "057e-2009.plist, session.subcommands.requests[].spiRead.length: An SPI read length "
        + "must be 1...29. Fix: Set length to 1...29."
    )
  }
}
