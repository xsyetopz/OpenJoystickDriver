import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ProtocolParametersTests {
  /// A family, the JSON of its parameters, and the typed value that JSON decodes to.
  private struct ParameterCase: Sendable {
    let family: PhysicalProtocolID
    let json: String
    let parameters: ProtocolParameters
    let entry: String
  }

  private static let cases: [ParameterCase] = [
    ParameterCase(
      family: .xboxGIP,
      json: #"{"shareButton":{"fromEnd":26}}"#,
      parameters: ProtocolParameters(shareButton: .init(fromEnd: 26)),
      entry: "shareButton.fromEnd=26"
    ),
    ParameterCase(
      family: .nintendoSwitch1,
      json: #"{"layout":"JoyConLeft"}"#,
      parameters: ProtocolParameters(layout: .joyConLeft),
      entry: "layout=JoyConLeft"
    ),
    ParameterCase(
      family: .nintendoSwitch2,
      json: #"{"layout":"JoyConRight"}"#,
      parameters: ProtocolParameters(layout: .joyConRight),
      entry: "layout=JoyConRight"
    ),
    ParameterCase(
      family: .nintendoSwitch2,
      json: #"{"layout":"GameCube"}"#,
      parameters: ProtocolParameters(layout: .gameCube),
      entry: "layout=GameCube"
    ),
    ParameterCase(
      family: .nintendoSwitch1,
      json: #"{"usbProtocol":"ChargingOnly"}"#,
      parameters: ProtocolParameters(usbProtocol: .chargingOnly),
      entry: "usbProtocol=ChargingOnly"
    ),
    ParameterCase(
      family: .vendorGameSir,
      json: #"{"innerGrips":true}"#,
      parameters: ProtocolParameters(innerGrips: true),
      entry: "innerGrips=true"
    ),
    ParameterCase(
      family: .vendorGameSir,
      json: #"{"lightingMemory":"ProfileSlots"}"#,
      parameters: ProtocolParameters(lightingMemory: .profileSlots),
      entry: "lightingMemory=ProfileSlots"
    ),
    ParameterCase(
      family: .vendorPS3ThirdParty,
      json: #"{"hatSource":"DpadPressure"}"#,
      parameters: ProtocolParameters(hatSource: .dpadPressure),
      entry: "hatSource=DpadPressure"
    ),
    ParameterCase(
      family: .sonyDualShock4,
      json: #"{"motionCalibration":"Factory"}"#,
      parameters: ProtocolParameters(motionCalibration: .factory),
      entry: "motionCalibration=Factory"
    ),
    ParameterCase(
      family: .sonyDualShock4,
      json: #"{"role":"WirelessAdapter"}"#,
      parameters: ProtocolParameters(role: .wirelessAdapter),
      entry: "role=WirelessAdapter"
    ),
    ParameterCase(
      family: .sonyDualShock4,
      json: #"{"motionScale":"StrikePad"}"#,
      parameters: ProtocolParameters(motionScale: .strikePad),
      entry: "motionScale=StrikePad"
    ),
    ParameterCase(
      family: .vendorNVIDIAShield,
      json: #"{"reportRevision":"Shield2015"}"#,
      parameters: ProtocolParameters(reportRevision: .shield2015),
      entry: "reportRevision=Shield2015"
    ),
    ParameterCase(
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty"}"#,
      parameters: ProtocolParameters(maker: .thirdParty),
      entry: "maker=ThirdParty"
    ),
    ParameterCase(
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","unprobedSensors":true}"#,
      parameters: ProtocolParameters(maker: .thirdParty, unprobedSensors: true),
      entry: "unprobedSensors=true"
    ),
    ParameterCase(
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","unprobedTouchpad":true}"#,
      parameters: ProtocolParameters(maker: .thirdParty, unprobedTouchpad: true),
      entry: "unprobedTouchpad=true"
    ),
    ParameterCase(
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","forcedVibration":true}"#,
      parameters: ProtocolParameters(maker: .thirdParty, forcedVibration: true),
      entry: "forcedVibration=true"
    ),
    ParameterCase(
      family: .sonyDualSense,
      json: #"{"maker":"ThirdParty","role":"Receiver"}"#,
      parameters: ProtocolParameters(role: .receiver, maker: .thirdParty),
      entry: "role=Receiver"
    ),
  ]

  private func decode(_ json: String) throws -> ProtocolParameters {
    try JSONDecoder().decode(ProtocolParameters.self, from: Data(json.utf8))
  }

  @Test
  func decodingEveryCaseYieldsItsTypedParameters() throws {
    for row in Self.cases {
      let decoded = try decode(row.json)
      #expect(decoded == row.parameters, "\(row.entry)")
      #expect(decoded.entries.contains(row.entry), "\(row.entry)")
      #expect(decoded.violation(family: row.family, variant: nil) == nil, "\(row.entry)")
    }
  }

  @Test
  func encodingRoundTripsEveryParameter() throws {
    for row in Self.cases {
      let data = try JSONEncoder().encode(row.parameters)
      #expect(try JSONDecoder().decode(ProtocolParameters.self, from: data) == row.parameters)
    }
  }

  @Test(
    arguments: [
      #"{"notAParameter":true}"#, #"{"layout":"notALayout"}"#, #"{"layout":["JoyConLeft"]}"#,
      #"{"innerGrips":"yes"}"#, #"{"innerGrips":false}"#,
      #"{"shareButton":26}"#, #"{"shareButton":{"fromEnd":0}}"#,
      #"{"shareButton":{"fromEnd":26,"extra":1}}"#, #"{"maker":"notAMaker"}"#, #"{}"#,
    ]
  )
  func rejectsUnknownEmptyAndMistypedParameters(json: String) {
    #expect(throws: DecodingError.self) { try decode(json) }
  }

  @Test
  func rejectsParameterItsFamilyDoesNotDeclare() throws {
    let wrongFamily = try decode(#"{"layout":"JoyConLeft"}"#)
    for family in PhysicalProtocolID.allCases
    where family != .nintendoSwitch1 && family != .nintendoSwitch2 {
      #expect(wrongFamily.violation(family: family, variant: nil) != nil, "\(family)")
    }
    #expect(ProtocolParameters.none.violation(family: .xboxXUSB, variant: .wired) == nil)
  }
}
