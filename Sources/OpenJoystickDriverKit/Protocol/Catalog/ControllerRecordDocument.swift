import Foundation

/// Strict runtime representation of the one current controller-record contract.
///
/// JSONDecoder normally ignores unknown keys. This decoder instead rejects
/// removed or misspelled fields and requires the exact current schema identity.
struct ControllerRecordDocument: Decodable {
  static let schemaID =
    "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
    + "Resources/Schemas/controller.schema.json"

  let vendorID: Int
  let productID: Int
  let protocolInfo: ProtocolInfo
  let usb: USBOverride?
  let capabilities: ControllerCapabilityDelta
  /// Nil leaves a controller macOS supports to macOS.
  let ownership: ControllerOwnership?
  let rumbleTemplate: RumbleOutputTemplate?
  /// Fixed reports OJD sends when it starts the controller; empty when the record has none.
  let startupWrites: [RecordStartupWrite]
  /// Present exactly for the `hid.report-layout` family.
  let inputLayout: ControllerInputLayout?

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: [
      "$schema", "vendorID", "productID", "protocol", "usb", "capabilities", "ownership", "output",
      "input",
    ])
    let schema = try container.decode(String.self, for: "$schema")
    guard schema == Self.schemaID else {
      throw DecodingError.dataCorruptedError(
        forKey: DocumentKey("$schema"),
        in: container,
        debugDescription: "$schema must identify the current controller contract"
      )
    }
    vendorID = try container.decode(Int.self, for: "vendorID")
    productID = try container.decode(Int.self, for: "productID")
    protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
    usb = try container.decodeOptional(USBOverride.self, for: "usb")
    capabilities =
      try container.decodeOptional(CapabilityDelta.self, for: "capabilities")?.delta ?? .none
    ownership = try container.decodeOptional(String.self, for: "ownership").map { name in
      guard let ownership = ControllerOwnership(rawValue: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: DocumentKey("ownership"),
          in: container,
          debugDescription: "ownership must be macos or ojd"
        )
      }
      return ownership
    }
    let output = try container.decodeOptional(Output.self, for: "output")
    rumbleTemplate = output?.rumble
    startupWrites = output?.startup ?? []
    inputLayout = try container.decodeOptional(InputLayout.self, for: "input")?.layout
    try validateOwnershipAndOutput(codingPath: decoder.codingPath)
    // Only these deltas have a driver that acts on them: GIP drops rumble, DualSense Edge adds
    // exactly its paddles and function buttons.
    let presentAllowed =
      capabilities.presentControls.isEmpty
      || (protocolInfo.protocolID == .sonyDualSense
        && capabilities.presentControls == DualSenseDriver.edgeControls)
    guard !capabilities.rumbleAbsent || protocolInfo.protocolID == .xboxGIP, presentAllowed else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey("capabilities")],
          debugDescription: "capabilities must be deltas their driver declares"
        )
      )
    }
    if let endpoints = usb?.endpoints {
      let defaultEndpoints: (Int, Int)
      switch protocolInfo.protocolID {
      case .xboxXUSB: defaultEndpoints = (129, 1)
      case .xboxXID: defaultEndpoints = (129, 2)
      default: defaultEndpoints = (130, 2)
      }
      guard (endpoints.input, endpoints.output) != defaultEndpoints else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("usb"), DocumentKey("endpoints")],
            debugDescription: "protocol-default endpoints must be omitted"
          )
        )
      }
    }
  }

  /// macOS cannot serve a raw-USB family, startup writes go to HID controllers, only a driver that
  /// encodes rumble from a template may name one, and the report-layout family alone has, and
  /// needs, an input layout.
  private func validateOwnershipAndOutput(codingPath: [any CodingKey]) throws {
    let rawUSB = protocolInfo.protocolID.usesRawUSB(storedVariant: protocolInfo.protocolVariant)
    if ownership != nil, rawUSB {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("ownership")],
          debugDescription: "ownership applies only to HID controllers"
        )
      )
    }
    if !startupWrites.isEmpty, rawUSB {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("output"), DocumentKey("startup")],
          debugDescription: "startup writes apply only to HID controllers"
        )
      )
    }
    if (inputLayout != nil) != (protocolInfo.protocolID == .hidReportLayout) {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("input")],
          debugDescription: "an input layout is required for hid.report-layout and only there"
        )
      )
    }
    if rumbleTemplate != nil, !protocolInfo.protocolID.encodesRumbleTemplate {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey("output"), DocumentKey("rumble")],
          debugDescription: "rumble templates require a driver that encodes them"
        )
      )
    }
  }

  struct RumbleTemplate: Decodable {
    let template: RumbleOutputTemplate

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let motors = RumbleOutputTemplate.templateMotors
      try container.rejectUnknown(allowed: Set(["report"] + motors.map(\.rawValue)))
      let report = try container.decode(TemplateReport.self, for: "report").report
      var motorBytes: [PhysicalRumbleMotor: Int] = [:]
      for motor in motors {
        motorBytes[motor] = try container.decodeOptional(TemplateByte.self, for: motor.rawValue)?
          .byte
      }
      do {
        template = try RumbleOutputTemplate(report: report, motorBytes: motorBytes)
      } catch {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: error.description)
        )
      }
    }
  }

  struct TemplateReport: Decodable {
    let report: ControllerTemplateReport

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["kind", "id", "length"])
      let kind = try container.decode(String.self, for: "kind")
      let reportID = try container.decode(Int.self, for: "id")
      let length = try container.decode(Int.self, for: "length")
      guard kind == "output" || kind == "feature", let id = UInt8(exactly: reportID) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "report must be an output or feature report with ID 0...255"
          )
        )
      }
      report = ControllerTemplateReport(
        kind: kind == "output" ? .output : .feature,
        reportID: id,
        length: length
      )
    }
  }

  struct TemplateByte: Decodable {
    let byte: Int

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte"])
      byte = try container.decode(Int.self, for: "byte")
    }
  }

  struct ProtocolInfo: Decodable {
    let protocolID: PhysicalProtocolID
    /// Nil unless the family stores its variant (``PhysicalProtocolID/storesVariant``).
    let protocolVariant: PhysicalProtocolVariantID?
    let quirks: [ControllerQuirk]
    /// Named GIP initialization actions; nil selects the driver's default sequence.
    let initialization: [GIPStartupPacket]?
    let keepAliveEnabled: Bool?
    /// The named assembly policy; its vocabulary is empty, so every name fails.
    let assembly: ControllerAssemblyPolicy?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "family", "variant", "quirks", "initialization", "keepAlive", "assembly",
      ])
      let family = try container.decode(String.self, for: "family")
      let variantName = try container.decodeOptional(String.self, for: "variant")
      guard let protocolID = PhysicalProtocolID(rawValue: family) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "unknown family \(family)")
        )
      }
      let variant = variantName.flatMap(PhysicalProtocolVariantID.init(rawValue:))
      // Only families whose variant transport cannot decide store it, and it must be theirs.
      guard protocolID.storesVariant == (variantName != nil),
        variantName == nil || variant.map(protocolID.variants.contains) == true
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "variant must be a stored variant of family \(family)"
          )
        )
      }
      self.protocolID = protocolID
      protocolVariant = variant
      quirks = try container.decodeUniqueList(ControllerQuirk.self, for: "quirks") ?? []
      initialization = try container.decodeUniqueList(GIPStartupPacket.self, for: "initialization")
      keepAliveEnabled = try container.decodeOptional(Bool.self, for: "keepAlive")
      if let name = try container.decodeOptional(String.self, for: "assembly") {
        guard let policy = ControllerAssemblyPolicy(name: name) else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "unknown assembly \(name)")
          )
        }
        assembly = policy
      } else {
        assembly = nil
      }
      try validate(codingPath: decoder.codingPath)
    }

    private func validate(codingPath: [any CodingKey]) throws {
      let violation: String? =
        if !quirks.allSatisfy({ $0.protocolID == protocolID }) {
          "quirks must be declared by the selected driver"
        } else if quirks.contains(.joyConLeft) && quirks.contains(.joyConRight) {
          "Joy-Con layout must select one side"
        } else if quirks.contains(.inputOnly) && quirks.count != 1 {
          "a Switch input-only pad has no Joy-Con layout"
        } else if quirks.contains(.bluetoothOnly) && quirks.count != 1 {
          "a Bluetooth-only Switch pad selects no other layout"
        } else if quirks.contains(.gameCube) && !quirks.contains(.switch2) {
          "the GameCube layout is a Switch 2 controller"
        } else if quirks.contains(.gameCube)
          && (quirks.contains(.joyConLeft) || quirks.contains(.joyConRight))
        {
          "a Switch 2 row selects one layout"
        } else if protocolID == .valveSteamController && quirks.count > 1 {
          "a Steam Controller row selects at most one hardware generation"
        } else if quirks.contains(.neptune) && protocolVariant != .wired {
          "the Steam Deck controller is an internal USB device"
        } else if protocolID == .vendorGameSir && protocolVariant == .usb && !quirks.isEmpty {
          "GameSir vendor USB declares no quirks"
        } else if protocolVariant == .enhancedHID && quirks.count != 1 {
          // An unknown model must not receive a guessed lighting-memory layout.
          "GameSir enhanced HID must select exactly one model quirk"
        } else if initialization != nil && protocolID != .xboxGIP {
          "initialization actions must be declared by the selected driver"
        } else if keepAliveEnabled != nil && protocolID != .xboxGIP {
          "keep-alive policy requires the GIP driver"
        } else { nil }
      if let violation {
        throw DecodingError.dataCorrupted(
          .init(codingPath: codingPath, debugDescription: violation)
        )
      }
    }
  }

  /// Capability corrections against the bound parser's declared defaults.
  struct CapabilityDelta: Decodable {
    let delta: ControllerCapabilityDelta

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["absent", "present", "rumble"])
      let absent = Set(try container.decodeUniqueList(ControlID.self, for: "absent") ?? [])
      let present = Set(try container.decodeUniqueList(ControlID.self, for: "present") ?? [])
      let rumble = try container.decodeOptional(String.self, for: "rumble")
      guard !container.allKeys.isEmpty, absent.isDisjoint(with: present),
        rumble == nil || rumble == "absent"
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "capabilities must be nonempty, disjoint, and declare rumble only as absent"
          )
        )
      }
      delta = ControllerCapabilityDelta(
        absentControls: absent,
        presentControls: present,
        rumbleAbsent: rumble != nil
      )
    }
  }

  struct USBOverride: Decodable {
    let configuration: String?
    let postHandshakeSettleMilliseconds: Int?
    let endpoints: Endpoints?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["configuration", "postHandshakeSettleMs", "endpoints"])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "usb must not be empty")
        )
      }
      configuration = try container.decodeOptional(String.self, for: "configuration")
      postHandshakeSettleMilliseconds = try container.decodeOptional(
        Int.self,
        for: "postHandshakeSettleMs"
      )
      endpoints = try container.decodeOptional(Endpoints.self, for: "endpoints")
      guard postHandshakeSettleMilliseconds.map({ (1...60_000).contains($0) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("postHandshakeSettleMs")],
            debugDescription: "postHandshakeSettleMs must be in 1...60000"
          )
        )
      }
    }
  }

  struct Endpoints: Decodable {
    let input: Int
    let output: Int

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["in", "out"])
      input = try container.decode(Int.self, for: "in")
      output = try container.decode(Int.self, for: "out")
      guard DeviceTransportProfile.inputEndpointRange.contains(input),
        DeviceTransportProfile.outputEndpointRange.contains(output)
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "endpoints must use IN 128...255 and OUT 1...127"
          )
        )
      }
    }
  }
}

/// A coding key for any field name, so the strict decoders can name and reject fields.
struct DocumentKey: CodingKey, Hashable {
  let stringValue: String
  let intValue: Int? = nil

  init(_ value: String) { stringValue = value }
  init?(stringValue: String) { self.init(stringValue) }
  init?(intValue: Int) { self.init(String(intValue)) }
}

extension KeyedDecodingContainer where Key == DocumentKey {
  func decode<T: Decodable>(_ type: T.Type, for key: String) throws -> T {
    try decode(type, forKey: DocumentKey(key))
  }

  func decodeOptional<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
    let codingKey = DocumentKey(key)
    guard contains(codingKey) else { return nil }
    guard try !decodeNil(forKey: codingKey) else {
      throw DecodingError.valueNotFound(
        type,
        .init(codingPath: codingPath + [codingKey], debugDescription: "null is not permitted")
      )
    }
    return try decode(type, forKey: codingKey)
  }

  /// Decodes a nonempty list of unique current identifiers; unknown values fail.
  func decodeUniqueList<Value: RawRepresentable & Hashable>(
    _ type: Value.Type,
    for key: String
  ) throws -> [Value]? where Value.RawValue == String {
    guard let names = try decodeOptional([String].self, for: key) else { return nil }
    let values = names.compactMap(Value.init(rawValue:))
    guard !values.isEmpty, values.count == names.count, Set(values).count == values.count else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must contain unique, current, nonempty values"
        )
      )
    }
    return values
  }

  func rejectUnknown(allowed: Set<String>) throws {
    let unknown = Set(allKeys.map(\.stringValue)).subtracting(allowed).sorted()
    guard unknown.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath,
          debugDescription: "unknown field(s): \(unknown.joined(separator: ", "))"
        )
      )
    }
  }
}
