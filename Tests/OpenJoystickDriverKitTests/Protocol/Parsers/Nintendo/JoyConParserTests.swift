import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct JoyConParserTests {
  @Test(arguments: [UInt16(0x2006), UInt16(0x2007)])
  func catalogSelectsSideAndIgnoresAbsentStick(_ productID: UInt16) throws {
    let registry = ProtocolDriverRegistry()
    let model = ControllerModelID(vendorID: 0x057E, productID: productID)
    let parser = try #require(try catalogParser(model, registry: registry) as? Switch1Driver)
    let isLeft = productID == 0x2006
    #expect(parser.layout == (isLeft ? .leftJoyCon : .rightJoyCon))
    #expect(registry.hidModels.contains(model))
    #expect(parser.capabilities.motion)
    #expect(parser.outputCapabilities.rumbleMotors == (isLeft ? [.lowFrequency] : [.highFrequency]))
    var report = [UInt8](repeating: 0, count: 49)
    report[0] = 0x30
    // The unused stick field remains zero; only the present stick moves right.
    let offset = isLeft ? 6 : 9
    report[offset] = 255
    report[offset + 1] = 15
    report[offset + 2] = 128
    let events = try parser.parseReport(Data(report), at: 100)
    #expect(events.contains(isLeft ? .leftStick(x: 1, y: 0) : .rightStick(x: 1, y: 0)))
    #expect(events?.state.leftStick == (isLeft ? events?.state.leftStick : .center))
    #expect(events?.state.rightStick == (isLeft ? .center : events?.state.rightStick))
    #expect(events?.motion.count == 3)
  }

  @Test
  func eachHalfIgnoresOtherHalfsButtonBits() throws {
    var bytes = [UInt8](repeating: 0, count: 12)
    bytes[0] = 0x30
    bytes[3] = 0xFF
    bytes[4] = 0xFF
    bytes[5] = 0xFF
    let left = try Switch1Driver(layout: .leftJoyCon).parseReport(Data(bytes))
    #expect(left.contains(.press(.leftShoulder)))
    #expect(left.contains(.press(.back)))
    #expect(!left.contains(.press(.rightShoulder)))
    #expect(!left.contains(.press(.start)))
    let right = try Switch1Driver(layout: .rightJoyCon).parseReport(Data(bytes))
    #expect(right.contains(.press(.rightShoulder)))
    #expect(right.contains(.press(.start)))
    #expect(!right.contains(.press(.leftShoulder)))
    #expect(!right.contains(.press(.back)))
  }

  @Test(arguments: [NintendoControllerLayout.leftJoyCon, .rightJoyCon])
  func joyConStartupAndRumbleOnlyAddressItsAvailableControls(_ layout: NintendoControllerLayout) {
    let parser = Switch1Driver(layout: layout, isBluetooth: true)
    let startup = parser.startupWrites().hidOutputs
    #expect(startup.map(\.reportID) == [1, 1, 1, 1, 1])
    #expect(startup.map { $0.bytes[10] } == [3, 0x40, 0x48, 0x10, 0x10])
    let report = parser.rumblePlan(left: 255, right: 255, lt: 0, rt: 0).onlyReport
    let absent = layout == .leftJoyCon ? Array(report.bytes[6..<10]) : Array(report.bytes[2..<6])
    #expect(absent == SwitchProRumbleCodec.encode(intensity: 0))
    let present = layout == .leftJoyCon ? Array(report.bytes[2..<6]) : Array(report.bytes[6..<10])
    #expect(present == SwitchProRumbleCodec.encode(intensity: 255))
  }

  @Test(arguments: [NintendoControllerLayout.pro, .leftJoyCon, .rightJoyCon])
  func railButtonsPreserveTheirSideAndRelease(_ layout: NintendoControllerLayout) throws {
    let parser = Switch1Driver(layout: layout)
    var bytes = [UInt8](repeating: 0, count: 12)
    bytes[0] = 0x30
    bytes[3] = 0x30
    bytes[5] = 0x30
    let expected: Set<Control>
    switch layout {
    case .pro: expected = []
    case .leftJoyCon: expected = [.auxiliary3, .auxiliary4]
    case .rightJoyCon: expected = [.auxiliary5, .auxiliary6]
    }
    let pressed = try parser.parseReport(Data(bytes))?.state.pressed ?? []
    #expect(pressed.intersection([.auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6]) == expected)
    bytes[3] = 0
    bytes[5] = 0
    #expect(try parser.parseReport(Data(bytes))?.state.pressed.isDisjoint(with: expected) == true)
  }

  @Test(arguments: [
    (NintendoControllerLayout.leftJoyCon, 5, UInt8(0x20), Control.auxiliary3),
    (NintendoControllerLayout.leftJoyCon, 5, UInt8(0x10), Control.auxiliary4),
    (NintendoControllerLayout.rightJoyCon, 3, UInt8(0x20), Control.auxiliary5),
    (NintendoControllerLayout.rightJoyCon, 3, UInt8(0x10), Control.auxiliary6),
  ])
  func eachRailBitDrivesOnlyItsAssignedAction(
    layout: NintendoControllerLayout,
    offset: Int,
    mask: UInt8,
    source: Control
  ) throws {
    let parser = Switch1Driver(layout: layout)
    let identifier = LogicalControllerID(
      vendorID: 0x057E,
      productID: layout == .leftJoyCon ? 0x2006 : 0x2007
    )
    let profile = RemappingProfile(
      name: "Rail mapping",
      device: RemappingDeviceScope(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID
      ),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough),
      bindings: [RemappingBinding(source: .button(source), destination: .gamepadButton(.south))]
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
    #expect(
      engine.process(
        parsed: try parser.parseReport(Data(bytes)),
        from: identifier,
        profile: profile,
        at: 0
      ) == [.gamepad(RemappingGamepadState(buttons: [.south]), identifier)]
    )
    bytes[offset] = 0
    #expect(
      engine.process(
        parsed: try parser.parseReport(Data(bytes)),
        from: identifier,
        profile: profile,
        at: 1
      ) == [.gamepad(.neutral, identifier)]
    )
  }

  @Test
  func conflictingSideSelectionIsRejected() throws {
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 1406, "productID": 8198,
      "modes": [
        [
          "id": "default",
          "protocol": [
            "family": "NintendoSwitch1", "parameters": ["layout": ["JoyConLeft", "JoyConRight"]],
          ],
        ]
      ],
    ]
    let encoded = try JSONSerialization.data(withJSONObject: record)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(ControllerRecordDocument.self, from: encoded)
    }
  }

}
