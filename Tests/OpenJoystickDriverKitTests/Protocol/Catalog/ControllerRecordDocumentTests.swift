import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordDocumentTests {
  @Test
  func decodesCurrentVocabulary() throws {
    let document = try decode(
      protocol: [
        "family": "XboxGIP", "parameters": ["shareButton": ["fromEnd": 26]],
        "initialization": ["XboxGIP/hori-ack", "XboxGIP/power-on"],
      ],
      usb: ["configuration": "SetConfiguration1BeforeClaim"],
      capabilities: ["absent": ["LeftTrigger", "RightTrigger"], "rumble": "Absent"]
    )

    #expect(document.protocolInfo.protocolID == .xboxGIP)
    #expect(document.protocolInfo.protocolVariant == nil)
    #expect(document.protocolInfo.parameters == ProtocolParameters(shareButton: .init(fromEnd: 26)))
    #expect(document.protocolInfo.initialization == ["XboxGIP/hori-ack", "XboxGIP/power-on"])
    #expect(
      document.capabilities
        == ControllerCapabilityDelta(
          absentControls: [.leftTrigger, .rightTrigger],
          presentControls: [],
          rumbleAbsent: true
        )
    )
    #expect(document.usb?.configuration == "SetConfiguration1BeforeClaim")
  }

  @Test
  func decodesGameSirModelParameters() throws {
    let cases: [([String: any Sendable], ProtocolParameters)] = [
      (["innerGrips": true], ProtocolParameters(innerGrips: true)),
      (["lightingMemory": "ProfileSlots"], ProtocolParameters(lightingMemory: .profileSlots)),
    ]
    for (parameters, expected) in cases {
      let document = try decode(protocol: [
        "family": "VendorGameSir", "variant": "EnhancedHID", "parameters": parameters,
      ])
      #expect(document.protocolInfo.protocolVariant == .enhancedHID)
      #expect(document.protocolInfo.parameters == expected)
    }
  }

  @Test
  func decodesThirdPartyDualSenseModelParameters() throws {
    let document = try decode(
      protocol: [
        "family": "SonyDualSense",
        "parameters": [
          "maker": "ThirdParty", "unprobedSensors": true, "unprobedTouchpad": true,
          "forcedVibration": true, "role": "Receiver",
        ] as [String: any Sendable],
      ],
      vendorID: 0x1532
    )
    #expect(
      document.protocolInfo.parameters
        == ProtocolParameters(
          role: .receiver,
          maker: .thirdParty,
          unprobedSensors: true,
          unprobedTouchpad: true,
          forcedVibration: true
        )
    )
  }

  @Test
  func rejectsDualSenseModelParametersWithoutTheThirdPartyMaker() {
    for vendorID in [0x054C, 0x1532] {
      for parameters in [["role": "Receiver"], ["unprobedTouchpad": true]]
        as [[String: any Sendable]]
      {
        #expect(throws: DecodingError.self) {
          try decode(
            protocol: ["family": "SonyDualSense", "parameters": parameters],
            vendorID: vendorID
          )
        }
      }
    }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter(\.storesVariant))
  func decodesEveryStoredVariant(family: PhysicalProtocolID) throws {
    for variant in family.variants {
      var protocolInfo: [String: any Sendable] = [
        "family": family.rawValue, "variant": variant.rawValue,
      ]
      // Enhanced HID rows must name their model parameter.
      if variant == .enhancedHID { protocolInfo["parameters"] = ["innerGrips": true] }
      let document = try decode(protocol: protocolInfo)
      #expect(document.protocolInfo.protocolID == family)
      #expect(document.protocolInfo.protocolVariant == variant)
    }
    #expect(throws: DecodingError.self) { try decode(protocol: ["family": family.rawValue]) }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter { !$0.storesVariant })
  func rejectsVariantsTheTransportDecides(family: PhysicalProtocolID) throws {
    // A report-layout row must carry its layout; any other row must not.
    let extra: [String: any Sendable] =
      family == .hidReportLayout ? ["input": Self.minimalInput] : [:]
    let document = try decode(protocol: ["family": family.rawValue], extra: extra)
    #expect(document.protocolInfo.protocolID == family)
    #expect(document.protocolInfo.protocolVariant == nil)
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": family.rawValue, "variant": "USB"], extra: extra)
    }
  }

  @Test(
    arguments: [
      ["notAField": "XboxGIP"], ["family": "notAFamily"],
      ["family": "XboxGIP", "variant": "notAVariant"],
      ["family": "XboxGIP", "notAField": true],
      ["family": "XboxGIP", "parameters": ["notAParameter": true]],
      ["family": "XboxXID", "variant": "Gamepad", "parameters": ["notAParameter": true]],
      ["family": "XboxXUSB", "variant": "Wired", "parameters": ["notAParameter": true]],
      ["family": "SonyDualSense", "parameters": ["notAParameter": true]],
      ["family": "SonyDualShock4", "parameters": ["notAParameter": true]],
      ["family": "HIDDescriptor", "parameters": ["notAParameter": true]],
      ["family": "NintendoSwitch1", "parameters": ["notAParameter": true]],
      [
        "family": "ValveSteamController", "variant": "Wired",
        "parameters": ["notAParameter": true],
      ],
      ["family": "VendorGameSir", "variant": "notAVariant"],
      ["family": "VendorGameSir", "variant": "EnhancedHID", "parameters": ["innerGrips": "yes"]],
      ["family": "VendorGameSir", "variant": "EnhancedHID", "parameters": ["innerGrips": false]],
      ["family": "VendorGameSir", "variant": "USB", "parameters": ["innerGrips": true]],
      ["family": "XboxGIP", "parameters": ["shareButton": ["fromEnd": 0]]],
      ["family": "XboxGIP", "parameters": ["shareButton": ["fromEnd": 256]]],
      ["family": "XboxGIP", "parameters": ["shareButton": ["fromEnd": "26"]]],
      ["family": "XboxGIP", "parameters": ["shareButton": ["fromEnd": 26, "notAField": 1]]],
      ["family": "XboxGIP", "parameters": ["shareButton": 26]],
      ["family": "XboxGIP", "initialization": ["XboxGIP/missing"]],
      ["family": "XboxGIP", "initialization": ["XboxGIP/power-on", "XboxGIP/power-on"]],
      ["family": "XboxGIP", "initialization": [String]()],
      ["family": "XboxXUSB", "variant": "Wired", "initialization": ["XboxGIP/power-on"]],
    ] as [[String: any Sendable]]
  )
  func rejectsUnknownProtocolVocabulary(protocolInfo: [String: any Sendable]) {
    #expect(throws: DecodingError.self) { try decode(protocol: protocolInfo) }
  }

  @Test
  func rejectsAnUnknownRecordField() {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "XboxGIP"], extra: ["notAField": "usb"])
    }
  }

  @Test(
    arguments: [
      [:], ["absent": [String]()], ["absent": ["LeftTrigger", "LeftTrigger"]],
      ["absent": ["leftTrigger"]], ["present": ["trackpad"]],
      ["absent": ["Guide"], "present": ["Guide"]], ["rumble": "present"],
      ["rumble": "Absent", "controls": ["Guide"]],
    ] as [[String: any Sendable]]
  )
  func rejectsInvalidCapabilities(capabilities: [String: any Sendable]) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "XboxGIP"], capabilities: capabilities)
    }
  }

  @Test
  func presentControlsAreOnlyTheDualSenseEdgeSet() throws {
    let edge = ["LeftPaddle1", "RightPaddle1", "Auxiliary1", "Auxiliary2"]
    let dualSense: [String: any Sendable] = ["family": "SonyDualSense"]
    let document = try decode(protocol: dualSense, capabilities: ["present": edge])
    #expect(document.capabilities.presentControls == DualSenseDriver.edgeControls)
    #expect(throws: DecodingError.self) {
      try decode(protocol: dualSense, capabilities: ["present": Array(edge.prefix(2))])
    }
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "XboxGIP"], capabilities: ["present": ["LeftPaddle1"]])
    }
  }

  @Test
  func rejectsRumbleAbsenceForDriversThatDoNotDeclareIt() {
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: ["family": "XboxXUSB", "variant": "Wired"],
        capabilities: ["rumble": "Absent"]
      )
    }
  }

  @Test
  func rejectsUSBInterfaceOverride() {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "XboxGIP"], usb: ["interface": 1])
    }
  }

  /// The assembly vocabulary is empty until a row with multi-interface evidence adds a policy.
  @Test(arguments: ["", "steam-dongle", "flydigi-xinput-vendor", "joy-con-pair"])
  func rejectsEveryAssemblyPolicy(name: String) {
    #expect(ControllerAssemblyPolicy(name: name) == nil)
    #expect(throws: DecodingError.self) {
      try decode(protocol: [
        "family": "ValveSteamController", "variant": "Dongle", "assembly": name,
      ])
    }
  }

  @Test
  func noCatalogRowNamesAnAssemblyPolicy() {
    let registry = ProtocolDriverRegistry()
    for model in registry.hidModels + registry.rawUSBModels {
      let record = registry.record(for: model)
      #expect(record?.assemblyPolicy == nil)
      let binding = ProtocolBinding(
        protocolID: record?.physicalProtocolID ?? .hidDescriptor,
        variant: record?.physicalProtocolVariant,
        accessBackend: .hid,
        interfaceNumber: nil,
        rule: .catalogRecord,
        matchedPredicates: [.catalogIdentity],
        record: record
      )
      #expect(registry.assemblyPolicy(for: binding) == nil)
    }
  }

  @Test
  func schemaVocabularyMatchesTheSwiftEnums() throws {
    let schema = try Self.controllerSchema()
    let definitions = try #require(schema["$defs"] as? [String: Any])
    // The description defines the ids; the schema holds only their shape.
    let action = try #require(definitions["namedPacketAction"] as? [String: Any])
    let pattern = try #require(action["pattern"] as? String)
    let identifiers = try #require(
      ProtocolDescription.bundled[.xboxGIP]?.namedPackets?.packets.map(\.id)
    )
    #expect(!identifiers.isEmpty)
    for identifier in identifiers {
      #expect(identifier.range(of: pattern, options: .regularExpression) != nil, "\(identifier)")
    }

    // Every implemented family has catalog rows, so the schema lists all of them.
    let protocolSchema = try #require(definitions["protocol"] as? [String: Any])
    let properties = try #require(protocolSchema["properties"] as? [String: Any])
    #expect(Self.enumValues(properties["family"]) == PhysicalProtocolID.allCases.map(\.rawValue))
    #expect(
      Self.enumValues(properties["assembly"]) == ControllerAssemblyPolicy.allCases.map(\.name)
    )

    // The parameter names are one vocabulary, which the descriptions declare from.
    let descriptionSchema = try Self.descriptionSchema()
    let descriptionProperties = try #require(descriptionSchema["properties"] as? [String: Any])
    let parameters = try #require(descriptionProperties["parameters"] as? [String: Any])
    let names = try #require(parameters["propertyNames"] as? [String: Any])
    #expect(Set(Self.enumValues(names) ?? []) == ProtocolParameters.names)
    let declared = PhysicalProtocolID.allCases.flatMap {
      ProtocolParameters.declared(by: $0)
    }
    #expect(Set(declared) == ProtocolParameters.names)
    for family in PhysicalProtocolID.allCases {
      for (name, type) in family.protocolDescription.parameters {
        guard case .enumeration(let values) = type, let swiftValues = Self.parameterEnums[name]
        else { continue }
        #expect(Set(values).isSubset(of: swiftValues), "\(family.rawValue) \(name)")
      }
    }
  }

  /// An input layout belongs to the `HIDReportLayout` family, which cannot run without one.
  @Test
  func inputLayoutIsRequiredExactlyForTheReportLayoutFamily() throws {
    let document = try decode(
      protocol: ["family": "HIDReportLayout"],
      extra: ["input": Self.minimalInput]
    )
    #expect(document.inputLayout?.controls == [.south])
    #expect(throws: DecodingError.self) { try decode(protocol: ["family": "HIDReportLayout"]) }
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "HIDDescriptor"], extra: ["input": Self.minimalInput])
    }
  }

  /// The smallest valid `input` section: one button in a one-byte report.
  static let minimalInput: [String: any Sendable] = [
    "report": ["length": ["atLeast": 1]] as [String: [String: Int]],
    "buttons": [["control": "South", "byte": 0, "mask": 1] as [String: any Sendable]],
  ]

  @Test
  func decodesTuningWhereADriverReadsIt() throws {
    let ds4 = try decode(
      protocol: ["family": "SonyDualShock4"],
      extra: ["tuning": ["stickDeadzone": 0.05, "inputLivenessTimeoutMs": 1_500]]
    )
    #expect(
      ds4.tuning
        == ControllerTuning(stickDeadzone: 0.05, inputLivenessTimeoutMilliseconds: 1_500)
    )
    let switch1 = try decode(
      protocol: ["family": "NintendoSwitch1"],
      extra: [
        "tuning": [
          "hidStartupIntervalMs": 40, "hidStartupRecoveryIntervalMs": 300,
          "hidStartupRecoveryRounds": 4,
        ]
      ]
    )
    #expect(
      switch1.tuning
        == ControllerTuning(
          hidStartupIntervalMilliseconds: 40,
          hidStartupRecoveryIntervalMilliseconds: 300,
          hidStartupRecoveryRounds: 4
        )
    )
    #expect(try decode(protocol: ["family": "XboxGIP"]).tuning == .none)
    for protocolInfo in [
      ["family": "XboxGIP"], ["family": "XboxXUSB", "variant": "Wired"],
    ] {
      let transfer = try decode(
        protocol: protocolInfo,
        extra: ["tuning": ["usbTransferTimeoutMs": 750]]
      )
      #expect(
        transfer.tuning == ControllerTuning(usbTransferTimeoutMilliseconds: 750),
        "\(protocolInfo)"
      )
    }
  }

  @Test(arguments: ["XboxGIP", "SonyDualSense", "NintendoSwitch2", "HIDDescriptor"])
  func decodesFrameQueueCapacityForEveryFamily(family: String) throws {
    let record = try decode(
      protocol: ["family": family],
      extra: ["tuning": ["frameQueueCapacity": 8]]
    )
    #expect(record.tuning == ControllerTuning(frameQueueCapacity: 8))
  }

  @Test(
    arguments: [
      ("SonyDualShock4", ["stickDeadzone": 0]), ("SonyDualShock4", ["stickDeadzone": 1]),
      ("SonyDualShock4", ["inputLivenessTimeoutMs": 0]),
      ("NintendoSwitch1", ["hidStartupRecoveryRounds": 11]),
      ("NintendoSwitch1", ["hidStartupRecoveryIntervalMs": 0]),
      ("HIDDescriptor", ["minimumHIDOutputIntervalMs": 60_001]),
      ("HIDDescriptor", ["deadzone": 0.1]), ("HIDDescriptor", [:]),
      ("HIDDescriptor", ["inputLivenessTimeoutMs": 1_000]),
      ("SonyDualSense", ["hidStartupRecoveryRounds": 2]),
      ("XboxGIP", ["hidStartupIntervalMs": 20]),
      ("ValveSteamTriton", ["lizardResendTicks": 0]),
      ("ValveSteamTriton", ["lizardResendTicks": 100_001]),
      ("NintendoSwitch2", ["usbCommandTimeoutMs": 0]),
      ("NintendoSwitch2", ["usbCommandTimeoutMs": 60_001]),
      ("XboxGIP", ["presenceResendReports": 0]),
      ("XboxGIP", ["presenceResendReports": 1_001]),
      ("XboxXUSB", ["presenceResendReports": 16]),
      ("SonyDualShock4", ["adapterDisconnectDelayMs": 0]),
      ("SonyDualShock4", ["adapterDisconnectDelayMs": 60_001]),
      ("XboxGIP", ["usbStartupIntervalMs": -1]),
      ("XboxGIP", ["usbStartupIntervalMs": 60_001]),
      ("XboxGIP", ["usbStartupRetryDelayMs": 0]),
      ("XboxGIP", ["usbStartupRetryDelayMs": 60_001]),
      ("XboxGIP", ["usbTransferTimeoutMs": 0]),
      ("XboxGIP", ["usbTransferTimeoutMs": 60_001]),
      ("XboxXUSB", ["usbTransferTimeoutMs": 0]),
      ("XboxXUSB", ["usbTransferTimeoutMs": 60_001]),
      ("SonyDualSense", ["usbTransferTimeoutMs": 2_000]),
      ("XboxGIP", ["zephyrQuill": 5]),
      ("XboxXUSB", ["zephyrQuill": 5]),
      ("XboxGIP", ["frameQueueCapacity": 0]),
      ("HIDDescriptor", ["frameQueueCapacity": 1_025]),
      ("SonyDualSense", ["frameQueueCapacity": 1.5]),
    ] as [(String, [String: any Sendable])]
  )
  func rejectsTuningOutOfRangeOrOutsideItsFamily(family: String, tuning: [String: any Sendable]) {
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: family == "XboxXUSB"
          ? ["family": family, "variant": "Wired"] : ["family": family],
        extra: ["tuning": tuning]
      )
    }
  }

  @Test(arguments: ["NintendoSwitch2", "NintendoSwitchInputOnly"])
  func rejectsRecoveryTuningForSwitchDriversWithoutRecovery(family: String) throws {
    _ = try decode(protocol: ["family": family])
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: ["family": family],
        extra: ["tuning": ["hidStartupRecoveryRounds": 2]]
      )
    }
  }

  static let vibrationUUID = "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149"
  static let switch2: [String: any Sendable] = [
    "family": "NintendoSwitch2"
  ]

  @Test
  func decodesTheBluetoothLEVibrationCharacteristicOfASwitch2Controller() throws {
    let document = try decode(
      protocol: Self.switch2,
      extra: ["bluetoothLE": ["vibrationCharacteristic": Self.vibrationUUID]]
    )
    #expect(document.bluetoothLE?.vibrationCharacteristic == Self.vibrationUUID)
    #expect(
      try DeviceCatalog.makeRuntimeProfile(document).bluetoothLEVibrationCharacteristic
        == Self.vibrationUUID
    )
  }

  @Test(
    arguments: [
      (["family": "NintendoSwitch1"], ["vibrationCharacteristic": vibrationUUID]),
      (["family": "SonyDualSense"], ["vibrationCharacteristic": vibrationUUID]),
      (switch2, ["vibrationCharacteristic": vibrationUUID.lowercased()]),
      (switch2, ["vibrationCharacteristic": "FA19B0FB"]),
      (switch2, [:]),
      (switch2, ["vibrationCharacteristic": vibrationUUID, "service": vibrationUUID]),
    ] as [([String: any Sendable], [String: any Sendable])]
  )
  func rejectsBluetoothLEOutsideSwitch2OrMalformed(
    protocolInfo: [String: any Sendable],
    bluetoothLE: [String: any Sendable]
  ) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: protocolInfo, extra: ["bluetoothLE": bluetoothLE])
    }
  }

  private static func controllerSchema() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent("Resources/Schemas/controller.schema.json")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private static func descriptionSchema() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = root.appendingPathComponent("Resources/Schemas/protocol-description.schema.json")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private static func enumValues(_ node: Any?) -> [String]? {
    (node as? [String: Any])?["enum"] as? [String]
  }

  /// The Swift value spellings of each enumerated parameter, in declaration order.
  private static let parameterEnums: [String: [String]] = [
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

  private func decode(
    protocol protocolInfo: [String: any Sendable],
    usb: [String: any Sendable]? = nil,
    capabilities: [String: any Sendable]? = nil,
    extra: [String: any Sendable] = [:],
    vendorID: Int = 0x045E
  ) throws -> ControllerRecordDocument {
    var record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": vendorID, "productID": 0x02EA,
      "modes": [["id": "default", "protocol": protocolInfo]],
    ]
    record.merge(extra) { current, _ in current }
    record["usb"] = usb
    record["capabilities"] = capabilities
    return try JSONDecoder().decode(
      ControllerRecordDocument.self,
      from: JSONSerialization.data(withJSONObject: record)
    )
  }
}
