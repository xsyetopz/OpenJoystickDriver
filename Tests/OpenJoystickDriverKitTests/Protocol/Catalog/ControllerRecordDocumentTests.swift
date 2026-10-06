import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordDocumentTests {
  @Test
  func decodesCurrentVocabulary() throws {
    let document = try decode(
      protocol: [
        "family": "xbox.gip", "quirks": ["share-offset"],
        "initialization": ["xbox.gip/hori-ack", "xbox.gip/power-on"],
      ],
      usb: ["configuration": "set1-before-claim"],
      capabilities: ["absent": ["left-trigger", "right-trigger"], "rumble": "absent"]
    )

    #expect(document.protocolInfo.protocolID == .xboxGIP)
    #expect(document.protocolInfo.protocolVariant == nil)
    #expect(document.protocolInfo.quirks == [.shareOffset])
    #expect(document.protocolInfo.initialization == [.horiAck, .powerOn])
    #expect(
      document.capabilities
        == ControllerCapabilityDelta(
          absentControls: [.leftTrigger, .rightTrigger],
          presentControls: [],
          rumbleAbsent: true
        )
    )
    #expect(document.usb?.configuration == "set1-before-claim")
  }

  @Test
  func decodesGameSirModelQuirks() throws {
    for quirk in [ControllerQuirk.innerGrips, .lightingSlots] {
      let document = try decode(protocol: [
        "family": "vendor.gamesir", "variant": "enhanced-hid", "quirks": [quirk.rawValue],
      ])
      #expect(document.protocolInfo.protocolVariant == .enhancedHID)
      #expect(document.protocolInfo.quirks == [quirk])
    }
  }

  @Test
  func decodesHIDDescriptorLayoutQuirks() throws {
    for quirk in [ControllerQuirk.wr007, .scufEnvision, .zRzBrakeLeft, .dragonRise] {
      let document = try decode(protocol: ["family": "hid.descriptor", "quirks": [quirk.rawValue]])
      #expect(document.protocolInfo.quirks == [quirk])
    }
  }

  @Test
  func decodesThirdPartyDualSenseModelQuirks() throws {
    let quirks: [ControllerQuirk] = [
      .thirdParty, .unprobedSensors, .unprobedTouchpad, .forcedVibration, .receiver,
    ]
    let document = try decode(
      protocol: ["family": "sony.dualsense", "quirks": quirks.map(\.rawValue)],
      vendorID: 0x1532
    )
    #expect(document.protocolInfo.quirks == quirks)
  }

  @Test
  func rejectsDualSenseModelQuirksWithoutTheThirdPartyQuirk() {
    for vendorID in [0x054C, 0x1532] {
      #expect(throws: DecodingError.self) {
        try decode(
          protocol: ["family": "sony.dualsense", "quirks": ["receiver"]],
          vendorID: vendorID
        )
      }
    }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter(\.storesVariant))
  func decodesEveryStoredVariant(family: PhysicalProtocolID) throws {
    for variant in family.variants {
      var protocolInfo: [String: any Sendable] = [
        "family": family.rawValue, "variant": variant.rawValue,
      ]
      // Enhanced HID rows must name their model quirk.
      if variant == .enhancedHID { protocolInfo["quirks"] = ["inner-grips"] }
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
      try decode(protocol: ["family": family.rawValue, "variant": "usb"], extra: extra)
    }
  }

  @Test(
    arguments: [
      ["driver": "GIP", "variant": "xboxOne"], ["driver": "GIP"], ["family": "GIP"],
      ["family": "xbox.gip", "variant": "xboxOne"], ["family": "xbox.xusb", "variant": "xbox360"],
      ["family": "xbox.xusb", "variant": "dongle"], ["family": "xbox.xusb:wired"],
      ["family": "vendor.gamesir", "variant": "gameSirG7ProUSB"],
      ["family": "vendor.gamesir", "variant": "enhanced-hid-8k"],
      ["family": "xbox.gip", "quirks": ["inner-grips"]],
      ["family": "vendor.gamesir", "variant": "enhanced-hid", "quirks": ["innerGrips"]],
      ["family": "vendor.gamesir", "variant": "usb", "quirks": ["inner-grips"]],
      ["family": "vendor.gamesir", "variant": "usb", "quirks": ["lighting-slots"]],
      ["family": "vendor.gamesir", "variant": "enhanced-hid"],
      ["family": "vendor.gamesir", "variant": "enhanced-hid", "quirks": [String]()],
      [
        "family": "vendor.gamesir", "variant": "enhanced-hid",
        "quirks": ["inner-grips", "lighting-slots"],
      ], ["family": "valve.steam-controller", "variant": "wired", "quirks": ["wirelessReceiver"]],
      ["family": "xbox.adaptive-joystick"], ["family": "xbox.gip", "quirks": ["shareOffset"]],
      ["family": "xbox.gip", "quirks": ["inputOnly"]],
      ["family": "xbox.gip", "quirks": ["triggersToButtons"]],
      ["family": "xbox.xid", "variant": "gamepad", "quirks": ["sticksToNull"]],
      ["family": "xbox.xusb", "variant": "wired", "quirks": ["dpadToButtons"]],
      ["family": "xbox.xusb", "variant": "wired", "quirks": ["share-offset"]],
      ["family": "sony.dualsense", "quirks": ["edgeButtons"]],
      ["family": "sony.dualsense", "quirks": ["touchpad"]],
      ["family": "valve.steam-controller", "variant": "wired", "quirks": ["lizardMode"]],
      ["family": "nintendo.switch1", "quirks": ["joyConLeft"]],
      ["family": "nintendo.switch1", "quirks": ["joy-con-left", "joy-con-right"]],
      ["family": "nintendo.switch1", "quirks": ["input-only", "joy-con-left"]],
      ["family": "nintendo.switch1", "quirks": ["bluetooth-only", "joy-con-left"]],
      ["family": "nintendo.switch1", "quirks": ["switch-2", "bluetooth-only"]],
      ["family": "nintendo.switch1", "quirks": ["gamecube"]],
      ["family": "nintendo.switch1", "quirks": ["switch-2", "gamecube", "joy-con-left"]],
      ["family": "vendor.ps3-third-party", "quirks": ["input-only"]],
      ["family": "valve.steam-controller", "variant": "wired", "quirks": ["triton", "neptune"]],
      ["family": "valve.steam-controller", "variant": "bluetooth-le", "quirks": ["neptune"]],
      ["family": "sony.dualshock4", "quirks": ["gyro"]],
      ["family": "sony.dualshock4", "quirks": ["wireless-adapter", "strikepad"]],
      ["family": "sony.dualshock4", "quirks": ["shield-2015"]],
      ["family": "vendor.nvidia-shield", "quirks": ["factory-calibration"]],
      ["family": "hid.descriptor", "quirks": ["wr007", "dragonrise"]],
      ["family": "hid.descriptor", "quirks": ["wireless-adapter"]],
      ["family": "sony.dualshock4", "quirks": ["wr007"]],
      ["family": "sony.dualsense", "quirks": ["wireless-adapter"]],
      ["family": "xbox.gip", "startupPackets": ["xbox.gip/power-on"]],
      ["family": "xbox.gip", "initialization": ["powerOn"]],
      ["family": "xbox.gip", "initialization": [String]()],
      ["family": "xbox.xusb", "variant": "wired", "initialization": ["xbox.gip/power-on"]],
      ["family": "xbox.xusb", "variant": "wired", "keepAlive": false],
    ] as [[String: any Sendable]]
  )
  func rejectsRemovedProtocolVocabulary(protocolInfo: [String: any Sendable]) {
    #expect(throws: DecodingError.self) { try decode(protocol: protocolInfo) }
  }

  @Test
  func rejectsTheRemovedTransportField() {
    for transport in ["usb", "hid"] {
      #expect(throws: DecodingError.self) {
        try decode(protocol: ["family": "xbox.gip"], extra: ["transport": transport])
      }
    }
  }

  @Test(
    arguments: [
      [:], ["absent": [String]()], ["absent": ["left-trigger", "left-trigger"]],
      ["absent": ["leftTrigger"]], ["present": ["trackpad"]],
      ["absent": ["guide"], "present": ["guide"]], ["rumble": "present"],
      ["rumble": "absent", "controls": ["guide"]],
    ] as [[String: any Sendable]]
  )
  func rejectsInvalidCapabilities(capabilities: [String: any Sendable]) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "xbox.gip"], capabilities: capabilities)
    }
  }

  @Test
  func presentControlsAreOnlyTheDualSenseEdgeSet() throws {
    let edge = ["paddle-left-1", "paddle-right-1", "auxiliary-1", "auxiliary-2"]
    let dualSense: [String: any Sendable] = ["family": "sony.dualsense"]
    let document = try decode(protocol: dualSense, capabilities: ["present": edge])
    #expect(document.capabilities.presentControls == DualSenseDriver.edgeControls)
    #expect(throws: DecodingError.self) {
      try decode(protocol: dualSense, capabilities: ["present": Array(edge.prefix(2))])
    }
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "xbox.gip"], capabilities: ["present": ["paddle-left-1"]])
    }
  }

  @Test
  func rejectsRumbleAbsenceForDriversThatDoNotDeclareIt() {
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: ["family": "xbox.xusb", "variant": "wired"],
        capabilities: ["rumble": "absent"]
      )
    }
  }

  @Test
  func rejectsUSBInterfaceOverride() {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "xbox.gip"], usb: ["interface": 1])
    }
  }

  /// The assembly vocabulary is empty until a row with multi-interface evidence adds a policy.
  @Test(arguments: ["", "steam-dongle", "flydigi-xinput-vendor", "joy-con-pair"])
  func rejectsEveryAssemblyPolicy(name: String) {
    #expect(ControllerAssemblyPolicy(name: name) == nil)
    #expect(throws: DecodingError.self) {
      try decode(protocol: [
        "family": "valve.steam-controller", "variant": "dongle", "assembly": name,
      ])
    }
  }

  @Test
  func noCatalogRowNamesAnAssemblyPolicy() {
    let registry = ProtocolDriverRegistry()
    for identifier in registry.hidIdentifiers + registry.rawUSBIdentifiers {
      let record = registry.record(for: identifier)
      #expect(record?.assemblyPolicy == nil)
      let binding = ProtocolBinding(
        protocolID: record?.physicalProtocolID ?? .hidDescriptor,
        variant: record?.physicalProtocolVariant,
        accessBackend: .ioHID,
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
    #expect(Self.enumValues(definitions["controlID"]) == ControlID.allCases.map(\.rawValue))
    #expect(
      Self.enumValues(definitions["gipInitializationAction"])
        == GIPStartupPacket.allCases.map(\.rawValue)
    )

    // Every implemented family has catalog rows, so the schema lists all of them.
    let protocolSchema = try #require(definitions["protocol"] as? [String: Any])
    let properties = try #require(protocolSchema["properties"] as? [String: Any])
    #expect(Self.enumValues(properties["family"]) == PhysicalProtocolID.allCases.map(\.rawValue))
    #expect(
      Self.enumValues(properties["assembly"]) == ControllerAssemblyPolicy.allCases.map(\.name)
    )
    let storedVariants = PhysicalProtocolID.allCases.filter(\.storesVariant).flatMap(\.variants)
    #expect(
      Set(Self.enumValues(properties["variant"]) ?? []) == Set(storedVariants.map(\.rawValue))
    )

    let branches = try #require(protocolSchema["allOf"] as? [[String: Any]])
    var declaredQuirks: [String] = []
    var familiesWithVariants: [PhysicalProtocolID] = []
    for branch in branches {
      guard let name = Self.familyConstant(branch), let family = PhysicalProtocolID(rawValue: name),
        let then = branch["then"] as? [String: Any],
        let thenProperties = then["properties"] as? [String: Any]
      else { continue }
      if let variants = Self.enumValues(thenProperties["variant"]) {
        #expect(variants == family.variants.map(\.rawValue), "\(name)")
        familiesWithVariants.append(family)
      }
      if let quirks = Self.quirkValues(thenProperties["quirks"]) {
        #expect(
          quirks == ControllerQuirk.allCases.filter { $0.protocolID == family }.map(\.rawValue),
          "\(name)"
        )
        declaredQuirks += quirks
      }
    }
    #expect(familiesWithVariants == PhysicalProtocolID.allCases.filter(\.storesVariant))
    #expect(declaredQuirks.sorted() == ControllerQuirk.allCases.map(\.rawValue).sorted())
  }

  /// An input layout belongs to the `hid.report-layout` family, which cannot run without one.
  @Test
  func inputLayoutIsRequiredExactlyForTheReportLayoutFamily() throws {
    let document = try decode(
      protocol: ["family": "hid.report-layout"],
      extra: ["input": Self.minimalInput]
    )
    #expect(document.inputLayout?.controls == [.faceSouth])
    #expect(throws: DecodingError.self) { try decode(protocol: ["family": "hid.report-layout"]) }
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": "hid.descriptor"], extra: ["input": Self.minimalInput])
    }
  }

  /// The smallest valid `input` section: one button in a one-byte report.
  static let minimalInput: [String: any Sendable] = [
    "report": ["length": 1] as [String: Int],
    "buttons": [["control": "face-south", "byte": 0, "mask": 1] as [String: any Sendable]],
  ]

  @Test
  func decodesTuningWhereADriverReadsIt() throws {
    let ds4 = try decode(
      protocol: ["family": "sony.dualshock4"],
      extra: ["tuning": ["stickDeadzone": 0.05, "inputLivenessTimeoutMs": 1_500]]
    )
    #expect(
      ds4.tuning
        == ControllerTuning(stickDeadzone: 0.05, inputLivenessTimeoutMilliseconds: 1_500)
    )
    let switch1 = try decode(
      protocol: ["family": "nintendo.switch1"],
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
    #expect(try decode(protocol: ["family": "xbox.gip"]).tuning == .none)
  }

  @Test(
    arguments: [
      ("sony.dualshock4", ["stickDeadzone": 0]), ("sony.dualshock4", ["stickDeadzone": 1]),
      ("sony.dualshock4", ["inputLivenessTimeoutMs": 0]),
      ("nintendo.switch1", ["hidStartupRecoveryRounds": 11]),
      ("nintendo.switch1", ["hidStartupRecoveryIntervalMs": 0]),
      ("hid.descriptor", ["minimumHIDOutputIntervalMs": 60_001]),
      ("hid.descriptor", ["deadzone": 0.1]), ("hid.descriptor", [:]),
      ("hid.descriptor", ["inputLivenessTimeoutMs": 1_000]),
      ("sony.dualsense", ["hidStartupRecoveryRounds": 2]),
      ("xbox.gip", ["hidStartupIntervalMs": 20]),
    ] as [(String, [String: any Sendable])]
  )
  func rejectsTuningOutOfRangeOrOutsideItsFamily(family: String, tuning: [String: any Sendable]) {
    #expect(throws: DecodingError.self) {
      try decode(protocol: ["family": family], extra: ["tuning": tuning])
    }
  }

  @Test(arguments: [["switch-2"], ["input-only"]])
  func rejectsRecoveryTuningForSwitchDriversWithoutRecovery(quirks: [String]) throws {
    _ = try decode(protocol: ["family": "nintendo.switch1", "quirks": quirks])
    #expect(throws: DecodingError.self) {
      try decode(
        protocol: ["family": "nintendo.switch1", "quirks": quirks],
        extra: ["tuning": ["hidStartupRecoveryRounds": 2]]
      )
    }
  }

  static let vibrationUUID = "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149"
  static let switch2: [String: any Sendable] = [
    "family": "nintendo.switch1", "quirks": ["switch-2"],
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
      (["family": "nintendo.switch1"], ["vibrationCharacteristic": vibrationUUID]),
      (["family": "sony.dualsense"], ["vibrationCharacteristic": vibrationUUID]),
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
    let url = root.appendingPathComponent("Resources/Schemas/v1beta1/controller.schema.json")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private static func enumValues(_ node: Any?) -> [String]? {
    (node as? [String: Any])?["enum"] as? [String]
  }

  /// The quirk names a family's `quirks` schema admits, in declaration order: the item enum,
  /// or the union over `anyOf` branches of their item enums and `prefixItems` values.
  private static func quirkValues(_ node: Any?) -> [String]? {
    guard let schema = node as? [String: Any] else { return nil }
    let branches = (schema["anyOf"] as? [[String: Any]]) ?? [schema]
    var names: [String] = []
    for branch in branches {
      let slots = [branch["items"] as Any] + ((branch["prefixItems"] as? [Any]) ?? [])
      for slot in slots {
        let slot = slot as? [String: Any]
        let values = enumValues(slot) ?? (slot?["const"] as? String).map { [$0] } ?? []
        names += values.filter { !names.contains($0) }
      }
    }
    return names.isEmpty ? nil : names
  }

  private static func familyConstant(_ branch: [String: Any]) -> String? {
    let condition = branch["if"] as? [String: Any]
    let properties = condition?["properties"] as? [String: Any]
    return (properties?["family"] as? [String: Any])?["const"] as? String
  }

  private func decode(
    protocol protocolInfo: [String: any Sendable],
    usb: [String: any Sendable]? = nil,
    capabilities: [String: any Sendable]? = nil,
    extra: [String: any Sendable] = [:],
    vendorID: Int = 0x045E
  ) throws -> ControllerRecordDocument {
    var record: [String: Any] = [
      "$schema": ControllerRecordDocument.schemaID, "vendorID": vendorID, "productID": 0x02EA,
      "protocol": protocolInfo,
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
