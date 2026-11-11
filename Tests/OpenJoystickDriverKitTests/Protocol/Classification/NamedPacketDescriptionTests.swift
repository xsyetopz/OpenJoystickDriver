import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The GIP named startup packets come from `defaults.session.namedPackets` in the family's
/// description.
///
/// The decoder is the only validator of these documents (the protocol description tests); the bytes
/// the driver sends are pinned in `GIPStartupPacketBytesTests`.
struct NamedPacketDescriptionTests {
  private static let powerOn =
    #"{"id": "XboxGIP/power-on", "bytes": "05 20 00 01 00", "sessionByte": 2}"#

  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    try ProtocolDescriptionFixture.decode(family: family, body)
  }

  private func rejects(family: PhysicalProtocolID = .xboxGIP, _ packets: String) -> Bool {
    do {
      _ = try decode(family: family, #""defaults": {"session": {"namedPackets": \#(packets)}}"#)
      return false
    } catch { return true }
  }

  private func packet(
    id: String = "XboxGIP/power-on",
    bytes: String = #""05 20 00 01 00""#,
    members: String = #""sessionByte": 2"#
  ) -> String {
    #"{"id": "\#(id)", "bytes": \#(bytes), \#(members)}"#
  }

  @Test
  func acceptsWellFormedPackets() throws {
    let ledOn = packet(id: "XboxGIP/led-on", bytes: #""0A 20 00""#)
    let description = try decode(
      family: .xboxGIP,
      #""defaults": {"session": {"namedPackets": [\#(Self.powerOn), \#(ledOn)]}}"#
    )
    let plan = try #require(description.namedPackets)
    #expect(plan.packets.map(\.id) == ["XboxGIP/power-on", "XboxGIP/led-on"])
    #expect(plan.packet(named: "XboxGIP/power-on")?.write.bytes == [5, 32, 0, 1, 0])
    #expect(plan.packet(named: "XboxGIP/power-on")?.write.sessionByte == 2)
    #expect(plan.packet(named: "XboxGIP/missing") == nil)
  }

  @Test
  func rejectsMalformedPackets() {
    let sixteen = (0..<16).map { packet(id: "XboxGIP/packet-\($0)") }
    let seventeen = (0..<17).map { packet(id: "XboxGIP/packet-\($0)") }
    #expect(!rejects("[\(sixteen.joined(separator: ","))]"))
    for packets in [
      "[]",
      "[\(seventeen.joined(separator: ","))]",
      #"[{"bytes": "05 20 00", "sessionByte": 2}]"#,
      #"[{"id": "XboxGIP/power-on", "sessionByte": 2}]"#,
      #"[{"id": "XboxGIP/power-on", "bytes": "05 20 00"}]"#,
      "[\(packet(id: "power-on"))]",
      "[\(packet(id: "XboxGIP/Power-On"))]",
      "[\(packet(id: "XboxGIP/power--on"))]",
      "[\(packet(id: "XboxGIP/"))]",
      "[\(packet(bytes: #""05 20""#))]",
      "[\(packet(bytes: #""05 20 100""#))]",
      "[\(packet(members: #""sessionByte": 1"#))]",
      "[\(packet(members: #""sessionByte": 3"#))]",
      "[\(packet(members: #""sessionByte": 2, "endpoint": 2"#))]",
      "[\(Self.powerOn), \(packet(bytes: #""05 20 00 02""#))]",
      "[\(packet(id: "XboxXUSB/power-on"))]",
    ] {
      #expect(rejects(packets), "\(packets)")
    }
  }

  @Test
  func onlyGIPHasNamedPackets() {
    for family in [PhysicalProtocolID.sonyDualSense, .xboxXUSB, .xboxXID, .nintendoSwitch2] {
      #expect(rejects(family: family, "[\(Self.powerOn)]"), "\(family.rawValue)")
    }
  }

  private func decodeStartup(
    _ startup: String,
    packets: Bool = true
  ) throws
    -> ProtocolDescription
  {
    let named = packets ? #""namedPackets": [\#(Self.powerOn)], "# : ""
    return try decode(
      family: .xboxGIP,
      #""defaults": {"session": {\#(named)"startup": \#(startup)}}"#
    )
  }

  @Test
  func startupReferencesNamedPacketsWithTheirBytes() throws {
    let description = try decodeStartup(
      #"[{"packet": "XboxGIP/power-on"}, {"packet": "XboxGIP/power-on", "variants": ["USB"]}]"#
    )
    #expect(description.usbStartupWrites.map(\.bytes) == [[5, 32, 0, 1, 0], [5, 32, 0, 1, 0]])
    #expect(description.usbStartupWrites.allSatisfy { $0.sessionByte == 2 })
    #expect(description.usbStartupWrites[0].condition == .always)
    #expect(description.usbStartupWrites[1].condition != .always)
  }

  @Test
  func startupRejectsWhatItCannotResolveOrMix() {
    let usb = #"{"bytes": "01 02 03"}"#
    let reference = #"{"packet": "XboxGIP/power-on"}"#
    for startup in [
      #"[{"packet": "XboxGIP/missing"}]"#,
      #"[{"packet": "XboxGIP/power-on", "bytes": "01 02 03"}]"#,
      #"[{"packet": 7}]"#,
      "[\(reference), \(usb)]",
      "[\(usb), \(reference)]",
    ] {
      #expect((try? decodeStartup(startup)) == nil, "\(startup)")
    }
  }

  @Test
  func aRecordCannotReferToAPacketInItsStartup() {
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(
        ControllerRecordDocument.SessionDocument.self,
        from: Data(#"{"startup": [{"packet": "XboxGIP/power-on"}]}"#.utf8)
      )
    }
  }

  @Test
  func theBundledGIPStartupIsTheThreeReferencedPackets() throws {
    let description = PhysicalProtocolID.xboxGIP.protocolDescription
    let plan = try #require(description.namedPackets)
    let expected = ["power-on", "led-on", "auth-done"].compactMap {
      plan.packet(named: "XboxGIP/\($0)")?.write
    }
    #expect(expected.count == 3)
    #expect(description.usbStartupWrites == expected)
  }

  @Test
  func theBundledGIPDescriptionHoldsTheEightPackets() throws {
    let plan = try #require(PhysicalProtocolID.xboxGIP.protocolDescription.namedPackets)
    #expect(
      plan.packets.map(\.id) == [
        "XboxGIP/power-on", "XboxGIP/s-init", "XboxGIP/enable-extra-input",
        "XboxGIP/hori-ack", "XboxGIP/led-on", "XboxGIP/auth-done", "XboxGIP/rumble-begin",
        "XboxGIP/rumble-end",
      ]
    )
    #expect(plan.packets.allSatisfy { $0.write.sessionByte == 2 })
  }
}
