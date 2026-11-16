import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A value in a spelling the naming rule rejects is an unknown name, like a random word.
struct RecordValueSpellingTests {
  @Test(arguments: ["xbox.gip", "hid.descriptor", "vendor.ps3-third-party", "banana"])
  func familyInEarlierSpellingIsUnknown(name: String) {
    #expect(PhysicalProtocolID(rawValue: name) == nil)
    #expect(ProtocolBindingID(rawValue: name) == nil)
  }

  @Test(arguments: ["usb", "bluetooth-le", "bluetooth-classic", "enhanced-hid", "wired", "banana"])
  func variantInEarlierSpellingIsUnknown(name: String) {
    #expect(PhysicalProtocolVariantID(rawValue: name) == nil)
    #expect(PhysicalTransport(rawValue: name) == nil)
  }

  @Test(arguments: ["north", "northEast", "neutral", "banana"])
  func hatDirectionInEarlierSpellingIsUnknown(name: String) {
    #expect(HatDirection(rawValue: name) == nil)
  }

  @Test(arguments: ["ojd", "system", "banana"])
  func serverInEarlierSpellingIsUnknown(name: String) {
    #expect(ControllerServer(rawValue: name) == nil)
  }

  @Test
  func protocolDescriptionFilesAreKebabCaseFamily() {
    #expect(PhysicalProtocolID.xboxGIP.descriptionFileStem == "xbox-gip")
    #expect(PhysicalProtocolID.hidDescriptor.descriptionFileStem == "hid-descriptor")
    #expect(PhysicalProtocolID.vendorPS3ThirdParty.descriptionFileStem == "vendor-ps3-third-party")
    #expect(PhysicalProtocolID.sonyDualShock4.descriptionFileStem == "sony-dual-shock4")
    #expect(PhysicalProtocolID.vendorGameSir.descriptionFileStem == "vendor-game-sir")
    for family in PhysicalProtocolID.allCases {
      #expect(ProtocolDescription.bundled[family] != nil)
      #expect(family.descriptionFileStem == CommandLineName.kebab(family.rawValue))
    }
  }

  @Test
  func brandNamesSplitAtEveryCaseBoundary() {
    #expect(CommandLineName.kebab("SonyDualShock4") == "sony-dual-shock4")
    #expect(CommandLineName.kebab("SonyDualSense") == "sony-dual-sense")
    #expect(CommandLineName.kebab("VendorGameSir") == "vendor-game-sir")
    #expect(CommandLineName.kebab("VendorNVIDIAShield") == "vendor-nvidia-shield")
    #expect(CommandLineName.value(of: "sony-dualshock4", in: PhysicalProtocolID.self) == nil)
    #expect(
      CommandLineName.value(of: "sony-dual-shock4", in: PhysicalProtocolID.self)
        == .sonyDualShock4
    )
    #expect(CommandLineName.collisions(in: PhysicalProtocolID.self).isEmpty)
  }

  // MARK: - Records

  /// A record template with one `VALUE` slot: it decodes with the current spelling and fails with
  /// an earlier spelling or a random word.
  struct RecordCase: Sendable, CustomTestStringConvertible {
    let name: String
    let fields: String
    let current: String
    let rejected: [String]
    var testDescription: String { name }
  }

  private static let ps3 = #"{"family": "VendorPS3ThirdParty"}"#
  private static let hidWrite =
    #"{"report": {"kind": "Output", "id": 1, "length": 8}, "bytes": "01 02 03 04 05 06 07""#
  private static let sixaxis = #"{"family": "SonySixaxis"}"#

  private static func modes(_ protocolInfo: String, session: String = "") -> String {
    #""modes": [{"id": "default", "protocol": \#(protocolInfo)\#(session)}]"#
  }

  private static let recordCases: [RecordCase] = [
    RecordCase(
      name: "rumble report kind",
      fields: modes(
        ps3,
        session: #", "session": {"rumble": {"report": {"kind": "VALUE", "id": 2, "length": 8}, "#
          + #""lowFrequency": {"byte": 3}}}"#
      ),
      current: "Output",
      rejected: ["output", "banana"]
    ),
    RecordCase(
      name: "rumble motor key",
      fields: modes(
        ps3,
        session: #", "session": {"rumble": {"report": {"kind": "Output", "id": 2, "length": 8}, "#
          + #""VALUE": {"byte": 3}}}"#
      ),
      current: "lowFrequency",
      rejected: ["leftMain", "rightMain", "banana"]
    ),
    RecordCase(
      name: "raw-USB rumble report kind",
      fields: modes(
        #"{"family": "XboxXUSB", "variant": "Wired"}"#,
        session: #", "session": {"rumble": {"report": {"kind": "VALUE", "length": 8}, "#
          + #""lowFrequency": {"byte": 3}}}"#
      ),
      current: "USB",
      rejected: ["usb", "banana"]
    ),
    RecordCase(
      name: "startup phase",
      fields: modes(
        sixaxis,
        session: #", "session": {"startup": [\#(hidWrite), "phase": "VALUE"}]}"#
      ),
      current: "Startup",
      rejected: ["startup", "activation", "banana"]
    ),
    RecordCase(
      name: "startup transport",
      fields: modes(
        sixaxis,
        session: #", "session": {"startup": [\#(hidWrite), "transport": "VALUE"}]}"#
      ),
      current: "BluetoothClassic",
      rejected: ["bluetooth-classic", "banana"]
    ),
    RecordCase(
      name: "capabilities rumble",
      fields: modes(#"{"family": "XboxGIP"}"#) + #", "capabilities": {"rumble": "VALUE"}"#,
      current: "Absent",
      rejected: ["absent", "banana"]
    ),
    RecordCase(
      name: "mode link",
      fields: #""modes": [{"id": "default", "protocol": \#(sixaxis)}, "#
        + #"{"id": "wireless", "protocol": \#(sixaxis), "match": {"link": "VALUE"}}]"#,
      current: "BluetoothClassic",
      rejected: ["bluetooth-classic", "banana"]
    ),
    RecordCase(
      name: "probe expectation",
      fields: #""modes": [{"id": "default", "protocol": \#(sixaxis)}, "#
        + #"{"id": "probed", "protocol": \#(sixaxis), "match": {"probes": "#
        + #"[{"report": 239, "length": 49, "expect": "VALUE"}]}}]"#,
      current: "Answers",
      rejected: ["answers", "banana"]
    ),
    RecordCase(
      name: "hat encoding",
      fields: modes(#"{"family": "HIDReportLayout"}"#)
        + #", "input": {"layouts": [{"report": {"length": {"atLeast": 4}}, "#
        + #""buttons": [{"control": "South", "bitOffset": 0, "bitSize": 1}], "#
        + #""hat": [{"encoding": "VALUE", "bitOffset": 8, "bitSize": 4}]}]}"#,
      current: "EightWay",
      rejected: ["8-way", "banana"]
    ),
    RecordCase(
      name: "server",
      fields: modes(sixaxis) + #", "server": "VALUE""#,
      current: "OJD",
      rejected: ["ojd", "system", "banana"]
    ),
    RecordCase(
      name: "variant",
      fields: modes(#"{"family": "XboxXUSB", "variant": "VALUE"}"#),
      current: "Wired",
      rejected: ["wired", "banana"]
    ),
    RecordCase(
      name: "family",
      fields: modes(#"{"family": "VALUE"}"#),
      current: "XboxGIP",
      rejected: ["xbox.gip", "hid.descriptor", "banana"]
    ),
    RecordCase(
      name: "initialization packet id",
      fields: modes(#"{"family": "XboxGIP", "initialization": ["VALUE/power-on"]}"#),
      current: "XboxGIP",
      rejected: ["xbox.gip", "banana"]
    ),
    RecordCase(
      name: "USB configuration",
      fields: modes(#"{"family": "XboxGIP"}"#) + #", "usb": {"configuration": "VALUE"}"#,
      current: "SetConfiguration1BeforeClaim",
      rejected: ["set1-before-claim", "banana"]
    ),
    RecordCase(
      name: "endpoint direction",
      fields: endpointModes(#""direction": "VALUE""#),
      current: "In",
      rejected: ["in", "out", "banana"]
    ),
    RecordCase(
      name: "endpoint transfer type",
      fields: endpointModes(#""transferType": "VALUE""#),
      current: "Interrupt",
      rejected: ["interrupt", "banana"]
    ),
  ]

  private static func endpointModes(_ endpoint: String) -> String {
    #""modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}, "#
      + #"{"id": "alternative", "protocol": {"family": "XboxGIP"}, "match": "#
      + #"{"interfaceSignature": {"interfaceClass": 255, "interfaceSubclass": 71, "#
      + #""interfaceProtocol": 208, "endpoints": [{\#(endpoint)}]}}}]"#
  }

  private static func problem(_ fields: String) -> ErrorCode? {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
      "vendorID": 4660, "productID": 22136, \(fields)}
      """
    do {
      _ = try ControllerRecordSet.validate(PropertyListFixture.data(json: json))
      return nil
    } catch { return ControllerRecordSet.problemCode(error) }
  }

  @Test(arguments: recordCases)
  func recordValueInEarlierSpellingIsUnknown(_ spelling: RecordCase) {
    #expect(
      Self.problem(spelling.fields.replacingOccurrences(of: "VALUE", with: spelling.current))
        == nil
    )
    for name in spelling.rejected {
      #expect(
        Self.problem(spelling.fields.replacingOccurrences(of: "VALUE", with: name))
          == .invalidControllerRecord,
        "\(name) is unknown"
      )
    }
  }

  // MARK: - Protocol descriptions

  struct DescriptionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let family: PhysicalProtocolID
    let body: String
    let current: String
    let rejected: [String]
    var code: ErrorCode = .invalidProtocolDescription
    var testDescription: String { name }
  }

  private static let descriptionCases: [DescriptionCase] = [
    DescriptionCase(
      name: "parameter type",
      family: .sonyDualSense,
      body: #""parameters": {"maker": {"type": "VALUE", "values": ["ThirdParty"]}}"#,
      current: "Enum",
      rejected: ["enum", "banana"]
    ),
    DescriptionCase(
      name: "integer field type",
      family: .xboxGIP,
      body: #""parameters": {"shareButton": {"type": "Object", "fields": "#
        + #"{"fromEnd": {"type": "VALUE", "minimum": 1, "maximum": 255}}}}"#,
      current: "Integer",
      rejected: ["integer", "banana"]
    ),
    DescriptionCase(
      name: "controls base",
      family: .xboxXID,
      body: #""controls": {"base": "VALUE"}"#,
      current: "Xbox",
      rejected: ["xbox", "banana"]
    ),
    DescriptionCase(
      name: "SPI read purpose",
      family: .nintendoSwitch1,
      body: #""defaults": {"session": {"subcommands": {"reportID": 1, "counterModulus": 16, "#
        + #""requests": [{"subcommand": 16, "spiRead": {"address": 0, "length": 1, "#
        + #""purpose": "VALUE"}}], "playerIndicator": {"subcommand": 48, "patterns": "#
        + #"{"off": 0, "player1": 1, "player2": 3, "player3": 7, "player4": 15}}}}}"#,
      current: "UserMotionCalibration",
      rejected: ["userMotionCalibration", "banana"]
    ),
    DescriptionCase(
      name: "startup phase",
      family: .sonyDualShock4,
      body: #""defaults": {"session": {"startup": [{"report": {"kind": "Output", "id": 1, "#
        + #""length": 4}, "bytes": "01 02 03", "phase": "VALUE"}]}}"#,
      current: "Startup",
      rejected: ["startup", "banana"]
    ),
    DescriptionCase(
      name: "variant key",
      family: .sonyDualSense,
      body: #""defaults": {"variants": {"VALUE": {"tuning": {"stickDeadzone": 0.1}}}}"#,
      current: "USB",
      rejected: ["usb", "banana"],
      code: .unknownProtocolVariant
    ),
  ]

  @Test(arguments: descriptionCases)
  func descriptionValueInEarlierSpellingIsUnknown(_ spelling: DescriptionCase) {
    func code(_ value: String) -> ErrorCode? {
      let body = spelling.body.replacingOccurrences(of: "VALUE", with: value)
      do {
        _ = try ProtocolDescriptionFixture.decode(family: spelling.family, body)
        return nil
      } catch { return error.code }
    }
    #expect(code(spelling.current) == nil, "the current spelling decodes")
    for name in spelling.rejected { #expect(code(name) == spelling.code, "\(name) is unknown") }
  }
}
