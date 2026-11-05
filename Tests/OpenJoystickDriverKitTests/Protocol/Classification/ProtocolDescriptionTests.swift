import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

@Suite
struct ProtocolDescriptionTests {
  private static let minimalInput =
    #"{"report": {"length": {"atLeast": 1}}, "#
    + #""buttons": [{"control": "South", "byte": 0, "mask": 1}]}"#
  private static let rumbleTemplate =
    #"{"report": {"kind": "Output", "id": 1, "length": 4}, "lowFrequency": {"byte": 1}}"#
  private static let startupWrite =
    #"{"startup": [{"report": {"kind": "Output", "id": 1, "length": 4}, "bytes": "01 02 03"}]}"#

  /// Decodes a description of `family` whose body after the header is `body`, with the family's
  /// session counts and `sessionKeys` added to any the body leaves unstated.
  private func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    try ProtocolDescriptionFixture.decode(family: family, body)
  }

  private func decodeExactly(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    try ProtocolDescriptionFixture.decodeExactly(family: family, body)
  }

  private func rejection(
    exactly family: PhysicalProtocolID,
    _ body: String
  ) -> ProtocolDescriptionProblem? {
    do {
      _ = try decodeExactly(family: family, body)
      return nil
    } catch { return error }
  }

  private func rejection(family: PhysicalProtocolID, _ body: String) -> ProtocolDescriptionProblem?
  {
    do {
      _ = try decode(family: family, body)
      return nil
    } catch { return error }
  }

  // MARK: - Bundled descriptions

  @Test
  func everyFamilyThatDeclaresParametersHasADescription() {
    for family in PhysicalProtocolID.allCases {
      let description = ProtocolDescription.bundled[family]
      if !ProtocolParameters.declared(by: family).isEmpty {
        #expect(description != nil, "\(family.rawValue)")
      }
    }
    #expect(ProtocolDescription.bundled.count == PhysicalProtocolID.allCases.count)
  }

  /// The family facts the drivers read come from the descriptions.
  @Test
  func bundledDescriptionsHoldTheFamilyFacts() throws {
    let bundled = ProtocolDescription.bundled
    #expect(bundled[.xboxXUSB]?.endpoints == .init(input: 129, output: 1))
    #expect(bundled[.xboxXID]?.endpoints == .init(input: 129, output: 2))
    #expect(bundled[.xboxGIP]?.endpoints == .init(input: 130, output: 2))
    #expect(bundled[.xboxXID]?.rawUSB == .always)
    #expect(bundled[.vendorGameSir]?.rawUSB == .variants([.usb]))
    #expect(bundled[.sonyDualSense]?.rawUSB == .never)
    #expect(bundled[.hidReportLayout]?.recordSections == [.input, .rumble])
    #expect(bundled[.vendorPS3ThirdParty]?.recordSections == [.rumble])
    #expect(bundled[.sonyDualShock4]?.tuning?.inputLivenessTimeoutMilliseconds == 1_000)
    #expect(bundled[.nintendoSwitch1]?.tuning?.minimumHIDOutputIntervalMilliseconds == 50)
    #expect(bundled[.vendorGameSir]?.tuning?.hidStartupIntervalMilliseconds == 20)
    #expect(bundled[.nintendoSwitch1]?.tuning?.hidStartupRecoveryIntervalMilliseconds == 200)
    #expect(bundled[.nintendoSwitch1]?.tuning?.hidStartupRecoveryRounds == 2)
    #expect(bundled[.nintendoSwitch2]?.keepAlive?.intervalMilliseconds == 12)
    #expect(bundled[.valveSteamDeck]?.keepAlive?.intervalMilliseconds == 1_000)
    #expect(bundled[.valveSteamTriton]?.keepAlive?.intervalMilliseconds == 40)
    #expect(bundled[.xboxGIP]?.keepAlive?.intervalMilliseconds == 4_000)
    #expect(bundled[.vendorGameSir]?.keepAlive?.intervalMilliseconds == 500)
    #expect(bundled[.valveSteamTriton]?.tuning?.lizardResendTicks == 75)
    #expect(bundled[.nintendoSwitch2]?.tuning?.usbCommandTimeoutMilliseconds == 1_000)
    #expect(bundled[.vendorGameSir]?.tuning?.usbCommandTimeoutMilliseconds == 2_000)
    #expect(bundled[.xboxGIP]?.tuning?.presenceResendReports == 4)
    #expect(bundled[.xboxGIP]?.tuning?.usbStartupIntervalMilliseconds == 50)
    #expect(bundled[.xboxGIP]?.tuning?.usbStartupRetryDelayMilliseconds == 1_000)
    #expect(bundled[.xboxGIP]?.tuning?.usbTransferTimeoutMilliseconds == 2_000)
    #expect(bundled[.xboxXUSB]?.tuning?.usbTransferTimeoutMilliseconds == 2_000)
    #expect(bundled[.xboxXID]?.tuning?.usbTransferTimeoutMilliseconds == 2_000)
    #expect(bundled[.xboxGIP]?.handshakeAttempts == 3)
    #expect(bundled[.xboxGIP]?.announceResendLimit == 8)
    #expect(bundled[.sonyDualShock4]?.tuning?.adapterDisconnectDelayMilliseconds == 500)
    #expect(bundled[.sonyDualSense]?.tuning?.adapterDisconnectDelayMilliseconds == 500)
    let switch1 = try #require(bundled[.nintendoSwitch1])
    #expect(switch1.tuning(variant: .bluetoothClassic)?.hidStartupIntervalMilliseconds == 60)
    #expect(switch1.tuning(variant: .usb)?.hidStartupIntervalMilliseconds == 20)
    #expect(bundled[.sonyDualSense]?.recordCapabilities.presentControls.count == 4)
    #expect(bundled[.xboxGIP]?.recordCapabilities.rumbleAbsent == true)
    let sixaxis = try #require(bundled[.sonySixaxis]).macOSOwnedOutput
    #expect(sixaxis.drivesRumble && sixaxis.setsStartupPlayerIndicator)
    #expect(
      sixaxis.reports == [ControllerTemplateReport(kind: .output, reportID: 0x01, length: 49)]
    )
  }

  /// A raw-USB variant reads no HID timing.
  @Test
  func tuningScopeFollowsTheDescription() {
    let gameSir = ControllerTuning.scope(protocolID: .vendorGameSir, variant: .usb)
    #expect(
      gameSir == [.stickDeadzone, .frameQueueCapacity, .usbCommandTimeoutMs]
    )
    let enhanced = ControllerTuning.scope(protocolID: .vendorGameSir, variant: .enhancedHID)
    #expect(
      enhanced == [
        .stickDeadzone, .frameQueueCapacity, .hidStartupIntervalMs, .minimumHIDOutputIntervalMs,
      ]
    )
    #expect(
      ControllerTuning.scope(protocolID: .xboxGIP, variant: nil)
        == [
          .stickDeadzone, .frameQueueCapacity, .presenceResendReports, .usbStartupIntervalMs,
          .usbStartupRetryDelayMs, .usbTransferTimeoutMs,
        ]
    )
    #expect(
      ControllerTuning.scope(protocolID: .xboxXUSB, variant: nil)
        == [
          .stickDeadzone, .frameQueueCapacity, .usbTransferTimeoutMs,
        ]
    )
    #expect(
      ControllerTuning.scope(protocolID: .xboxXID, variant: nil)
        == [.stickDeadzone, .frameQueueCapacity, .usbTransferTimeoutMs]
    )
    #expect(
      ControllerTuning.scope(protocolID: nil, variant: nil) == [
        .stickDeadzone, .frameQueueCapacity,
      ]
    )
    #expect(
      ControllerTuning.scope(protocolID: .sonyDualShock4, variant: nil)
        .contains(.inputLivenessTimeoutMs)
    )
  }

  /// The parameters a description declares are those `ProtocolParameters` decodes: the names
  /// match, and an enum's values are cases of the Swift enum that holds it.
  @Test
  func declaredParametersMatchTheSwiftParameterTypes() {
    let enums: [String: [String]] = [
      "layout": ProtocolParameters.Layout.allCases.map(\.rawValue),
      "usbProtocol": ProtocolParameters.USBProtocol.allCases.map(\.rawValue),
      "lightingMemory": ProtocolParameters.LightingMemory.allCases.map(\.rawValue),
      "hatSource": ProtocolParameters.HatSource.allCases.map(\.rawValue),
      "motionCalibration": ProtocolParameters.MotionCalibration.allCases.map(\.rawValue),
      "role": ProtocolParameters.Role.allCases.map(\.rawValue),
      "motionScale": ProtocolParameters.MotionScale.allCases.map(\.rawValue),
      "reportRevision": ProtocolParameters.ReportRevision.allCases.map(\.rawValue),
      "maker": ProtocolParameters.Maker.allCases.map(\.rawValue),
    ]
    let flags: Set<String> = [
      "innerGrips", "unprobedSensors", "unprobedTouchpad", "forcedVibration",
    ]
    var declared: Set<String> = []
    var enumValues: [String: Set<String>] = [:]
    for description in ProtocolDescription.bundled.values {
      for (name, type) in description.parameters {
        declared.insert(name)
        switch type {
        case .flag: #expect(flags.contains(name), "\(name)")
        case .enumeration(let values):
          #expect(Set(values).isSubset(of: enums[name] ?? []), "\(name)")
          enumValues[name, default: []].formUnion(values)
        case .object(let fields):
          #expect(name == "shareButton")
          #expect(fields == ["fromEnd": ProtocolParameters.ShareButton.fromEndRange])
        }
      }
    }
    #expect(declared == ProtocolParameters.names)
    for (name, values) in enums { #expect(enumValues[name] == Set(values), "\(name)") }
  }

  // MARK: - Defaults

  @Test
  func decodesDefaultsTheirDriverReads() throws {
    let layout = try decode(
      family: .hidReportLayout,
      #""recordSections": ["input"], "#
        + #""defaults": {"input": \#(Self.minimalInput), "tuning": {"stickDeadzone": 0.1}}"#
    )
    #expect(layout.inputLayout?.controls == [.south])
    #expect(layout.tuning == ControllerTuning(stickDeadzone: 0.1))

    let hid = try decode(
      family: .sonyDualShock4,
      #""defaults": {"session": \#(Self.startupWrite)}"#
    )
    #expect(hid.startupWrites.count == 1)

    let ds4 = try decode(
      family: .sonyDualShock4,
      #""tuningKeys": ["inputLivenessTimeoutMs"], "#
        + #""defaults": {"tuning": {"inputLivenessTimeoutMs": 1500}}"#
    )
    #expect(ds4.tuning == ControllerTuning(inputLivenessTimeoutMilliseconds: 1_500))
  }

  @Test
  func anXboxXIDDescriptionMayDeclareAnInputLayout() throws {
    let description = try decode(
      family: .xboxXID,
      #""rawUSB": true, "recordSections": ["input"], "#
        + #""defaults": {"input": \#(Self.minimalInput)}"#
    )
    #expect(description.inputLayout?.controls == [.south])
  }

  @Test
  func decodesParameterDeclarations() throws {
    let description = try decode(
      family: .sonyDualSense,
      """
      "parameters": {"maker": {"type": "Enum", "values": ["ThirdParty"]},
                     "forcedVibration": {"type": "Flag"}}
      """
    )
    #expect(
      description.parameters == [
        "maker": .enumeration(["ThirdParty"]), "forcedVibration": .flag,
      ]
    )
    let gip = try decode(
      family: .xboxGIP,
      """
      "parameters": {"shareButton": {"type": "Object",
                                      "fields": {"fromEnd": {"type": "Integer",
                                                             "minimum": 1, "maximum": 255}}}}
      """
    )
    #expect(gip.parameters == ["shareButton": .object(["fromEnd": 1...255])])
  }

  /// `ProtocolParameters.violation` takes the ranges and enum values from the description.
  @Test
  func parameterViolationsReadTheDescription() {
    var parameters = ProtocolParameters()
    parameters.shareButton = .init(fromEnd: 300)
    #expect(
      parameters.violation(family: .xboxGIP, variant: nil)
        == "shareButton.fromEnd must be in 1...255"
    )
    parameters.shareButton = .init(fromEnd: 2)
    #expect(parameters.violation(family: .xboxGIP, variant: nil) == nil)
  }

  // MARK: - Rejections

  @Test(
    arguments: [
      (PhysicalProtocolID.sonyDualSense, #""parameters": {"maker": {"type": "string"}}"#),
      (.sonyDualSense, #""parameters": {"maker": {"type": "Enum", "values": []}}"#),
      (.sonyDualSense, #""parameters": {"maker": {"type": "Enum", "values": ["thirdParty"]}}"#),
      (.sonyDualSense, #""parameters": {"maker": {"type": "Flag", "values": ["A"]}}"#),
      (.sonyDualSense, #""parameters": {"unknown": {"type": "Flag"}}"#),
      (.sonyDualSense, #""parameters": {}"#),
      (
        .xboxGIP,
        #""parameters": {"shareButton": {"type": "Object", "fields": "#
          + #"{"fromEnd": {"type": "Integer", "minimum": 9, "maximum": 1}}}}"#
      ),
      (.xboxGIP, #""defaults": {"unknown": {}}"#),
      (.xboxGIP, #""defaults": {"capabilities": {"rumble": "Absent"}}"#),
      (.xboxGIP, #""defaults": {"tuning": {"stickDeadzone": 5}}"#),
      (.xboxGIP, #""interfaceSignatures": []"#),
      (.xboxGIP, #""rawUSB": true, "tuningKeys": ["keepAliveIntervalMs"]"#),
      (.sonyDualSense, #""rawUSBTuningKeys": ["keepAliveIntervalMs"]"#),
      (.sonyDualSense, #""defaults": {"variants": {"USB": {"tuning": {"stickDeadzone": 5}}}}"#),
      (.sonyDualSense, #""macOSOwnedOutput": {"rationale": 5}"#),
      (.xboxGIP, #""defaults": {"session": {"rumble": \#(Self.rumbleTemplate)}}"#),
      (.sonyDualSense, #""tuningKeys": ["stickDeadzone"]"#),
      (.xboxGIP, #""rawUSB": true, "rawUSBTuningKeys": ["stickDeadzone"]"#),
    ]
  )
  func rejectsAMalformedBody(family: PhysicalProtocolID, body: String) {
    #expect(rejection(family: family, body)?.code == .invalidProtocolDescription, "\(body)")
  }

  /// A description sets exactly the family-specific session fields its driver reads.
  @Test
  func aFamilySpecificSessionFieldOfAnotherFamilyIsRefused() {
    let foreign: [(PhysicalProtocolID, String)] = [
      (.xboxXUSB, "handshakeAttempts"), (.xboxXUSB, "announceResendLimit"),
      (.xboxXID, "handshakeAttempts"),
      (.sonyDualSense, "announceResendLimit"), (.sonyDualSense, "trailingStopPackets"),
    ]
    for (family, key) in foreign {
      let body = #""defaults": {"session": {"\#(key)": 3}}"#
      let problem = rejection(family: family, body)
      #expect(problem?.code == .invalidProtocolDescription, "\(family) \(key)")
      #expect(problem?.detail.contains("does not read \(key)") == true, "\(family) \(key)")
    }
    let activation =
      #""defaults": {"session": {"activation": [{"report": "#
      + #"{"kind": "Feature", "id": 0, "length": 2}, "bytes": "81 00"}]}}"#
    #expect(rejection(family: .sonyDualSense, activation)?.code == .invalidProtocolDescription)
  }

  @Test
  func aSessionFieldTheDriverReadsMustBeSet() {
    let missing: [(PhysicalProtocolID, String)] = [
      (.xboxGIP, #""rawUSB": true"#),
      (.xboxGIP, #""rawUSB": true, "defaults": {"session": {"handshakeAttempts": 3}}"#),
      (.nintendoSwitch1, ""),
      (.valveSteamDeck, ""),
    ]
    for (family, body) in missing {
      let problem = rejection(
        exactly: family,
        ProtocolDescriptionFixture.sessionKeyMembers(of: family) + body
      )
      #expect(problem?.code == .invalidProtocolDescription, "\(family) \(body)")
      #expect(problem?.detail.contains("must set") == true, "\(family) \(body)")
    }
  }

  /// The code states what each driver reads, and a description declares exactly that: the
  /// parameters and the family-specific session fields.
  @Test(arguments: PhysicalProtocolID.allCases)
  func eachBundledDescriptionDeclaresWhatItsDriverReads(family: PhysicalProtocolID) throws {
    let description = try #require(ProtocolDescription.bundled[family])
    #expect(Set(description.parameters.keys) == family.readParameters, "\(family.rawValue)")
    #expect(description.presentSessionFields == family.sessionFields, "\(family.rawValue)")
    #expect(description.sessionKeys == family.generalSessionFields, "\(family.rawValue)")
    #expect(
      description.presentGeneralSessionFields.isSubset(of: description.sessionKeys),
      "\(family.rawValue)"
    )
  }

  /// The general session keys are the schema's list, which Python reads.
  @Test
  func theGeneralSessionKeysAreTheSchemasList() throws {
    let schema = try JSONSchemaFiles.document(named: "protocol-description.schema.json")
    let defs = try #require(schema["$defs"] as? [String: Any])
    let general = try #require(defs["generalSessionKeys"] as? [String: Any])
    let keys = try #require(general["properties"] as? [String: Any])
    #expect(Set(keys.keys) == ProtocolDescription.Document.Session.generalKeys)
  }

  @Test
  func sessionLimitsComeFromTheirFamily() throws {
    let gip = try decode(family: .xboxGIP, #""rawUSB": true"#)
    #expect(gip.handshakeAttempts == 3 && gip.announceResendLimit == 8)
    let xusb = try decode(family: .xboxXUSB, #""rawUSB": true"#)
    #expect(xusb.handshakeAttempts == nil && xusb.announceResendLimit == nil)
  }

  @Test(
    arguments: [
      (PhysicalProtocolID.xboxGIP, "handshakeAttempts", 1, 10),
      (.xboxGIP, "announceResendLimit", 1, 100),
    ]
  )
  func sessionLimitsHaveRanges(
    family: PhysicalProtocolID,
    key: String,
    low: Int,
    high: Int
  ) {
    for value in [low, high] {
      let body = #""rawUSB": true, "defaults": {"session": {"\#(key)": \#(value)}}"#
      #expect(rejection(family: family, body) == nil, "\(key) \(value)")
    }
    for value in [low - 1, high + 1] {
      let body = #""rawUSB": true, "defaults": {"session": {"\#(key)": \#(value)}}"#
      #expect(
        rejection(family: family, body)?.code == .invalidProtocolDescription,
        "\(key) \(value)"
      )
    }
  }

  @Test
  func rejectsDefaultsTheFamilyDriverDoesNotRead() {
    let cases: [(PhysicalProtocolID, String)] = [
      (.hidDescriptor, #""defaults": {"input": \#(Self.minimalInput)}"#),
      (.xboxXUSB, #""defaults": {"input": \#(Self.minimalInput)}"#),
      (.xboxGIP, #""rawUSB": true, "defaults": {"session": \#(Self.startupWrite)}"#),
      (.xboxXID, #""rawUSB": true, "defaults": {"tuning": {"hidStartupIntervalMs": 5}}"#),
      (.sonyDualSense, #""defaults": {"tuning": {"hidStartupIntervalMs": 5}}"#),
      (
        .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"tuning": {"inputLivenessTimeoutMs": 5}}"#
      ),
      (.sonyDualSense, #""defaults": {"tuning": {"hidStartupRecoveryRounds": 5}}"#),
    ]
    for (family, body) in cases {
      #expect(rejection(family: family, body)?.code == .invalidProtocolDescription, "\(body)")
    }
  }

  /// XboxXID lists no `sessionKeys`, so its `defaults.session` refuses startup packets and a
  /// keep-alive.
  @Test
  func anXIDSessionHoldsOnlyARumbleTemplate() {
    let session = [
      #""startup": [{"bytes": "01 02"}]"#,
      #""keepAlive": {"intervalMilliseconds": 500, "writes": [{"bytes": "01 02"}]}"#,
    ]
    for member in session {
      let problem = rejection(
        family: .xboxXID,
        #""rawUSB": true, "recordSections": ["rumble"], "defaults": {"session": {\#(member)}}"#
      )
      #expect(problem?.code == .invalidProtocolDescription, "\(member)")
      #expect(
        problem?.description.contains("which sessionKeys does not list") == true,
        "\(member)"
      )
    }
  }

  /// A description lists the general session keys its driver reads, no other.
  @Test
  func sessionKeysAreTheOnesTheDriverReads() {
    let cases: [(PhysicalProtocolID, String)] = [
      (.xboxXID, #""rawUSB": true, "sessionKeys": ["keepAlive"]"#),
      (.xboxXID, #""rawUSB": true, "sessionKeys": ["startup", "startup"]"#),
      (.xboxXID, #""rawUSB": true, "sessionKeys": ["rumble"]"#),
      (.xboxXID, #""rawUSB": true, "sessionKeys": ["subcommands"]"#),
      (.xboxXID, #""rawUSB": true, "sessionKeys": []"#),
      (.sonyDualShock4, #""sessionKeys": ["startup", "keepAlive"]"#),
      (.sonyDualShock4, #""sessionKeys": ["keepAlive"]"#),
    ]
    for (family, body) in cases {
      let problem = rejection(exactly: family, body)
      #expect(problem?.code == .invalidProtocolDescription, "\(family) \(body)")
    }
    let without = rejection(exactly: .sonyDualShock4, #""recordSections": ["rumble"]"#)
    #expect(without?.description.contains("reads the session keys startup") == true)
  }

  private static let hidReport = #""report": {"kind": "Output", "id": 1, "length": 4}"#

  private func startup(_ write: String) -> String {
    #""defaults": {"session": {"startup": ["# + write + "]}}"
  }

  private func hidWrite(_ field: String) -> String {
    "{\(Self.hidReport), \"bytes\": \"01 02 03\"" + (field.isEmpty ? "}" : ", \(field)}")
  }

  @Test
  func decodesStartupWritesOfBothFormats() throws {
    let hid = try decode(
      family: .sonyDualShock4,
      startup(
        hidWrite(
          #""phase": "Startup", "delayMilliseconds": 5, "variants": ["USB"]"#
        )
      )
    )
    #expect(hid.startupWrites(phase: .startup, variant: .usb, parameters: .none).count == 1)
    #expect(
      hid.startupWrites(phase: .startup, variant: .bluetoothClassic, parameters: .none).isEmpty
    )
    #expect(hid.startupWrites(phase: .activation, variant: .usb, parameters: .none).isEmpty)
    let usb = try decode(
      family: .xboxGIP,
      #""rawUSB": true, "#
        + startup(
          #"{"bytes": "01 02", "endpoint": 2, "timeoutMilliseconds": 500, "#
            + #""delayMilliseconds": 5, "sessionByte": 1, "toleratesRejection": true}"#
        )
    )
    #expect(usb.usbStartupWrites(variant: nil, parameters: .none).count == 1)
  }

  @Test(
    arguments: [
      #""phase": "later""#, #""delayMilliseconds": 1001"#, #""crc32Seed": 256"#,
      #""crc32Seed": 1"#, #""variants": []"#, #""variants": ["USB", "USB"]"#,
      #""when": {"parameter": "layout", "is": []}"#, #""when": {"parameter": "layout"}"#,
    ]
  )
  func rejectsAMalformedHIDStartupWrite(field: String) {
    let problem = rejection(family: .sonyDualShock4, startup(hidWrite(field)))
    #expect(problem?.code == .invalidProtocolDescription, "\(field)")
  }

  @Test(
    arguments: [
      #""endpoint": 0"#, #""endpoint": 128"#, #""timeoutMilliseconds": 0"#,
      #""timeoutMilliseconds": 60001"#, #""delayMilliseconds": 1001"#,
      #""delayMilliseconds": -1"#, #""sessionByte": 64"#, #""toleratesRejection": 1"#,
    ]
  )
  func rejectsAMalformedUSBStartupWrite(field: String) {
    let body = #""rawUSB": true, "# + startup(#"{"bytes": "01", "# + field + "}")
    #expect(rejection(family: .xboxGIP, body)?.code == .invalidProtocolDescription, "\(field)")
  }

  @Test
  func rejectsStartupWritesMixingBothFormats() {
    let body = startup(hidWrite("") + #", {"bytes": "01"}"#)
    #expect(rejection(family: .sonyDualShock4, body)?.code == .invalidProtocolDescription)
  }

  @Test
  func rejectsAStartupWriteNamingWhatTheFamilyLacks() {
    let variant = rejection(family: .sonyDualShock4, startup(hidWrite(#""variants": ["Wired"]"#)))
    #expect(variant?.code == .unknownProtocolVariant)
    let layout = #""when": {"parameter": "layout", "is": ["Pro"]}"#
    #expect(
      rejection(family: .sonyDualShock4, startup(hidWrite(layout)))?.code
        == .invalidProtocolDescription
    )
    let value = #""when": {"parameter": "layout", "is": ["Triangle"]}"#
    #expect(
      rejection(family: .nintendoSwitch1, startup(hidWrite(value)))?.code
        == .invalidProtocolDescription
    )
  }

  @Test
  func rejectsAVariantTheFamilyDoesNotHave() {
    #expect(
      rejection(family: .vendorGameSir, #""rawUSB": ["Wired"]"#)?.code == .unknownProtocolVariant
    )
    #expect(
      rejection(
        family: .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"variants": {"Wired": {"tuning": {"hidStartupIntervalMs": 5}}}}"#
      )?.code == .unknownProtocolVariant
    )
  }

  @Test
  func rejectsAnEmptySession() {
    #expect(
      rejection(exactly: .xboxGIP, #""defaults": {"session": {}}"#)?.code
        == .invalidProtocolDescription
    )
  }

  @Test
  func rejectsARumbleResendIntervalInAFamilyWithAKeepAlive() {
    let keepAlive = #""keepAlive": {"intervalMilliseconds": 100}"#
    let variant = rejection(
      family: .vendorGameSir,
      #""rawUSB": ["USB"], "recordSections": ["rumble"], "#
        + #""defaults": {"session": {\#(keepAlive)}, "#
        + #""variants": {"EnhancedHID": {"session": "#
        + #"{"rumble": \#(Self.rumbleTemplateWithResend)}}}}"#
    )
    let usb = rejection(
      family: .vendorGameSir,
      #""rawUSB": ["USB"], "recordSections": ["rumble"], "#
        + #""defaults": {"session": {\#(keepAlive)}, "#
        + #""variants": {"USB": {"session": {"rumble": \#(Self.usbRumbleTemplate)}}}}"#
    )
    for problem in [variant, usb] {
      #expect(
        problem?.description.contains(
          "a rumble resendIntervalMilliseconds needs a family "
            + "whose description declares no keepAlive"
        ) == true,
        Comment(rawValue: "\(problem?.description ?? "accepted")")
      )
    }
  }

  @Test
  func rejectsRumbleDefaultsAndStickDeadzoneForTheRightReason() {
    let rumble = rejection(
      family: .xboxGIP,
      #""defaults": {"session": {"rumble": \#(Self.rumbleTemplate)}}"#
    )
    #expect(rumble?.description.contains("rumble templates require") == true)
    let deadzone = rejection(family: .sonyDualSense, #""tuningKeys": ["stickDeadzone"]"#)
    #expect(deadzone?.code == .invalidProtocolDescription)
    #expect(deadzone?.description.contains("stickDeadzone") == true)
  }

  @Test
  func rejectsAVariantTuningKeyOutsideTheVariantScope() {
    #expect(
      rejection(
        family: .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"variants": {"USB": {"tuning": {"adapterDisconnectDelayMs": 7}}}}"#
      )?.code == .invalidProtocolDescription
    )
  }

  @Test
  func variantTuningLayersOverTheFlatTuningWithinTheVariantScope() throws {
    let description = try decode(
      family: .sonyDualSense,
      #""tuningKeys": ["hidStartupIntervalMs", "minimumHIDOutputIntervalMs"], "#
        + #""defaults": {"tuning": {"hidStartupIntervalMs": 5, "minimumHIDOutputIntervalMs": 9}, "#
        + #""variants": {"USB": {"tuning": {"hidStartupIntervalMs": 7}}}}"#
    )
    let usb = description.tuning(variant: .usb)
    #expect(usb?.hidStartupIntervalMilliseconds == 7)
    #expect(usb?.minimumHIDOutputIntervalMilliseconds == 9)
    #expect(description.tuning(variant: .bluetoothClassic)?.hidStartupIntervalMilliseconds == 5)
    #expect(
      rejection(
        family: .sonyDualSense,
        #""tuningKeys": ["hidStartupIntervalMs"], "#
          + #""defaults": {"variants": {"USB": {"tuning": {"keepAliveIntervalMs": 7}}}}"#
      )?.code == .invalidProtocolDescription
    )
  }

  private static let rumbleTemplateWithResend =
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 4}, "#
    + #""resendIntervalMilliseconds": 100}"#
  private static let usbRumbleTemplate =
    #"{"report": {"kind": "USB", "length": 8}, "bytes": "00 08 00 00 00 00 00 00", "#
    + #""lowFrequency": {"byte": 3, "encoding": "UInt16BigEndian"}, "counter": {"byte": 7}, "#
    + #""resendIntervalMilliseconds": 100}"#
  private static let otherRumbleTemplate =
    #"{"report": {"kind": "Output", "id": 2, "length": 8}, "lowFrequency": {"byte": 4}}"#

  private static func variantRumble(_ variant: String, _ template: String) -> String {
    #""defaults": {"variants": {"\#(variant)": {"session": {"rumble": \#(template)}}}}"#
  }

  @Test
  func aVariantRumbleTemplateOverridesTheFlatOneForThatVariantOnly() throws {
    let description = try decode(
      family: .sonyDualSense,
      #""recordSections": ["rumble"], "#
        + #""defaults": {"session": {"rumble": \#(Self.rumbleTemplate)}, "#
        + #""variants": {"USB": {"session": {"rumble": \#(Self.otherRumbleTemplate)}}}}"#
    )
    #expect(description.rumbleTemplate(variant: .usb)?.report?.reportID == 2)
    #expect(description.rumbleTemplate(variant: .usb)?.motors[.lowFrequency]?.byte == 4)
    #expect(description.rumbleTemplate(variant: .bluetoothClassic)?.report?.reportID == 1)
    #expect(description.rumbleTemplate(variant: nil)?.report?.reportID == 1)
  }

  @Test
  func aVariantRumbleTemplateStandsWithoutAFlatOneAndBesideVariantTuning() throws {
    let description = try decode(
      family: .sonyDualSense,
      #""recordSections": ["rumble"], "tuningKeys": ["hidStartupIntervalMs"], "#
        + #""defaults": {"variants": {"USB": {"tuning": {"hidStartupIntervalMs": 7}, "#
        + #""session": {"rumble": \#(Self.otherRumbleTemplate)}}}}"#
    )
    #expect(description.rumbleTemplate(variant: .usb) != nil)
    #expect(description.rumbleTemplate(variant: .bluetoothClassic) == nil)
    #expect(description.tuning(variant: .usb)?.hidStartupIntervalMilliseconds == 7)
  }

  @Test
  func aRawUSBVariantTakesAUSBPacketTemplate() throws {
    let description = try decode(
      family: .sonyDualSense,
      #""rawUSB": ["USB"], "recordSections": ["rumble"], "#
        + Self.variantRumble("USB", Self.usbRumbleTemplate)
    )
    let template = try #require(description.rumbleTemplate(variant: .usb))
    #expect(template.report == nil)
    #expect(template.counterByte == 7 && template.resendIntervalMilliseconds == 100)
    #expect(template.motors[.lowFrequency]?.encoding == .uInt16BigEndian)
  }

  @Test
  func rejectsAVariantRumbleTemplateTheFamilyCannotUse() {
    let cases: [(body: String, code: ErrorCode)] = [
      // A family whose driver reads no rumble section.
      (Self.variantRumble("USB", Self.otherRumbleTemplate), .invalidProtocolDescription),
      // A variant the family lacks.
      (
        #""recordSections": ["rumble"], "# + Self.variantRumble("wired", Self.otherRumbleTemplate),
        .unknownProtocolVariant
      ),
      // A HID template on a raw-USB variant and a usb packet on a HID variant.
      (
        #""rawUSB": ["USB"], "recordSections": ["rumble"], "#
          + Self.variantRumble("USB", Self.otherRumbleTemplate),
        .invalidProtocolDescription
      ),
      (
        #""recordSections": ["rumble"], "# + Self.variantRumble("USB", Self.usbRumbleTemplate),
        .invalidProtocolDescription
      ),
      // Bytes that do not start with the report ID.
      (
        #""recordSections": ["rumble"], "#
          + Self.variantRumble(
            "usb",
            #"{"report": {"kind": "Output", "id": 1, "length": 4}, "bytes": "02 00 00 00", "#
              + #""lowFrequency": {"byte": 1}}"#
          ),
        .invalidProtocolDescription
      ),
      // An empty variant and an empty variant session.
      (
        #""recordSections": ["rumble"], "defaults": {"variants": {"USB": {}}}"#,
        .invalidProtocolDescription
      ),
      (
        #""recordSections": ["rumble"], "defaults": {"variants": {"USB": {"session": {}}}}"#,
        .invalidProtocolDescription
      ),
      // A variant session member other than the rumble template.
      (
        #""recordSections": ["rumble"], "defaults": {"variants": {"USB": {"session": "#
          + #"{"keepAlive": {"intervalMilliseconds": 5, "writes": []}}}}}"#,
        .invalidProtocolDescription
      ),
    ]
    for (body, code) in cases {
      #expect(rejection(family: .sonyDualSense, body)?.code == code, "\(body)")
    }
  }

  private static func flatRumble(_ template: String) -> String {
    #""recordSections": ["rumble"], "defaults": {"session": {"rumble": \#(template)}}"#
  }

  @Test
  func theFlatRumbleTemplateIsCheckedAgainstEveryVariantWithoutItsOwn() throws {
    let rejected = [
      // A HID template with every variant raw USB.
      #""rawUSB": true, "# + Self.flatRumble(Self.otherRumbleTemplate),
      // A usb packet with no raw-USB variant.
      Self.flatRumble(Self.usbRumbleTemplate),
      // A HID template reaching the raw-USB variant of a mixed family.
      #""rawUSB": ["USB"], "# + Self.flatRumble(Self.otherRumbleTemplate),
    ]
    for body in rejected {
      let code = rejection(family: .sonyDualSense, body)?.code
      #expect(code == .invalidProtocolDescription, "\(body)")
    }
    let mixed = try decode(
      family: .sonyDualSense,
      #""rawUSB": ["USB"], "recordSections": ["rumble"], "defaults": {"session": {"rumble": "#
        + #"\#(Self.otherRumbleTemplate)}, "variants": {"USB": {"session": {"rumble": "#
        + #"\#(Self.usbRumbleTemplate)}}}}"#
    )
    #expect(mixed.rumbleTemplate(variant: .usb)?.report == nil)
    #expect(mixed.rumbleTemplate(variant: .bluetoothClassic)?.report?.reportID == 2)
  }

  /// The spec scenario: a family's interval is edited in its description, and every record of
  /// the family follows it. A record has no interval of its own.
  @Test
  func aFamilysKeepAliveIntervalComesFromItsDescription() throws {
    let edited = try decode(
      family: .valveSteamDeck,
      #""defaults": {"session": {"keepAlive": {"intervalMilliseconds": 777}, "#
        + Self.valveSessionWrites + "}}"
    )
    let plan = DriverSessionPlan(keepAliveChannels: [.hid]).withKeepAlive(of: edited)
    #expect(plan.hidKeepAliveIntervalNanoseconds == 777_000_000)

    let families: Set<PhysicalProtocolID> = [
      .xboxGIP, .vendorGameSir, .valveSteamDeck, .valveSteamTriton, .nintendoSwitch2,
    ]
    var checked: Set<PhysicalProtocolID> = []
    for record in ControllerRecordSet.bundled.records.values {
      let profile = record.profile
      guard families.contains(profile.physicalProtocolID) else { continue }
      let variant =
        profile.physicalProtocolVariant
        ?? (profile.physicalProtocolID.variants.contains(.usb) ? .usb : nil)
      guard
        case .success(let driver) = ProtocolDriverRegistry.makeUnobservedDriver(
          protocolID: profile.physicalProtocolID,
          variant: variant,
          record: profile,
          model: record.model,
          transportProfile: profile.transportProfile
        )
      else { continue }
      let plan = driver.sessionPlan.tuned(profile.tuning)
      let intervals = [plan.usbKeepAliveIntervalNanoseconds, plan.hidKeepAliveIntervalNanoseconds]
        .compactMap { $0 }
      guard !intervals.isEmpty else { continue }
      let described = try #require(
        profile.physicalProtocolID.protocolDescription.keepAlive?.intervalMilliseconds
      )
      for interval in intervals {
        #expect(interval == UInt64(described) * 1_000_000, "\(record.model)")
      }
      checked.insert(profile.physicalProtocolID)
    }
    #expect(checked == families)
  }

  private static let valveFeature = #"{"report": {"kind": "Feature", "id": 0, "length": 2}"#
  private static let valveSessionWrites =
    #""activation": ["# + valveFeature + #", "bytes": "81 00"}], "deactivation": ["#
    + valveFeature + #", "bytes": "85 00"}]"#

  @Test
  func decodesValveActivationFilteredByTransport() throws {
    let description = try decode(
      family: .valveSteamController,
      #""writeTransports": ["USB", "BluetoothLE"], "defaults": {"session": {"activation": ["#
        + Self.valveFeature + #", "bytes": "81 00", "transport": "USB"}, "#
        + Self.valveFeature + #", "bytes": "82 00", "transport": "BluetoothLE"}, "#
        + Self.valveFeature + #", "bytes": "83 00"}], "deactivation": ["#
        + Self.valveFeature + #", "bytes": "85 00"}]}}"#
    )
    #expect(description.activationWrites(over: .usb).count == 2)
    #expect(description.activationWrites(over: .bluetoothLE).count == 2)
    #expect(description.activationWrites(over: .bluetoothClassic).count == 1)
    #expect(description.deactivationWrites(over: .usb).count == 1)
  }

  @Test(
    arguments: [
      (PhysicalProtocolID.valveSteamController, "BluetoothClassic", false),
      (.valveSteamController, "USB", true), (.valveSteamController, "BluetoothLE", true),
      (.valveSteamDeck, "USB", false), (.valveSteamTriton, "BluetoothLE", false),
    ]
  )
  func activationTransportIsOneWriteTransportsLists(
    family: PhysicalProtocolID,
    transport: String,
    accepted: Bool
  ) {
    let write = Self.valveFeature + #", "bytes": "81 00", "transport": "\#(transport)"}"#
    let transports =
      family == .valveSteamController ? #""writeTransports": ["USB", "BluetoothLE"], "# : ""
    for key in ["activation", "deactivation"] {
      let other = key == "activation" ? "deactivation" : "activation"
      let body =
        transports + #""defaults": {"session": {"\#(key)": ["# + write + #"], "\#(other)": ["#
        + Self.valveFeature + #", "bytes": "85 00"}]}}"#
      #expect((rejection(family: family, body) == nil) == accepted, "\(family) \(transport)")
    }
  }

  @Test(
    arguments: [
      "[]", #"[{"bytes": "81 00"}]"#, #"[{"report": {"kind": "Feature", "id": 0, "length": 2}}]"#,
      #"[{"report": {"kind": "Feature", "id": 0, "length": 2}, "bytes": "81"}]"#,
    ]
  )
  func rejectsMalformedValveActivation(writes: String) {
    let body =
      #""defaults": {"session": {"activation": "# + writes + #", "deactivation": "#
      + writes + "}}"
    #expect(rejection(family: .valveSteamDeck, body)?.code == .invalidProtocolDescription)
  }

  @Test(
    arguments: [
      #""phase": "Startup""#, #""variants": ["Wired"]"#, #""transport": "Radio""#,
      #""delayMilliseconds": 5"#, #""crc32Seed": 1"#,
    ]
  )
  func rejectsValveActivationMembersOfAStartupWrite(field: String) {
    let write = "[" + Self.valveFeature + #", "bytes": "81 00", "# + field + "}]"
    let body =
      #""defaults": {"session": {"activation": "# + write + #", "deactivation": "#
      + write + "}}"
    #expect(rejection(family: .valveSteamDeck, body)?.code == .invalidProtocolDescription)
  }

  @Test
  func rejectsASignatureForAFamilyWithNoVariants() {
    let signature =
      #""interfaceSignatures": [{"variant": "USB", "interfaceClass": 3, "#
      + #""interfaceSubclass": 0, "interfaceProtocol": 0}]"#
    #expect(rejection(family: .hidDescriptor, signature)?.code == .unknownProtocolVariant)
  }

  /// `variants` lists unique, known names and `storesVariant` is `true` and needs `variants`;
  /// each family's lists are the bundled ones, which `PhysicalProtocolID` reads.
  @Test(
    arguments: [
      #""variants": []"#, #""variants": ["USB", "USB"]"#, #""variants": ["usb"]"#,
      #""storesVariant": true"#, #""variants": ["USB"], "storesVariant": false"#,
    ]
  )
  func refusesMalformedVariantFacts(member: String) {
    func problem(_ members: String) -> ProtocolDescriptionProblem? {
      let json = """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
         "family": "XboxGIP", \(members) "sessionKeys": ["startup", "keepAlive"],
         "endpoints": {"in": 130, "out": 2}, "rawUSB": true,
         "defaults": {"session": {"handshakeAttempts": 3, "announceResendLimit": 8,
         "namedPackets": [
          {"id": "XboxGIP/power-on", "bytes": "05 20 00 01 00", "sessionByte": 2}
         ]}}}
        """
      do {
        _ = try ProtocolDescription.decode(
          Data(json.utf8),
          fileName: "xbox-gip.json"
        )
        return nil
      } catch { return error }
    }
    #expect(problem(#""variants": ["USB"],"#) == nil)
    #expect(problem("\(member),")?.code == .invalidProtocolDescription, "\(member)")
  }

  @Test
  func theFamilyReadsItsVariantsFromItsDescription() throws {
    for protocolID in PhysicalProtocolID.allCases {
      let description = try #require(ProtocolDescription.bundled[protocolID])
      #expect(protocolID.variants == description.variants, "\(protocolID.rawValue)")
      #expect(protocolID.storesVariant == description.storesVariant, "\(protocolID.rawValue)")
      #expect(!protocolID.storesVariant || !protocolID.variants.isEmpty, "\(protocolID.rawValue)")
    }
    #expect(PhysicalProtocolID.xboxXUSB.variants == [.wired, .receiver])
    #expect(PhysicalProtocolID.xboxXUSB.storesVariant)
    #expect(PhysicalProtocolID.hidDescriptor.variants.isEmpty)
    #expect(!PhysicalProtocolID.sonyDualSense.storesVariant)
  }

  /// The drivers branch on these variants, so a description that adds, drops or reorders one must
  /// change this table together with the driver that handles it.
  @Test
  func everyFamilysVariantsAreThoseItsDriverHandles() {
    let expected: [PhysicalProtocolID: (variants: [PhysicalProtocolVariantID], stores: Bool)] = [
      .hidDescriptor: ([], false), .hidReportLayout: ([], false),
      .xboxXID: ([.gamepad], true), .xboxXUSB: ([.wired, .receiver], true),
      .xboxGIP: ([.usb], false),
      .sonySixaxis: ([.usb, .bluetoothClassic], false),
      .sonyDualShock4: ([.usb, .bluetoothClassic], false),
      .sonyDualSense: ([.usb, .bluetoothClassic], false),
      .nintendoSwitch1: ([.usb, .bluetoothClassic], false),
      .nintendoSwitch2: ([.usb, .bluetoothLE], false),
      .nintendoSwitchInputOnly: ([.usb, .bluetoothClassic], false),
      .valveSteamController: ([.wired, .dongle, .bluetoothLE], true),
      .valveSteamTriton: ([.wired, .dongle, .bluetoothLE], true),
      .valveSteamDeck: ([], false), .vendorFlydigi: ([], false),
      .vendorPS3ThirdParty: ([], false), .vendorGameSir: ([.usb, .enhancedHID], true),
      .vendorNVIDIAShield: ([], false),
    ]
    #expect(Set(expected.keys) == Set(PhysicalProtocolID.allCases))
    for (protocolID, facts) in expected {
      #expect(protocolID.variants == facts.variants, "\(protocolID.rawValue)")
      #expect(protocolID.storesVariant == facts.stores, "\(protocolID.rawValue)")
    }
  }

  @Test
  func everyRejectionCarriesACatalogCode() {
    let problem = rejection(family: .xboxGIP, #""interfaceSignatures": []"#)
    #expect(problem?.description.hasPrefix("E5002: xbox-gip.json: ") == true)
    #expect(ErrorCode.invalidProtocolDescription.domain == .document)
    #expect(ErrorCode.protocolDescriptionFamilyMismatch.domain == .document)
    #expect(ErrorCode.unknownProtocolVariant.domain == .document)
  }
}

/// Builds protocol description documents for tests.
enum ProtocolDescriptionFixture {
  /// The session counts each family's description must state.
  nonisolated(unsafe) static let sessionLimits: [PhysicalProtocolID: [String: Any]] = [
    .xboxGIP: [
      "handshakeAttempts": 3, "announceResendLimit": 8,
      "namedPackets": [["id": "XboxGIP/power-on", "bytes": "05 20 00 01 00", "sessionByte": 2]],
    ]
  ]

  /// Decodes a description of `family` whose body after the header is `body`, with the family's
  /// session counts and `sessionKeys` added to any the body leaves unstated.
  static func decode(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let keys = body.contains("\"sessionKeys\"") ? "" : sessionKeyMembers(of: family)
    return try decodeExactly(family: family, keys + withSessionLimits(family: family, body))
  }

  /// Decodes a description of `family` whose body after the header is exactly `body`.
  static func decodeExactly(
    family: PhysicalProtocolID,
    _ body: String
  ) throws(ProtocolDescriptionProblem) -> ProtocolDescription {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ProtocolDescription",
       "family": "\(family.rawValue)", \(variantMembers(of: family))
       "endpoints": {"in": 130, "out": 2}, \(body)}
      """
    return try ProtocolDescription.decode(
      Data(json.utf8),
      fileName: "\(family.descriptionFileStem).json"
    )
  }

  /// The `variants` and `storesVariant` members, with a trailing comma, that the bundled
  /// description of `family` states; empty for a family with one contract.
  static func variantMembers(of family: PhysicalProtocolID) -> String {
    guard let bundled = ProtocolDescription.bundled[family], !bundled.variants.isEmpty else {
      return ""
    }
    let names = bundled.variants.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
    return "\"variants\": [\(names)], "
      + (bundled.storesVariant ? "\"storesVariant\": true, " : "")
  }

  /// The `sessionKeys` member, with a trailing comma, that the bundled description of `family`
  /// states; empty for a family that reads none.
  static func sessionKeyMembers(of family: PhysicalProtocolID) -> String {
    let keys = family.generalSessionFields.map(\.rawValue).sorted()
    guard !keys.isEmpty else { return "" }
    return "\"sessionKeys\": [\(keys.map { "\"\($0)\"" }.joined(separator: ", "))], "
  }

  private static func withSessionLimits(family: PhysicalProtocolID, _ body: String) -> String {
    guard let limits = sessionLimits[family] else { return body }
    let json = "{\(body)}"
    guard var object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    else { return body }
    var defaults = object["defaults"] as? [String: Any] ?? [:]
    var session = defaults["session"] as? [String: Any] ?? [:]
    for (key, value) in limits where session[key] == nil { session[key] = value }
    defaults["session"] = session
    object["defaults"] = defaults
    guard
      let data = try? JSONSerialization.data(withJSONObject: object),
      let text = String(data: data, encoding: .utf8)
    else { return body }
    return String(text.dropFirst().dropLast())
  }
}
