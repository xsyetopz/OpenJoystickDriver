import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ControllerRecordSubcommandsMessageTests {
  private static func message(_ json: String) -> String? {
    do {
      _ = try JSONDecoder().decode(SubcommandRequest.self, from: Data(json.utf8))
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
  func aRequestWithNeitherDataNorSPIReadNamesBothKeys() {
    #expect(
      Self.message(#"{"subcommand": 1}"#)
        == "057e-2009.plist, session.subcommands.requests[]: A subcommand request must name "
        + "exactly one of data and spiRead. Fix: Keep data or spiRead, and remove the other."
    )
  }

  @Test
  func aDecodedDataCountOutsideItsRangeKeepsItsOwnMessage() {
    #expect(
      Self.message(#"{"subcommand": 1, "data": "00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10"}"#)
        == "057e-2009.plist, session.subcommands.requests[].data: A subcommand request must "
        + "name 1...16 data bytes. Fix: Give data 1...16 bytes."
    )
  }
}
