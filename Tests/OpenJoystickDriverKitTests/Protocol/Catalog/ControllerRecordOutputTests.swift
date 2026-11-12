import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record's `server` field, the rumble template a mode's `session` decodes into, and the
/// writes OJD keeps for a controller macOS serves.
struct ControllerRecordOutputTests {
  private static let thirdParty = thirdPartyModes(session: nil)

  /// The `modes` field of a PS3 third-party record whose default mode runs `session`.
  private static func thirdPartyModes(session: String?) -> String {
    let session = session.map { ", \"session\": \($0)" } ?? ""
    return """
      "modes": [{"id": "default", "protocol": {"family": "VendorPS3ThirdParty"}\(session)}]
      """
  }
  private static let gp100Rumble = #"""
    "rumble": {"report": {"kind": "Output", "id": 2, "length": 8},
      "lowFrequency": {"byte": 3}, "highFrequency": {"byte": 2}}
    """#

  @Test
  func decodesOwnershipAndARumbleTemplate() throws {
    let document = try decode(
      "\(Self.thirdPartyModes(session: "{\(Self.gp100Rumble)}")), \"server\": \"OJD\""
    )
    #expect(document.server == .ojd)
    let template = try #require(document.baseMode.session.rumbleTemplate)
    #expect(template.report == ControllerTemplateReport(kind: .output, reportID: 2, length: 8))
    #expect(template.motors == [.lowFrequency: .init(byte: 3), .highFrequency: .init(byte: 2)])
    #expect(template.bytes == [2, 0, 0, 0, 0, 0, 0, 0])
    #expect(template.counterByte == nil && template.resendIntervalMilliseconds == nil)
    #expect(template.outputCapabilities == .dualMainRumble)
    #expect(try decode(Self.thirdParty).server == nil)
    let sixaxis = try decode(
      #""modes": [{"id": "default", "protocol": {"family": "SonySixaxis"}}], "server": "System""#
    )
    #expect(sixaxis.server == .system)
  }

  @Test
  func aHIDDescriptorModeDecodesAHIDRumbleTemplate() throws {
    let document = try decode(
      "\"modes\": [{\"id\": \"default\", \"protocol\": {\"family\": \"HIDDescriptor\"}, "
        + "\"session\": {\(Self.gp100Rumble)}}]"
    )
    let template = try #require(document.baseMode.session.rumbleTemplate)
    #expect(template.report == ControllerTemplateReport(kind: .output, reportID: 2, length: 8))
    #expect(template.outputCapabilities == .dualMainRumble)
  }

  @Test(arguments: ["ojd", "system", "native", ""])
  func rejectsUnknownOwnership(name: String) {
    #expect(throws: DecodingError.self) {
      try decode("\(Self.thirdParty), \"server\": \"\(name)\"")
    }
  }

  /// macOS cannot serve a raw-USB family, so the record has no ownership to choose.
  @Test(
    arguments: [
      #"{"family": "XboxGIP"}"#, #"{"family": "XboxXUSB", "variant": "Wired"}"#,
      #"{"family": "VendorGameSir", "variant": "USB"}"#,
    ]
  )
  func rejectsOwnershipOnRawUSBFamilies(protocolInfo: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo)}], \"server\": \"OJD\""
      )
    }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter { !$0.encodesRumbleTemplate })
  func rejectsTemplatesForDriversThatDoNotEncodeThem(family: PhysicalProtocolID) {
    let variant = family.storesVariant ? family.variants.first?.rawValue : nil
    let protocolInfo =
      variant.map { "{\"family\": \"\(family.rawValue)\", \"variant\": \"\($0)\"}" }
      ?? "{\"family\": \"\(family.rawValue)\"}"
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo), "
          + "\"session\": {\(Self.gp100Rumble)}}]"
      )
    }
  }

  /// Rumble templates that fail to decode.
  private static let invalidRumbleTemplates: [String] = [
    #"{"report": {"kind": "input", "id": 2, "length": 8}, "lowFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "Output", "id": 256, "length": 8}, "lowFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 1}, "lowFrequency": {"byte": 0}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 65}, "lowFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 0}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 8}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 3}, "#
      + #""highFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 3, "max": 9}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "leftHaptic": {"byte": 3}}"#,
    // A motor's encoding must be named and its bytes must fit and not overlap.
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "#
      + #""lowFrequency": {"byte": 3, "encoding": "UInt16"}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "#
      + #""lowFrequency": {"byte": 7, "encoding": "UInt16BigEndian"}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "#
      + #""lowFrequency": {"byte": 2, "encoding": "SwitchHDRumble"}, "#
      + #""highFrequency": {"byte": 5}}"#,
    // Fixed bytes cover the whole report and lead with its ID.
    #"{"report": {"kind": "Output", "id": 2, "length": 3}, "bytes": "02 00", "#
      + #""lowFrequency": {"byte": 1}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 3}, "bytes": "03 00 00", "#
      + #""lowFrequency": {"byte": 1}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 3}, "bytes": "02 0a 00", "#
      + #""lowFrequency": {"byte": 1}}"#,
    // The counter is one free byte after the report ID.
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "counter": {"byte": 3}, "#
      + #""lowFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "counter": {"byte": 0}, "#
      + #""lowFrequency": {"byte": 3}}"#,
    // The resend interval is a keep-alive's.
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "#
      + #""resendIntervalMilliseconds": 0, "lowFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "#
      + #""resendIntervalMilliseconds": 60001, "lowFrequency": {"byte": 3}}"#,
    // A usb packet has a length only, and a HID mode sends no usb packet.
    #"{"report": {"kind": "USB", "id": 2, "length": 8}, "lowFrequency": {"byte": 3}}"#,
    #"{"report": {"kind": "USB", "length": 8}, "lowFrequency": {"byte": 3}}"#,
  ]

  @Test(arguments: invalidRumbleTemplates)
  func rejectsInvalidRumbleTemplates(rumble: String) {
    #expect(throws: DecodingError.self) {
      try decode(Self.thirdPartyModes(session: "{\"rumble\": \(rumble)}"))
    }
  }

  @Test
  func rejectsUnknownOutputTemplates() {
    #expect(throws: DecodingError.self) {
      try decode(Self.thirdPartyModes(session: "{\(Self.gp100Rumble), \"lighting\": {}}"))
    }
  }

  /// A HID mode has no raw-USB session to keep alive.
  @Test
  func rejectsAKeepAliveInAHIDMode() {
    let keepAlive = #"{"intervalMilliseconds": 500, "writes": [{"bytes": "01"}]}"#
    #expect(throws: DecodingError.self) {
      try decode(Self.thirdPartyModes(session: "{\"keepAlive\": \(keepAlive)}"))
    }
  }

  /// A report ID of 0 has no ID byte, so byte 0 carries a motor; a feature report stays a feature.
  @Test
  func writesReportsWithoutAnIDAndFeatureReports() throws {
    let unnumbered = try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .output, reportID: 0, length: 4)),
      motors: [.lowFrequency: .init(byte: 0), .rightTrigger: .init(byte: 3)]
    )
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(byte: 0x11),
      highFrequency: UnipolarValue(byte: 0x22),
      rightTrigger: UnipolarValue(byte: 0x33)
    )
    guard case .hidOutput(let report) = unnumbered.write(intensities) else {
      Issue.record("expected an output report")
      return
    }
    #expect(report.reportID == 0)
    #expect(report.bytes == [0x11, 0, 0, 0x33])

    let feature = try RumbleOutputTemplate(
      target: .hid(ControllerTemplateReport(kind: .feature, reportID: 5, length: 3)),
      motors: [.highFrequency: .init(byte: 1)]
    )
    guard case .hidFeature(let featureReport) = feature.write(intensities) else {
      Issue.record("expected a feature report")
      return
    }
    #expect(featureReport.bytes == [5, 0x22, 0])
  }

  /// Fixed bytes stay, each motor writes its encoding at its byte, and the counter fills its byte.
  @Test
  func decodesFixedBytesEncodingsAndACounter() throws {
    let rumble = #"""
      "rumble": {"report": {"kind": "Output", "id": 2, "length": 12},
        "bytes": "02 00 AA 00 00 00 00 00 00 00 00 BB", "counter": {"byte": 1},
        "lowFrequency": {"byte": 3, "encoding": "UInt16BigEndian"},
        "highFrequency": {"byte": 5, "encoding": "UInt16LittleEndian"},
        "leftTrigger": {"byte": 7, "encoding": "SwitchHDRumble"},
        "resendIntervalMilliseconds": 250}
      """#
    let document = try decode(Self.thirdPartyModes(session: "{\(rumble)}"))
    let template = try #require(document.baseMode.session.rumbleTemplate)
    #expect(template.counterByte == 1 && template.resendIntervalMilliseconds == 250)
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(0x1234),
      highFrequency: UnipolarValue(0x5678),
      leftTrigger: UnipolarValue(byte: 0xFF)
    )
    let hd = SwitchProRumbleCodec.encode(intensity: 0xFF)
    #expect(
      template.reportBytes(intensities, counter: 0x0C)
        == [0x02, 0x0C, 0xAA, 0x12, 0x34, 0x78, 0x56] + hd + [0xBB]
    )
    #expect(
      template.reportBytes(.off)
        == [0x02, 0x00, 0xAA, 0, 0, 0, 0] + SwitchProRumbleCodec.encode(intensity: 0) + [0xBB]
    )
  }

  /// A usb packet has no report ID, so byte 0 is free and the bytes need not lead with an ID.
  @Test
  func buildsRawUSBPackets() throws {
    let packet = try RumbleOutputTemplate(
      target: .usb(length: 6),
      bytes: [0x0F, 0x20, 0x66, 0x55, 0, 0],
      motors: [.lowFrequency: .init(byte: 4), .highFrequency: .init(byte: 5)]
    )
    #expect(packet.report == nil)
    let intensities = RumbleIntensities(
      lowFrequency: UnipolarValue(byte: 0x40),
      highFrequency: UnipolarValue(byte: 0x80)
    )
    #expect(packet.reportBytes(intensities) == [0x0F, 0x20, 0x66, 0x55, 0x40, 0x80])
    #expect(throws: ControllerRecordProblem.self) {
      try RumbleOutputTemplate(target: .usb(length: 65), motors: [.lowFrequency: .init(byte: 0)])
    }
  }

  /// A raw-USB mode names a usb packet, never a HID report.
  @Test
  func rejectsAHIDTemplateInARawUSBMode() {
    let protocolInfo = #"{"family": "XboxXUSB", "variant": "Wired"}"#
    let rumble =
      #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 3}}"#
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo), "
          + "\"session\": {\"rumble\": \(rumble)}}]"
      )
    }
  }

  private func record(
    protocolInfo: String,
    template: String
  ) throws -> ControllerRecordDocument {
    try decode(
      "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo), "
        + "\"session\": {\"rumble\": \(template)}}]"
    )
  }

  private static let usbRumble =
    #"{"report": {"kind": "USB", "length": 6}, "lowFrequency": {"byte": 2}}"#
  private static let shieldRumble =
    #"{"report": {"kind": "Output", "id": 1, "length": 7}, "lowFrequency": {"byte": 2}}"#

  /// A record may carry a rumble template for each family whose driver encodes one.
  @Test
  func acceptsARumbleTemplateForEachDriverThatEncodesOne() throws {
    let accepted: [(String, String)] = [
      (#"{"family": "XboxXID", "variant": "Gamepad"}"#, Self.usbRumble),
      (#"{"family": "XboxXUSB", "variant": "Wired"}"#, Self.usbRumble),
      (#"{"family": "XboxXUSB", "variant": "Receiver"}"#, Self.usbRumble),
      (
        #"{"family": "VendorNVIDIAShield", "parameters": {"reportRevision": "Shield2015"}}"#,
        Self.shieldRumble
      ),
    ]
    for (protocolInfo, template) in accepted {
      let document = try record(protocolInfo: protocolInfo, template: template)
      #expect(document.baseMode.session.rumbleTemplate != nil, "\(protocolInfo)")
    }
  }

  /// A record template the driver would ignore is refused, not dropped.
  @Test
  func rejectsARumbleTemplateTheDriverIgnores() {
    let refused: [(String, String)] = [
      (#"{"family": "VendorNVIDIAShield"}"#, Self.shieldRumble),
      (#"{"family": "VendorGameSir", "variant": "USB"}"#, Self.usbRumble),
    ]
    for (protocolInfo, template) in refused {
      #expect(throws: DecodingError.self, "\(protocolInfo)") {
        try record(protocolInfo: protocolInfo, template: template)
      }
    }
  }

  /// Sixaxis keeps its family writes; a record template adds exactly its own report.
  @Test
  func macOSOwnedOutputAddsOnlyTheRecordReport() throws {
    let sixaxis = MacOSOwnedOutput.allowance(for: .sonySixaxis, record: nil)
    let sixaxisReport = PhysicalHIDOutputReport(
      reportID: 1,
      bytes: [1] + [UInt8](repeating: 0, count: 48)
    )
    #expect(sixaxis.permits(sixaxisReport, kind: .output))
    #expect(!sixaxis.permits(sixaxisReport, kind: .feature))
    #expect(!sixaxis.permits(PhysicalHIDOutputReport(reportID: 1, bytes: [1, 0]), kind: .output))
    #expect(sixaxis.setsStartupPlayerIndicator && sixaxis.readsStartupFeatures)

    #expect(MacOSOwnedOutput.allowance(for: .hidReportLayout, record: nil) == .none)
    let gp100 = try #require(
      DeviceCatalog().record(for: ControllerModelID(vendorID: 0x2563, productID: 0x0575))
    )
    let allowance = MacOSOwnedOutput.allowance(for: .hidReportLayout, record: gp100)
    let rumble = PhysicalHIDOutputReport(reportID: 2, bytes: [2, 0, 0, 0, 0, 0, 0, 0])
    #expect(allowance.drivesRumble)
    #expect(allowance.permits(rumble, kind: .output))
    #expect(!allowance.permits(PhysicalHIDOutputReport(reportID: 2, bytes: [2, 0]), kind: .output))
    #expect(!allowance.permits(sixaxisReport, kind: .output))
    #expect(!allowance.setsStartupPlayerIndicator && !allowance.readsStartupFeatures)
    #expect(allowance.narrowing(.dualMainRumble) == .dualMainRumble)
    #expect(MacOSOwnedOutput.none.narrowing(.dualMainRumble) == .none)
  }

  /// A native DS4 gets only the startup feature read that switches Bluetooth to report 0x11.
  @Test
  func macOSOwnedDualShock4ReadsStartupFeaturesOnly() {
    let ds4 = MacOSOwnedOutput.allowance(for: .sonyDualShock4, record: nil)
    #expect(ds4.readsStartupFeatures)
    #expect(ds4.reports.isEmpty && ds4.lightingFeatures.isEmpty && !ds4.drivesRumble)
    #expect(!ds4.setsStartupPlayerIndicator)
  }

  /// Decodes a record for 2563:0575 whose remaining top-level fields are `fields`.
  private func decode(_ fields: String) throws -> ControllerRecordDocument {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
      "vendorID": 9571, "productID": 1397, \
      \(fields)}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }
}
