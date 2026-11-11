import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct KeepAliveMessageTests {
  private static func message(_ json: String) -> String? {
    do {
      _ = try JSONDecoder().decode(KeepAlive.self, from: Data(json.utf8))
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "28de-1205.plist"
      )
    }
  }

  @Test
  func anIntervalOutsideItsRangeNamesTheKey() {
    #expect(
      Self.message(#"{"intervalMilliseconds": 0}"#)
        == "28de-1205.plist, session.keepAlive.intervalMilliseconds: A keep-alive interval must "
        + "be 1...60000 ms. Fix: Set intervalMilliseconds to 1...60000."
    )
  }

  @Test
  func anEmptyWritesListNamesTheKey() {
    #expect(
      Self.message(#"{"intervalMilliseconds": 100, "writes": []}"#)
        == "28de-1205.plist, session.keepAlive.writes: A keep-alive must name no writes or 1...8 "
        + "of them. Fix: List 1...8 writes, or leave writes out."
    )
  }

  @Test
  func moreThanEightWritesNameTheKey() {
    let writes = Array(repeating: #"{"bytes": "01"}"#, count: 9).joined(separator: ",")
    #expect(
      Self.message(#"{"intervalMilliseconds": 100, "writes": [\#(writes)]}"#)
        == "28de-1205.plist, session.keepAlive.writes: A keep-alive must name no writes or 1...8 "
        + "of them. Fix: List 1...8 writes, or leave writes out."
    )
  }

  @Test
  func aWrongResendTuningNamesTheKey() {
    #expect(
      Self.message(
        #"{"intervalMilliseconds": 100, "writes": [{"bytes": "01", "resendTuning": "x"}]}"#
      )
        == "28de-1205.plist, session.keepAlive.writes[].resendTuning: A keep-alive resendTuning "
        + "must be lizardResendTicks. Fix: Set resendTuning to lizardResendTicks, or leave it out."
    )
  }
}
