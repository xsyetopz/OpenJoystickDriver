import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct DualSenseDriverTests {
  static let family = PhysicalProtocolID.sonyDualSense
  static let model = ControllerModelID(vendorID: 0x054C, productID: 0x0CE6)

  @Test
  func testDualSenseUSBReportParsesPrimaryControls() throws {
    let model = ControllerModelID(vendorID: 1356, productID: 3302)
    let parser = try catalogParser(model)
    _ = try parser.parseReport(ProtocolPacketFixtures.DualSense.usbInputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.DualSense.usbInputReport(
        sticks: ((255, 0), (0, 255)),
        triggers: (255, 128),
        buttons: (0x28, 0x30, 0x03)
      )
    )

    #expect(events.contains(.leftStick(x: 1.0, y: -1.0)))
    #expect(events.contains(.rightStick(x: -1.0, y: 1.0)))
    #expect(events.contains(.leftTrigger(1.0)))
    #expect(events.contains(.rightTrigger(128.0 / 255.0)))
    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.press(.touchpadClick)))
  }

  @Test
  func testDualSenseBluetoothReportParsesPrimaryControlsWithCRC() throws {
    let parser = DualSenseDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.DualSense.bluetoothInputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.DualSense.bluetoothInputReport(
        sticks: ((255, 0), (0, 255)),
        triggers: (255, 128),
        buttons: (0x28, 0x30, 0x07)
      )
    )

    #expect(events.contains(.leftStick(x: 1.0, y: -1.0)))
    #expect(events.contains(.rightStick(x: -1.0, y: 1.0)))
    #expect(events.contains(.leftTrigger(1.0)))
    #expect(events.contains(.rightTrigger(128.0 / 255.0)))
    #expect(events.contains(.press(.south)))
    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.press(.touchpadClick)))
    #expect(events.contains(.press(.microphone)))
  }

  @Test
  func testDualSenseUnknownReportIDIsIgnored() throws {
    let parser = DualSenseDriver()
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 0x02
    report[1] = 255
    report[2] = 0
    report[5] = 255
    report[8] = 0x28

    #expect(try parser.parseReport(Data(report)) == nil)
  }

  @Test
  func testDualSenseBluetoothReportRejectsInvalidCRC() {
    let parser = DualSenseDriver()
    var report = Array(ProtocolPacketFixtures.DualSense.bluetoothInputReport(buttons: (0x28, 0, 0)))
    report[77] ^= 0xFF

    do {
      _ = try parser.parseReport(Data(report))
      #expect(Bool(false))
    } catch let error as DualSenseDriverError { #expect(error == .invalidBluetoothCRC) } catch {
      #expect(Bool(false))
    }
  }

  @Test
  func testDualSenseUSBReportParsesMicrophoneMute() throws {
    let parser = DualSenseDriver()
    _ = try parser.parseReport(ProtocolPacketFixtures.DualSense.usbInputReport())

    let events = try parser.parseReport(
      ProtocolPacketFixtures.DualSense.usbInputReport(buttons: (0x08, 0, 0x04))
    )

    #expect(events.contains(.press(.microphone)))
  }

  @Test
  func testDualSenseProfilesAreExperimentalAndUnverified() throws {
    let registry = ProtocolDriverRegistry()
    let models = [
      ControllerModelID(vendorID: 1356, productID: 3302),
      ControllerModelID(vendorID: 1356, productID: 3570),
    ]

    for model in models {
      let profile = try #require(registry.record(for: model))
      #expect(
        profile.physicalProtocolID == .sonyDualSense && profile.physicalProtocolVariant == nil
      )
      #expect(profile.parameters.isEmpty)
      #expect(
        profile.capabilityDelta.presentControls
          == (model.productID == 3570 ? DualSenseDriver.edgeControls : [])
      )
    }
  }

  @Test
  func bluetoothSensorPayloadMatchesUSBAndBadCRCCannotAdvanceClock() throws {
    var report = Array(ProtocolPacketFixtures.DualSense.bluetoothInputReport())
    report[17] = 0xFF
    report[18] = 0xFF
    report[29] = 3
    let crc = ProtocolPacketFixtures.DualSense.bluetoothInputCRC32(report)
    for index in 0..<4 { report[74 + index] = UInt8(truncatingIfNeeded: crc >> (index * 8)) }
    let parser = DualSenseDriver()
    let first = try parser.parseReport(Data([0xA1] + report))
    let motion = try #require(first?.motion.first)
    #expect(isClose(motion.angularVelocity, radiansPerSecond(-1.0 / 16, 0, 0)))
    #expect(motion.timestamp.rawCounter == 3)
    report[29] = 6
    #expect(throws: DualSenseDriverError.invalidBluetoothCRC) {
      try parser.parseReport(Data(report))
    }
    let repeated = try parser.parseReport(ProtocolPacketFixtures.DualSense.bluetoothInputReport())
    let next = try #require(repeated?.motion.first)
    #expect(next.timestamp.sequenceIndex == 1)
  }

}

extension DualSenseDriverTests {
  @Test(arguments: [
    (UInt8(0x10), Control.auxiliary1, Control.auxiliary1),
    (UInt8(0x20), Control.auxiliary2, Control.auxiliary2),
    (UInt8(0x40), Control.leftPaddle1, Control.leftPaddle1),
    (UInt8(0x80), Control.rightPaddle1, Control.rightPaddle1),
  ])
  func edgeButtonMapsFromUSBAndBluetooth(
    mask: UInt8,
    physical: Control,
    source: Control
  ) throws {
    for bluetooth in [false, true] {
      let identifier = LogicalControllerID(vendorID: 0x054C, productID: 0x0DF2)
      let parser = try catalogParser(identifier.model)
      let report =
        bluetooth
        ? ProtocolPacketFixtures.DualSense.bluetoothInputReport(buttons: (0x08, 0, mask))
        : ProtocolPacketFixtures.DualSense.usbInputReport(buttons: (0x08, 0, mask))
      let neutral =
        bluetooth
        ? ProtocolPacketFixtures.DualSense.bluetoothInputReport()
        : ProtocolPacketFixtures.DualSense.usbInputReport()
      let profile = RemappingProfile(
        name: "Edge mapping",
        device: RemappingDeviceScope(vendorID: 0x054C, productID: 0x0DF2),
        applicationScope: .global,
        outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
        bindings: [RemappingBinding(source: .button(source), destination: .gamepadButton(.south))]
      )
      try profile.validate()
      let pressed = try #require(try parser.parseReport(report))
      #expect(pressed.holds(.press(physical)))
      var engine = RemappingEngineState()
      func process(_ event: ControllerEvent, at time: UInt64) -> [RemappingEngineAction] {
        engine.process(
          event,
          from: identifier,
          into: identifier,
          profile: profile,
          at: time
        )
      }
      #expect(
        process(pressed, at: 0) == [.gamepad(RemappingGamepadState(buttons: [.south]), identifier)]
      )
      // A repeated report holds the button without a new transition.
      #expect(process(try #require(try parser.parseReport(report)), at: 1).isEmpty)
      #expect(
        process(try #require(try parser.parseReport(neutral)), at: 2) == [
          .gamepad(.neutral, identifier)
        ]
      )
    }
  }

  @Test
  func ordinaryDualSenseDoesNotDecodeEdgeButtonBits() throws {
    let model = ControllerModelID(vendorID: 0x054C, productID: 0x0CE6)
    let parser = try catalogParser(model)
    let events = try parser.parseReport(
      ProtocolPacketFixtures.DualSense.usbInputReport(buttons: (0x08, 0, 0xF0))
    )
    #expect(events?.state.pressed.isEmpty == true)
    #expect(!parser.capabilities.controls.contains(.leftPaddle1))
  }

  @Test
  func badBluetoothCRCCannotConsumeAnEdgeButtonPress() throws {
    let parser = DualSenseDriver(hasEdgeButtons: true)
    let valid = ProtocolPacketFixtures.DualSense.bluetoothInputReport(buttons: (0x08, 0, 0x40))
    var bad = valid
    bad[77] ^= 0xFF
    #expect(throws: DualSenseDriverError.invalidBluetoothCRC) { try parser.parseReport(bad) }
    #expect(try parser.parseReport(valid).contains(.press(.leftPaddle1)))
    #expect(
      try parser.parseReport(ProtocolPacketFixtures.DualSense.bluetoothInputReport()).contains(
        .release(.leftPaddle1)
      )
    )
  }

  @Test
  func adaptiveTriggerResistanceUsesBoundedUSBEffectPayload() {
    let parser = DualSenseDriver()
    let report = parser.encoded(
      .setAdaptiveTrigger(
        .left,
        PhysicalAdaptiveTriggerEffect(kind: .resistance, startPosition: 0.5, strength: 0.75)
      )
    ).onlyReport

    #expect(report.reportID == 0x02)
    #expect(report.bytes[1] == 0x08)
    #expect(Array(report.bytes[22..<25]) == [0x01, 5, 6])
    #expect(Array(report.bytes[11..<22]) == [UInt8](repeating: 0, count: 11))
  }

  @Test
  func adaptiveTriggerBluetoothReportCarriesCRCAndExactSide() {
    let parser = DualSenseDriver(prefersBluetooth: true)
    let report = parser.encoded(
      .setAdaptiveTrigger(
        .right,
        PhysicalAdaptiveTriggerEffect(kind: .resistance, startPosition: 1, strength: 1)
      )
    ).onlyReport

    #expect(report.reportID == 0x31)
    #expect(report.bytes[3] == 0x04)
    #expect(Array(report.bytes[13..<16]) == [0x01, 9, 8])
    #expect(Array(report.bytes[24..<35]) == [UInt8](repeating: 0, count: 11))
    let storedCRC =
      UInt32(report.bytes[74]) | (UInt32(report.bytes[75]) << 8) | (UInt32(report.bytes[76]) << 16)
      | (UInt32(report.bytes[77]) << 24)
    #expect(ProtocolPacketFixtures.DualSense.bluetoothOutputCRC32(report.bytes) == storedCRC)
  }

  @Test
  func invalidAdaptiveTriggerEffectFailsClosedWithoutIntegerConversion() {
    let parser = DualSenseDriver()
    let report = parser.encoded(
      .setAdaptiveTrigger(
        .left,
        PhysicalAdaptiveTriggerEffect(kind: .resistance, startPosition: .infinity, strength: .nan)
      )
    ).onlyReport

    #expect(Array(report.bytes[22..<33]) == [UInt8](repeating: 0, count: 11))
  }
}
