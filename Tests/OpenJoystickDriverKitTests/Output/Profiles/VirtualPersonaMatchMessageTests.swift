import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct VirtualPersonaMatchMessageTests {
  private static func message(_ key: String, arguments: [String] = []) -> String {
    ControllerRecordSet.problemDescription(
      ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: key,
        arguments: arguments,
        "unused"
      ),
      document: "virtualDevice",
      localization: Localization(preferredLanguages: ["en-US"]),
      file: "1234-abcd.plist"
    )
  }

  @Test
  func aMatchTakenByAUserFileNamesThatFile() {
    #expect(
      Self.message("error.E5007.virtualDevice.matchTakenByUserFile", arguments: ["mine.plist"])
        == "1234-abcd.plist, match: A persona file must not repeat the match of the user file "
        + "mine.plist. Fix: Give each model one persona file, or change match in one of the two."
    )
  }

  @Test
  func aMatchTakenByAPackageFileNamesThatFile() {
    #expect(
      Self.message("error.E5007.virtualDevice.matchTakenByPackageFile", arguments: ["pack.plist"])
        == "1234-abcd.plist, match: A persona file must not repeat the match of the package file "
        + "pack.plist. Fix: Give each model one persona file, or change match in one of the two."
    )
  }
}
