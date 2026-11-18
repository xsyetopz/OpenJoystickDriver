import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ModeAndSessionRuleMessageTests {
  private static func message(_ key: String, _ arguments: [String] = []) -> String {
    ControllerRecordSet.problemDescription(
      ControllerRecordProblem(
        code: .invalidControllerRecord,
        key: "error.E5007.\(key)",
        arguments: arguments,
        "unused"
      ),
      document: "record",
      localization: Localization(preferredLanguages: ["en-US"]),
      file: "046d-c21d.plist"
    )
  }

  @Test
  func sessionRulesNameFileKeyPathRuleAndFix() {
    #expect(
      Self.message("session.hidStartup")
        == "046d-c21d.plist, session.startup: HID startup writes apply "
        + "only to HID controllers, so not to a raw-USB mode or family. "
        + "Fix: Remove the HID startup writes, or use raw-USB packets."
    )
    #expect(
      Self.message("session.keepAliveFamily", ["A"])
        == "046d-c21d.plist, session.keepAlive: A session keepAlive needs "
        + "a raw-USB family whose description declares none, and A "
        + "declares one. Fix: Remove the session keepAlive, because A "
        + "already runs its own."
    )
    #expect(
      Self.message("session.rawUSBOnly", ["A"])
        == "046d-c21d.plist, session.A: Session A applies only to raw-USB "
        + "modes. Fix: Remove A from the session, or use a raw-USB "
        + "protocol."
    )
    #expect(
      Self.message("session.usbStartup")
        == "046d-c21d.plist, session.startup: Raw-USB startup writes need "
        + "a family that reads them and a mode with no initialization "
        + "list. Fix: Remove the raw-USB startup writes, or use a family "
        + "that reads them and drop the initialization list."
    )
  }

  @Test
  func rumbleRulesNameFileKeyPathRuleAndFix() {
    #expect(
      Self.message("rumble.templateKind")
        == "046d-c21d.plist, session.rumble: A rumble template is a usb "
        + "packet for a raw-USB protocol and a HID report for a HID "
        + "protocol. Fix: Write the template as the kind of packet that "
        + "the protocol uses."
    )
    #expect(
      Self.message("rumble.templateDriver")
        == "046d-c21d.plist, session.rumble: Rumble templates need a "
        + "driver that encodes them. Fix: Remove the rumble template, or "
        + "use a family whose driver encodes it."
    )
    #expect(
      Self.message("rumble.resendWithKeepAlive")
        == "046d-c21d.plist, session.rumble.resendIntervalMilliseconds: A "
        + "rumble resendIntervalMilliseconds cannot be combined with a "
        + "session keepAlive. Fix: Remove resendIntervalMilliseconds, or "
        + "remove the session keepAlive."
    )
    #expect(
      Self.message("rumble.resendWithFamilyKeepAlive")
        == "046d-c21d.plist, session.rumble.resendIntervalMilliseconds: A "
        + "rumble resendIntervalMilliseconds needs a family whose "
        + "description declares no keepAlive. Fix: Remove "
        + "resendIntervalMilliseconds, because the keep-alive of the "
        + "family sets the timing."
    )
  }

  @Test
  func modesRulesNameFileKeyPathRuleAndFix() {
    #expect(
      Self.message("modes.empty")
        == "046d-c21d.plist, modes: Modes must hold at least one mode. "
        + "Fix: Add a mode."
    )
    #expect(
      Self.message("modes.defaultCount")
        == "046d-c21d.plist, modes: At most one mode has the id default. "
        + "Fix: Give the id default to one mode only."
    )
    #expect(
      Self.message("modes.uniqueIDs")
        == "046d-c21d.plist, modes: Each mode id must be unique. Fix: "
        + "Rename the modes that repeat an id."
    )
    #expect(
      Self.message("modes.interfaceRawUSB")
        == "046d-c21d.plist, modes[].interface: A raw-USB mode has no "
        + "interface, because it claims the interface that its usb "
        + "transport resolves. Fix: Remove interface from the mode."
    )
    #expect(
      Self.message("modes.endpointsHID")
        == "046d-c21d.plist, modes[].match.interfaceSignature.endpoints: "
        + "A HID mode's interfaceSignature has no endpoints, because "
        + "only the raw-USB scanner reads an endpoint set. Fix: Remove "
        + "endpoints from the interfaceSignature."
    )
    #expect(
      Self.message("modes.inputLayoutNeeded")
        == "046d-c21d.plist, input: A HIDReportLayout mode needs the "
        + "input layouts of the record. Fix: Add input with the layouts, "
        + "or use another protocol."
    )
    #expect(
      Self.message("modes.usageMapDriver")
        == "046d-c21d.plist, input.usageMap: A HID usage map applies only "
        + "if the driver of every mode reads one. Fix: Remove the usage "
        + "map, or use only drivers that read one."
    )
    #expect(
      Self.message("modes.capabilities")
        == "046d-c21d.plist, capabilities: Capabilities must be deltas "
        + "that the driver of some mode declares. Fix: Keep only "
        + "capabilities that the driver of a mode declares."
    )
  }

  @Test
  func tuningRulesNameFileKeyPathRuleAndFix() {
    #expect(
      Self.message("tuning.keyNotRead", ["A", "B"])
        == "046d-c21d.plist, tuning.A: A is not read by the B driver. "
        + "Fix: Remove A from tuning, or use a driver that reads it."
    )
  }

  @Test
  func protocolDescriptionRulesNameFileKeyPathRuleAndFix() {
    #expect(
      Self.message("protocolDescription.inputLayout")
        == "046d-c21d.plist, defaults.input: An input layout applies only "
        + "to a family that reads one. Fix: Remove the input layout from "
        + "the defaults."
    )
    #expect(
      Self.message("protocolDescription.usageMap")
        == "046d-c21d.plist, defaults.input.usageMap: A HID usage map "
        + "applies only to a family that reads one. Fix: Remove the "
        + "usage map from the defaults."
    )
    #expect(
      Self.message("protocolDescription.receiverPowerOff")
        == "046d-c21d.plist, defaults.receiverPowerOff: The "
        + "receiverPowerOff default applies only to XboxXUSB. Fix: "
        + "Remove receiverPowerOff from the defaults."
    )
    #expect(
      Self.message("protocolDescription.sessionKeysNone", ["A"])
        == "046d-c21d.plist, sessionKeys: A reads no session keys. Fix: "
        + "Leave sessionKeys empty."
    )
    #expect(
      Self.message("protocolDescription.sessionKeysRead", ["A", "B"])
        == "046d-c21d.plist, sessionKeys: A reads the session keys B. "
        + "Fix: Set sessionKeys to B."
    )
    #expect(
      Self.message("protocolDescription.sessionKeyUnlisted", ["A"])
        == "046d-c21d.plist, defaults.session: The defaults set the "
        + "session key A, which sessionKeys does not list. Fix: Add A to "
        + "sessionKeys, or remove it from the defaults."
    )
    #expect(
      Self.message("protocolDescription.keepAliveHID")
        == "046d-c21d.plist, defaults.session.keepAlive.writes: A HID "
        + "keep-alive write applies only to HID controllers. Fix: Remove "
        + "the HID write, or use a raw-USB write."
    )
    #expect(
      Self.message("protocolDescription.keepAliveUSB")
        == "046d-c21d.plist, defaults.session.keepAlive.writes: A raw-USB "
        + "keep-alive write applies only to a family with a raw-USB "
        + "variant. Fix: Remove the raw-USB write, or use a HID write."
    )
    #expect(
      Self.message("protocolDescription.keepAliveResendTuning", ["A"])
        == "046d-c21d.plist, "
        + "defaults.session.keepAlive.writes[].resendTuning: The "
        + "resendTuning of a keep-alive write names A, which the family "
        + "must read and give a default. Fix: Name a tuning key that the "
        + "family reads and defaults, or remove resendTuning."
    )
    #expect(
      Self.message("protocolDescription.activationTransport")
        == "046d-c21d.plist, activation: Activation and deactivation name "
        + "only a transport that writeTransports lists. Fix: Name a "
        + "transport from writeTransports, or add it there."
    )
    #expect(
      Self.message("protocolDescription.sessionMissing", ["A", "B"])
        == "046d-c21d.plist, defaults.session: A must set the session "
        + "fields B. Fix: Set B in the defaults."
    )
    #expect(
      Self.message("protocolDescription.sessionUnread", ["A", "B"])
        == "046d-c21d.plist, defaults.session: A does not read the "
        + "session fields B. Fix: Remove B from the defaults."
    )
    #expect(
      Self.message("protocolDescription.namedPacketPrefix", ["A"])
        == "046d-c21d.plist, namedPackets: Each named packet id starts "
        + "with A/. Fix: Rename the packets so that each id starts with "
        + "A/."
    )
    #expect(
      Self.message("protocolDescription.tuningRawUSB")
        == "046d-c21d.plist, tuningKeys: A family that is always raw USB "
        + "reads its tuning through rawUSBTuningKeys. Fix: Move the keys "
        + "from tuningKeys to rawUSBTuningKeys."
    )
    #expect(
      Self.message("protocolDescription.rawUSBTuningKeys")
        == "046d-c21d.plist, rawUSBTuningKeys: The rawUSBTuningKeys apply "
        + "only to a family with a raw-USB variant. Fix: Remove "
        + "rawUSBTuningKeys, or add a raw-USB variant."
    )
  }

  @Test
  func recordRulesNameFileKeyPathRuleAndFix() {
    #expect(
      Self.message("record.hexBytes", ["A", "B"])
        == "046d-c21d.plist, A: The B bytes must be uppercase hex pairs "
        + "separated by single spaces. Fix: Write A as pairs such as 42 "
        + "03 00, with uppercase digits and one space between pairs."
    )
  }

  @Test
  func hexBytesNamesFieldAndWhatBytesBelongTo() throws {
    struct Carrier: Decodable {
      let bytes: [UInt8]
      init(from decoder: any Decoder) throws {
        bytes = try HexBytes.decode(
          try decoder.container(keyedBy: DocumentKey.self),
          for: "data",
          what: "control transfer"
        )
      }
    }
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["data": "42 3"],
      format: .xml,
      options: 0
    )
    let thrown = #expect(throws: ControllerRecordProblem.self) {
      try PropertyListDecoder().decode(Carrier.self, from: data)
    }
    let problem = try #require(thrown)
    let error = DecodingError.dataCorrupted(problem.context(at: [DocumentKey("data")]))
    #expect(
      ControllerRecordSet.problemDescription(
        error,
        includingCode: false,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "046d-c21d.plist"
      )
        == "046d-c21d.plist, data: The control transfer bytes must be uppercase hex pairs "
        + "separated by single spaces. Fix: Write data as pairs such as 42 03 00, with "
        + "uppercase digits and one space between pairs."
    )
  }
}
