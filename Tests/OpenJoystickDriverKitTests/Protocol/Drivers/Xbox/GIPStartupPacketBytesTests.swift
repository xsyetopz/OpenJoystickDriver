import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The bytes and sequence numbers the GIP driver stamps on each named startup packet of
/// `defaults.session.namedPackets` in `xbox-gip.json`.
struct GIPStartupPacketBytesTests {
  private static let identifiers = [
    "XboxGIP/power-on", "XboxGIP/s-init", "XboxGIP/enable-extra-input", "XboxGIP/hori-ack",
    "XboxGIP/led-on", "XboxGIP/auth-done", "XboxGIP/rumble-begin", "XboxGIP/rumble-end",
  ]

  /// The Vader 5S (`37D7:2801`) needs the Hori acknowledgement and the LED packet before
  /// authentication, and it runs no post-handshake settle (#40).
  @Test
  func vaderFiveSRecordRunsHoriStartupSequenceWithoutSettle() throws {
    let model = ControllerModelID(vendorID: 0x37D7, productID: 0x2801)
    let profile = try #require(ProtocolDriverRegistry().record(for: model))
    #expect(profile.physicalProtocolID == .xboxGIP)
    #expect(
      profile.gipStartupPackets == [
        "XboxGIP/hori-ack", "XboxGIP/led-on", "XboxGIP/auth-done", "XboxGIP/power-on",
      ]
    )
    #expect(profile.session.settleMilliseconds == nil)
    #expect(profile.transportProfile.postHandshakeSettleNanoseconds == 0)
  }

  private func driver(_ identifiers: [String]) -> GIPDriver {
    GIPDriver(startupPackets: identifiers)
  }

  private func hex(_ write: PhysicalOutputWrite) -> String {
    guard case .usb(let packet, _) = write else { return "other" }
    return "\(packet.endpoint):" + packet.bytes.map { unsafe String(format: "%02x", $0) }.joined()
  }

  private func startup(_ identifiers: [String]) -> [String] {
    driver(identifiers).startupWrites().map(hex)
  }

  /// Each packet alone, in a fresh driver: the first sequence number of its command counter.
  private static let alone: [String: String] = [
    "XboxGIP/power-on": "2:0520010100",
    "XboxGIP/s-init": "2:0520010f06",
    "XboxGIP/enable-extra-input": "2:4d1001020700",
    "XboxGIP/hori-ack": "2:012001090004203a0000008000",
    "XboxGIP/led-on": "2:0a200103000114",
    "XboxGIP/auth-done": "2:062001020100",
    "XboxGIP/rumble-begin": "2:09000109000f00001d1dff0000",
    "XboxGIP/rumble-end": "2:09000109000f00000000000000",
  ]

  private static let all = [
    "2:0520010100", "2:0520020f06", "2:4d1001020700", "2:012003090004203a0000008000",
    "2:0a200403000114", "2:062001020100", "2:09000109000f00001d1dff0000",
    "2:09000209000f00000000000000",
  ]

  private static let reversed = [
    "2:09000109000f00000000000000", "2:09000209000f00001d1dff0000", "2:062001020100",
    "2:0a200103000114", "2:012002090004203a0000008000", "2:4d1001020700", "2:0520030f06",
    "2:0520040100",
  ]

  @Test
  func testEachNamedPacketAloneCarriesSameBytes() {
    for identifier in Self.identifiers {
      #expect(startup([identifier]) == [Self.alone[identifier]], "\(identifier)")
    }
  }

  @Test
  func testAllNamedPacketsShareCommandCountersInListOrder() {
    #expect(startup(Self.identifiers) == Self.all)
    #expect(startup(Self.identifiers.reversed()) == Self.reversed)
  }

  @Test
  func testRepeatedPacketTakesNextSequenceNumber() {
    let twice = startup(["XboxGIP/power-on", "XboxGIP/power-on", "XboxGIP/s-init"])
    #expect(twice == ["2:0520010100", "2:0520020100", "2:0520030f06"])
  }

  @Test
  func testSequenceNumbersContinueAcrossStartupsAndIntoKeepAlive() {
    let gip = driver(Self.identifiers)
    #expect(gip.startupWrites().map(hex) == Self.all)
    #expect(
      gip.startupWrites().map(hex) == [
        "2:0520050100", "2:0520060f06", "2:4d1002020700", "2:012007090004203a0000008000",
        "2:0a200803000114", "2:062002020100", "2:09000309000f00001d1dff0000",
        "2:09000409000f00000000000000",
      ]
    )
    #expect(gip.keepAliveWrites().map(hex) == ["2:03200903000000"])
  }

  @Test
  func testDefaultStartupIsPowerOnLedOnAuthDone() {
    #expect(
      GIPDriver().startupWrites().map(hex)
        == ["2:0520010100", "2:0a200203000114", "2:062001020100"]
    )
  }
}
