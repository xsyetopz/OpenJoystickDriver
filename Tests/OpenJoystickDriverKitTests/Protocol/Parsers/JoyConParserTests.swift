import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct JoyConParserTests {
  @Test(arguments: [UInt16(0x2006), UInt16(0x2007)])
  func catalogSelectsSideAndIgnoresTheAbsentStick(_ productID: UInt16) throws {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 0x057E, productID: productID)
    let parser = try #require(registry.parser(for: identifier) as? SwitchProParser)
    let isLeft = productID == 0x2006
    #expect(parser.layout == (isLeft ? .leftJoyCon : .rightJoyCon))
    #expect(registry.hidProfileIdentifiers().contains(identifier))
    #expect(parser.physicalInputCapabilities.rawMotion)
    #expect(parser.physicalRumbleMotors == (isLeft ? [.leftMain] : [.rightMain]))
    var report = [UInt8](repeating: 0, count: 49)
    report[0] = 0x30
    // The unused stick field remains zero; only the present stick moves right.
    let offset = isLeft ? 6 : 9
    report[offset] = 255
    report[offset + 1] = 15
    report[offset + 2] = 128
    let events = try parser.parse(data: Data(report), receivedAtNanoseconds: 100)
    let axes = events.filter {
      switch $0 {
      case .leftStickChanged, .rightStickChanged: true
      default: false
      }
    }
    #expect(axes == [isLeft ? .leftStickChanged(x: 1, y: 0) : .rightStickChanged(x: 1, y: 0)])
    #expect(events.filter { if case .motionSample = $0 { return true }; return false }.count == 3)
  }

  @Test func eachHalfIgnoresTheOtherHalfsButtonBits() throws {
    var bytes = [UInt8](repeating: 0, count: 12)
    bytes[0] = 0x30
    bytes[3] = 0xFF
    bytes[4] = 0xFF
    bytes[5] = 0xFF
    let left = try SwitchProParser(layout: .leftJoyCon).parse(data: Data(bytes))
    #expect(left.contains(.buttonPressed(.leftBumper)))
    #expect(left.contains(.buttonPressed(.back)))
    #expect(!left.contains(.buttonPressed(.rightBumper)))
    #expect(!left.contains(.buttonPressed(.start)))
    let right = try SwitchProParser(layout: .rightJoyCon).parse(data: Data(bytes))
    #expect(right.contains(.buttonPressed(.rightBumper)))
    #expect(right.contains(.buttonPressed(.start)))
    #expect(!right.contains(.buttonPressed(.leftBumper)))
    #expect(!right.contains(.buttonPressed(.back)))
  }

  @Test(arguments: [NintendoControllerLayout.leftJoyCon, .rightJoyCon])
  func joyConStartupAndRumbleOnlyAddressItsAvailableControls(_ layout: NintendoControllerLayout) {
    let parser = SwitchProParser(layout: layout)
    let startup = parser.hidStartupReports(transport: "Bluetooth")
    #expect(startup.map(\.reportID) == [1, 1, 1, 1, 1])
    #expect(startup.map { $0.bytes[10] } == [3, 0x40, 0x48, 0x10, 0x10])
    let report = parser.physicalRumbleReport(left: 255, right: 255, lt: 0, rt: 0)
    let absent = layout == .leftJoyCon ? Array(report.bytes[6..<10]) : Array(report.bytes[2..<6])
    #expect(absent == SwitchProRumbleCodec.encode(intensity: 0))
    let present = layout == .leftJoyCon ? Array(report.bytes[2..<6]) : Array(report.bytes[6..<10])
    #expect(present == SwitchProRumbleCodec.encode(intensity: 255))
  }

  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func railButtonsPreserveTheirSideAndRelease(_ layout: NintendoControllerLayout) throws {
    let parser = SwitchProParser(layout: layout)
    var bytes = [UInt8](repeating: 0, count: 12)
    bytes[0] = 0x30
    bytes[3] = 0x30
    bytes[5] = 0x30
    let expected: [Button]
    switch layout {
    case .pro: expected = []
    case .leftJoyCon: expected = [.leftSL, .leftSR]
    case .rightJoyCon: expected = [.rightSL, .rightSR]
    }
    let pressed = try parser.parse(data: Data(bytes)).compactMap { event -> Button? in
      if case .buttonPressed(let button) = event { return button }
      return nil
    }
    #expect(pressed == expected)
    #expect(try parser.parse(data: Data(bytes)).isEmpty)
    bytes[3] = 0
    bytes[5] = 0
    #expect(try parser.parse(data: Data(bytes)) == expected.map(ControllerEvent.buttonReleased))
  }

  @Test(arguments: [
    (NintendoControllerLayout.leftJoyCon, 5, UInt8(0x20), RemappingButton.leftSL),
    (NintendoControllerLayout.leftJoyCon, 5, UInt8(0x10), RemappingButton.leftSR),
    (NintendoControllerLayout.rightJoyCon, 3, UInt8(0x20), RemappingButton.rightSL),
    (NintendoControllerLayout.rightJoyCon, 3, UInt8(0x10), RemappingButton.rightSR)
  ]) func eachRailBitDrivesOnlyItsAssignedAction(
    layout: NintendoControllerLayout, offset: Int, mask: UInt8, source: RemappingButton
  ) throws {
    let parser = SwitchProParser(layout: layout)
    let identifier = DeviceIdentifier(
      vendorID: 0x057E, productID: layout == .leftJoyCon ? 0x2006 : 0x2007
    )
    let profile = RemappingProfile(
      name: "Rail mapping",
      device: RemappingDeviceScope(vendorID: identifier.vendorID, productID: identifier.productID),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: [
        RemappingBinding(source: .button(source), destination: .gamepadButton(.south))
      ]
    )
    try profile.validate()
    var bytes = [UInt8](repeating: 0, count: 12)
    bytes[0] = 0x30
    bytes[7] = 0x08
    bytes[8] = 0x80
    bytes[10] = 0x08
    bytes[11] = 0x80
    bytes[offset] = mask
    var engine = RemappingEngineState()
    #expect(engine.process(
      events: try parser.parse(data: Data(bytes)), from: identifier, profile: profile, at: 0
    ) == [.gamepad(RemappingGamepadState(buttons: [.south]), identifier)])
    bytes[offset] = 0
    #expect(engine.process(
      events: try parser.parse(data: Data(bytes)), from: identifier, profile: profile, at: 1
    ) == [.gamepad(.neutral, identifier)])
  }

  @Test func conflictingSideSelectionIsRejected() throws {
    let record: [String: Any] = [
      "$schema": ControllerRecordDocument.schemaID,
      "vendor_id": 1406,
      "product_id": 8198,
      "transport": "hid",
      "protocol": [
        "driver": "SwitchPro", "variant": "switchPro", "quirks": ["joyConLeft", "joyConRight"]
      ]
    ]
    let encoded = try JSONSerialization.data(withJSONObject: record)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ControllerRecordDocument.self, from: encoded)
    }
  }

}
