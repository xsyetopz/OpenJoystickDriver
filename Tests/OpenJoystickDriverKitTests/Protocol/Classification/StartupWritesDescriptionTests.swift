import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A driver sends no startup write that its family's description does not carry.
///
/// A family with raw-USB startup packets returns exactly the description's packets; a family with
/// HID startup writes returns none of them itself, only the reports that depend on session state.
struct StartupWritesDescriptionTests {
  private static let switch2Layouts: [Switch2ControllerLayout] = [
    .pro, .leftJoyCon, .rightJoyCon, .gameCube,
  ]

  /// The packet with its per-session byte cleared, so a stamped packet compares to the
  /// description's.
  private func unstamped(
    _ write: PhysicalOutputWrite,
    sessionByte: Int?
  ) -> PhysicalUSBOutputPacket? {
    guard case .usb(var packet, _) = write else { return nil }
    if let sessionByte, packet.bytes.indices.contains(sessionByte) {
      packet = PhysicalUSBOutputPacket(
        endpoint: packet.endpoint,
        bytes: packet.bytes.enumerated().map { $0.offset == sessionByte ? 0 : $0.element },
        timeoutMilliseconds: packet.timeoutMilliseconds
      )
    }
    return packet
  }

  private func expectDriverSends(
    _ writes: [PhysicalOutputWrite],
    exactly described: [USBStartupWrite],
    family: PhysicalProtocolID,
    timeoutMilliseconds: Int,
    _ label: String
  ) {
    #expect(writes.count == described.count, "\(label)")
    for (write, source) in zip(writes, described) {
      let packet = unstamped(write, sessionByte: source.sessionByte)
      #expect(
        packet?.bytes
          == source.bytes.enumerated().map {
            $0.offset == source.sessionByte ? 0 : $0.element
          },
        "\(label)"
      )
      #expect(packet?.endpoint == source.endpoint ?? family.descriptionOutputEndpoint, "\(label)")
      #expect(
        Int(packet?.timeoutMilliseconds ?? 0) == source.timeoutMilliseconds ?? timeoutMilliseconds,
        "\(label)"
      )
    }
  }

  @Test(arguments: [Switch2Link.usb, .bluetoothLE], switch2Layouts)
  func switch2SendsExactlyDescriptionsPackets(link: Switch2Link, layout: Switch2ControllerLayout) {
    let variant: PhysicalProtocolVariantID = link == .usb ? .usb : .bluetoothLE
    let described = PhysicalProtocolID.nintendoSwitch2.protocolDescription.usbStartupWrites(
      variant: variant,
      parameters: ProtocolParameters(layout: layout.parameter)
    )
    #expect(!described.isEmpty)
    let driver = Switch2Driver(layout: layout, link: link)
    expectDriverSends(
      driver.startupWrites(),
      exactly: described,
      family: .nintendoSwitch2,
      timeoutMilliseconds: 1_000,
      "\(link) \(layout)"
    )
    #expect(
      driver.startupWrites().usbPackets.allSatisfy { $0.bytes[2] == link.commandTransportByte }
    )
  }

  @Test(arguments: [false, true])
  func xusbSendsExactlyDescriptionsPackets(isWirelessReceiver: Bool) {
    let described = PhysicalProtocolID.xboxXUSB.protocolDescription.usbStartupWrites(
      variant: isWirelessReceiver ? .receiver : .wired,
      parameters: .none
    )
    let driver = XUSBDriver(isWirelessReceiver: isWirelessReceiver)
    expectDriverSends(
      driver.startupWrites(),
      exactly: described,
      family: .xboxXUSB,
      timeoutMilliseconds: 2_000,
      "receiver \(isWirelessReceiver)"
    )
    #expect(described.isEmpty == !isWirelessReceiver)
  }

  @Test
  func gipSendsExactlyDescriptionsPackets() {
    let described = PhysicalProtocolID.xboxGIP.protocolDescription.usbStartupWrites(
      variant: .usb,
      parameters: .none
    )
    #expect(described.count == 3)
    expectDriverSends(
      GIPDriver().startupWrites(),
      exactly: described,
      family: .xboxGIP,
      timeoutMilliseconds: 2_000,
      "gip"
    )
  }

  @Test
  func recordsUSBWritesReplaceDescriptionsAndAreSentAsNamed() throws {
    let write = try USBStartupWrite(bytes: [9, 9], endpoint: 3, timeoutMilliseconds: 40)
    let driver = Switch2Driver(usbStartupWrites: [write])
    #expect(driver.startupWrites().usbBytes == [[9, 9]])
    #expect(driver.startupWrites().usbPackets.first?.endpoint == 3)
  }

  /// The HID startup writes a family declares are the description's, so its driver returns none
  /// of them.
  @Test
  func hidFamiliesLeaveTheirDeclaredWritesToDescription() {
    for gameSir in [
      GameSirDriver(protocol: .g7ProUSB),
      GameSirDriver(protocol: .enhancedHID),
      GameSirDriver(protocol: .enhancedHID, hasInnerGrips: true),
      GameSirDriver(protocol: .enhancedHID, usesLightingSlots: true),
    ] {
      #expect(gameSir.startupWrites().isEmpty)
    }
    #expect(DualShock4Driver().startupWrites().isEmpty)
    #expect(DualShock4Driver(prefersBluetooth: true).startupWrites().isEmpty)

    let gameSirDescription = PhysicalProtocolID.vendorGameSir.protocolDescription
    #expect(
      gameSirDescription.startupWrites(phase: .startup, variant: .usb, parameters: .none)
        .isEmpty
    )
    let heartbeat = gameSirDescription.startupWrites(
      phase: .startup,
      variant: .enhancedHID,
      parameters: .none
    )
    #expect(heartbeat.map(\.write).hidOutputs.map(\.reportID) == [0x0F])
    let slots = gameSirDescription.startupWrites(
      phase: .startup,
      variant: .enhancedHID,
      parameters: ProtocolParameters(lightingMemory: .profileSlots)
    )
    #expect(slots.count == heartbeat.count + 1)

    let ds4 = PhysicalProtocolID.sonyDualShock4.protocolDescription
    #expect(ds4.startupWrites(phase: .startup, variant: .usb, parameters: .none).isEmpty)
    let bluetooth = ds4.startupWrites(
      phase: .startup,
      variant: .bluetoothClassic,
      parameters: .none
    )
    #expect(bluetooth.count == 1)
    #expect(bluetooth.first?.crc32Seed != nil)
  }

  /// Switch 1 keeps the reports that carry its rolling packet counter; its handshake commands
  /// (report 0x80) are the description's alone.
  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon], [false, true])
  func switch1DriverSendsNoHandshakeCommand(layout: NintendoControllerLayout, isBluetooth: Bool) {
    let layouts: [NintendoControllerLayout: ProtocolParameters.Layout] = [
      .pro: .pro, .leftJoyCon: .joyConLeft, .rightJoyCon: .joyConRight,
    ]
    let driver = Switch1Driver(layout: layout, isBluetooth: isBluetooth)
    let reports = driver.startupWrites().hidOutputs
    #expect(!reports.isEmpty)
    #expect(reports.allSatisfy { $0.reportID == 0x01 })
    let described = PhysicalProtocolID.nintendoSwitch1.protocolDescription.startupWrites(
      phase: .startup,
      variant: isBluetooth ? .bluetoothClassic : .usb,
      parameters: ProtocolParameters(layout: layouts[layout])
    ).map(\.write).hidOutputs
    #expect(described.allSatisfy { $0.reportID == 0x80 })
    #expect(described.isEmpty == (isBluetooth || layout != .pro))
  }
}
