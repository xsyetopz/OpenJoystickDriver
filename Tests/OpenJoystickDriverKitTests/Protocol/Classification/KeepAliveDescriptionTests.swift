import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The keep-alive interval and fixed writes of GameSir, GIP, Switch 2 and the Steam Deck and Triton
/// come from `defaults.session.keepAlive` in the family's description.
///
/// The decoder is the only validator of these documents (the protocol description tests), and each
/// driver sends the description's bytes at the description's interval.
private let writes500 = #"{"intervalMilliseconds": 500, "writes": ["#
private let hidWriteHead =
  #"{"report": {"kind": "Feature", "id": 1, "length": 4}, "bytes": "01 02 03", "#
private let nineWrites = Array(repeating: keepAliveUSBWrite, count: 9).joined(separator: ",")
private let keepAliveUSBWrite = #"{"bytes": "03 20 00 03", "sessionByte": 2}"#

struct KeepAliveDescriptionTests {
  private static let usbWrite = keepAliveUSBWrite
  private static let hidWrite =
    #"{"report": {"kind": "Feature", "id": 1, "length": 4}, "bytes": "01 02 03"}"#

  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    try ProtocolDescriptionFixture.decode(family: family, body)
  }

  private func rejection(family: PhysicalProtocolID, _ body: String) -> ProtocolDescriptionProblem?
  {
    do {
      _ = try decode(family: family, body)
      return nil
    } catch { return error }
  }

  private func gip(_ keepAlive: String) -> String {
    #""rawUSB": true, "rawUSBTuningKeys": ["lizardResendTicks"], "defaults": {"#
      + #""session": {"keepAlive": \#(keepAlive)}}"#
  }

  // MARK: - Decoder

  @Test
  func acceptsAKeepAliveWithItsIntervalAndWrites() throws {
    let description = try decode(
      family: .xboxGIP,
      gip(#"{"intervalMilliseconds": 4000, "writes": [\#(Self.usbWrite)]}"#)
    )
    #expect(description.keepAlive?.intervalMilliseconds == 4000)
    #expect(description.keepAliveWrites(variant: .usb).count == 1)
    let intervalOnly = try decode(family: .xboxGIP, gip(#"{"intervalMilliseconds": 1}"#))
    #expect(intervalOnly.keepAlive?.intervalMilliseconds == 1)
    #expect(intervalOnly.keepAliveWrites(variant: .usb).isEmpty)
  }

  @Test(
    arguments: [
      "{}", #"{"writes": [\#(keepAliveUSBWrite)]}"#, #"{"intervalMilliseconds": 0}"#,
      #"{"intervalMilliseconds": 60001}"#, #"{"intervalMilliseconds": 1.5}"#,
      #"{"intervalMilliseconds": "500"}"#, #"{"intervalMilliseconds": 500, "unknown": 1}"#,
      #"{"intervalMilliseconds": 500, "writes": []}"#,
      writes500 + nineWrites + "]}",
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": ""}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "sessionByte": 64}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "endpoint": 0}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "variants": []}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "resendTuning": "x"}]}"#,
      writes500 + #"{"bytes": "01", "resendTuning": "keepAliveIntervalMs"}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "delayMilliseconds": 5}]}"#,
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "toleratesRejection": true}]}"#,
      writes500 + #"{"bytes": "01", "when": {"parameter": "layout", "is": ["Pro"]}}]}"#,
    ]
  )
  func rejectsAMalformedKeepAlive(keepAlive: String) {
    #expect(
      rejection(family: .xboxGIP, gip(keepAlive))?.code == .invalidProtocolDescription,
      "\(keepAlive)"
    )
  }

  @Test(
    arguments: [
      hidWriteHead + #""phase": "Startup"}"#,
      hidWriteHead + #""delayMilliseconds": 5}"#,
      hidWriteHead + #""transport": "USB"}"#,
      hidWriteHead + #""crc32Seed": 1}"#,
    ]
  )
  func rejectsStartupOnlyMembersInAKeepAliveWrite(write: String) {
    let body =
      #""tuningKeys": ["hidStartupIntervalMs"], "defaults": {"session": {"keepAlive": "#
      + #"{"intervalMilliseconds": 500, "writes": [\#(write)]}}}"#
    #expect(rejection(family: .sonyDualSense, body)?.code == .invalidProtocolDescription)
  }

  @Test
  func rejectsAKeepAliveTheFamilyCannotRun() {
    let interval = #"{"intervalMilliseconds": 500}"#
    // A HID write for a raw-USB family, and a raw-USB write for a HID family.
    #expect(
      rejection(
        family: .xboxGIP,
        gip(#"{"intervalMilliseconds": 500, "writes": [\#(Self.hidWrite)]}"#)
      )?
      .code == .invalidProtocolDescription
    )
    let hidFamily =
      #""tuningKeys": ["hidStartupIntervalMs"], "defaults": {"session": {"keepAlive": "#
      + #"{"intervalMilliseconds": 500, "writes": [\#(Self.usbWrite)]}}}"#
    #expect(rejection(family: .sonyDualSense, hidFamily)?.code == .invalidProtocolDescription)
    // A variant the family lacks.
    let variant =
      #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01", "variants": ["Wired"]}]}"#
    #expect(rejection(family: .xboxGIP, gip(variant))?.code == .unknownProtocolVariant)
    // A cadence key the family does not default.
    let cadence =
      writes500 + #"{"bytes": "01", "resendTuning": "lizardResendTicks"}]}"#
    #expect(rejection(family: .xboxGIP, gip(cadence))?.code == .invalidProtocolDescription)
    // Records never carry keep-alive writes.
    #expect(
      rejection(
        family: .xboxXID,
        #""rawUSB": true, "defaults": {"session": {"keepAlive": \#(interval)}}"#
      ) != nil
    )
  }

  /// The interval has one home. `keepAliveIntervalMs` is no tuning key, so a description names
  /// it nowhere, and a control with a real key in the same place decodes.
  @Test(
    arguments: [
      #""rawUSB": true, "rawUSBTuningKeys": ["KEY"]"#,
      #""tuningKeys": ["KEY"]"#,
      #""rawUSB": true, "rawUSBTuningKeys": ["usbCommandTimeoutMs"], "#
        + #""defaults": {"tuning": {"KEY": 500}}"#,
      #""rawUSB": true, "rawUSBTuningKeys": ["usbCommandTimeoutMs"], "#
        + #""defaults": {"variants": {"USB": {"tuning": {"KEY": 500}}}}"#,
    ]
  )
  func rejectsTheIntervalAsATuningKey(template: String) throws {
    let family = PhysicalProtocolID.xboxGIP
    _ = try decode(
      family: family,
      template.replacingOccurrences(of: "KEY", with: "usbCommandTimeoutMs")
    )
    #expect(
      rejection(
        family: family,
        template.replacingOccurrences(of: "KEY", with: "keepAliveIntervalMs")
      )
        != nil,
      "\(template)"
    )
  }

  // MARK: - Drivers keep their bytes and interval

  @Test
  func gameSirSendsItsHeartbeatsEvery500Milliseconds() {
    let enhanced = GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true)
    #expect(enhanced.sessionPlan.hidKeepAliveIntervalNanoseconds == 500_000_000)
    let heartbeat = enhanced.keepAliveWrites().hidOutputs
    #expect(heartbeat.map(\.reportID) == [0x0F])
    #expect(heartbeat.map(\.bytes) == [[0x0F, 0xF2] + [UInt8](repeating: 0, count: 62)])

    let g7 = GameSirDriver(protocol: .g7ProUSB)
    #expect(g7.sessionPlan.usbKeepAliveIntervalNanoseconds == 500_000_000)
    for sequence in 1...3 {
      let packets = g7.keepAliveWrites().usbPackets
      #expect(
        packets.map(\.bytes)
          == [[0x0F, 0x00, UInt8(sequence), 0x02, 0xF2, 0x00] + [UInt8](repeating: 0, count: 58)]
      )
      #expect(packets.map(\.endpoint) == [g7.outEndpoint])
      #expect(packets.map(\.timeoutMilliseconds) == [g7.usbTimeoutMilliseconds])
    }
  }

  @Test
  func gipSendsItsStatusPacketEvery4SecondsAndNoneWhenDisabled() {
    let driver = GIPDriver()
    #expect(driver.sessionPlan.usbKeepAliveIntervalNanoseconds == 4_000_000_000)
    let first = driver.keepAliveWrites().usbPackets
    let second = driver.keepAliveWrites().usbPackets
    #expect(first.map(\.bytes) == [[0x03, 0x20, 1, 0x03, 0x00, 0x00, 0x00]])
    #expect(second.map(\.bytes) == [[0x03, 0x20, 2, 0x03, 0x00, 0x00, 0x00]])
    #expect(first.map(\.endpoint) == [PhysicalProtocolID.xboxGIP.descriptionOutputEndpoint])
    #expect(GIPDriver(keepAlivePolicy: .disabled).keepAliveWrites().isEmpty)
    #expect(
      GIPDriver(keepAlivePolicy: .disabled).sessionPlan.usbKeepAliveIntervalNanoseconds == nil
    )
  }

  @Test
  func switch2KeepsItsIntervalInTheDescription() {
    let description = PhysicalProtocolID.nintendoSwitch2.protocolDescription
    #expect(description.keepAlive?.intervalMilliseconds == 12)
    #expect(description.keepAliveWrites(variant: .usb).isEmpty)
    let driver = Switch2Driver(layout: .pro, link: .usb)
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 12_000_000)
  }

  @Test
  func steamDeckSendsTheLizardWatchdogEverySecond() {
    let driver = SteamDeckDriver()
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 1_000_000_000)
    let features = driver.keepAliveWrites().hidFeatures
    #expect(features.map(\.reportID) == [0, 0])
    #expect(
      features.map(\.bytes) == [
        [0x81] + [UInt8](repeating: 0, count: 63),
        [0x87, 0x03, 0x08, 0x07, 0x00, 0x00] + [UInt8](repeating: 0, count: 58),
      ]
    )
  }

  @Test
  func steamTritonResendsLizardModeOffOnlyEvery75thTick() {
    let driver = SteamTritonDriver()
    #expect(driver.sessionPlan.hidKeepAliveIntervalNanoseconds == 40_000_000)
    let lizardOff =
      [0x01, 0x87, 0x03, 0x09, 0x00, 0x00].map(UInt8.init) + [UInt8](repeating: 0, count: 58)
    let ticks = (0..<76).map { _ in driver.keepAliveWrites().hidFeatures }
    #expect(ticks.enumerated().filter { !$0.element.isEmpty }.map(\.offset) == [0, 75])
    #expect(ticks[0].map(\.bytes) == [lizardOff])
    #expect(ticks[0].map(\.reportID) == [1])
  }

  /// A driver names the channels it keeps alive and takes the one interval from its
  /// description; no driver carries a `0` placeholder.
  @Test
  func driversNameTheirKeepAliveChannelsAndTakeTheIntervalFromTheDescription() throws {
    let cases: [(String, PhysicalProtocolID, DriverSessionPlan, Set<KeepAliveChannel>)] = [
      (
        "GameSir enhanced HID", .vendorGameSir,
        GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true).sessionPlan, [.hid]
      ),
      (
        "GameSir G7 Pro USB", .vendorGameSir, GameSirDriver(protocol: .g7ProUSB).sessionPlan,
        [.usb, .hid]
      ),
      ("GIP", .xboxGIP, GIPDriver().sessionPlan, [.usb]),
      (
        "Switch 2", .nintendoSwitch2, Switch2Driver(layout: .pro, link: .usb).sessionPlan, [.hid]
      ),
      ("Steam Deck", .valveSteamDeck, SteamDeckDriver().sessionPlan, [.hid]),
      ("Steam Triton", .valveSteamTriton, SteamTritonDriver().sessionPlan, [.hid]),
    ]
    for (name, family, plan, channels) in cases {
      #expect(plan.keepAliveChannels == channels, "\(name)")
      let milliseconds = try #require(family.protocolDescription.keepAlive?.intervalMilliseconds)
      let interval = UInt64(milliseconds) * 1_000_000
      #expect(plan.keepAliveIntervalNanoseconds == interval, "\(name)")
      #expect(plan.keepAliveIntervalNanoseconds != 0, "\(name)")
      #expect(plan.usbKeepAliveIntervalNanoseconds == (channels.contains(.usb) ? interval : nil))
      #expect(plan.hidKeepAliveIntervalNanoseconds == (channels.contains(.hid) ? interval : nil))
    }
    let disabled = GIPDriver(keepAlivePolicy: .disabled).sessionPlan
    #expect(disabled.keepAliveChannels.isEmpty)
    #expect(disabled.keepAliveIntervalNanoseconds == nil)
  }
}
