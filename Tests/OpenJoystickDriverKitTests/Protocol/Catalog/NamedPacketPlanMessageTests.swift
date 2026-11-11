import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct NamedPacketPlanMessageTests {
  private static func message(_ json: String) -> String? {
    do {
      _ = try JSONDecoder().decode(NamedPacketPlan.self, from: Data(json.utf8))
      return nil
    } catch {
      return ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "045e-02ea.plist"
      )
    }
  }

  private static func packet(id: String = "xbox/start-input", bytes: String = "05 20 00", sessionByte: Int = 2)
    -> String
  {
    #"{"id": "\#(id)", "bytes": "\#(bytes)", "sessionByte": \#(sessionByte)}"#
  }

  @Test
  func anEmptyListNamesTheCount() {
    #expect(
      Self.message("[]")
        == "045e-02ea.plist, session.namedPackets: Named packets must name 1...16 packets. "
        + "Fix: List 1...16 packets."
    )
  }

  @Test
  func aRepeatedIDNamesTheID() {
    let list = "[\(Self.packet()), \(Self.packet())]"
    #expect(
      Self.message(list)
        == "045e-02ea.plist, session.namedPackets[].id: Each named packet id must appear at most "
        + "once. Fix: Give each packet its own id."
    )
  }

  @Test
  func anIDWithoutAFamilyNamesTheForm() {
    #expect(
      Self.message("[\(Self.packet(id: "start-input"))]")
        == "045e-02ea.plist, session.namedPackets[].id: A named packet id must be a family, a "
        + "slash and lowercase words joined by hyphens. Fix: Write the id like xbox/start-input."
    )
  }

  @Test
  func aShortPacketNamesTheBytesAndSessionByte() {
    #expect(
      Self.message("[\(Self.packet(bytes: "05 20"))]")
        == "045e-02ea.plist, session.namedPackets[].sessionByte: A named packet must have at "
        + "least 3 bytes and its session byte must be 2. Fix: Give bytes at least 3 bytes and "
        + "set sessionByte to 2."
    )
  }
}
