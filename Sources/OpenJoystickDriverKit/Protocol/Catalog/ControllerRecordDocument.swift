import Foundation

/// Strict runtime representation of the one current controller-record contract.
///
/// JSONDecoder normally ignores unknown keys. This decoder instead rejects
/// removed or misspelled fields and requires the `apiVersion` and `kind` of the controller
/// contract.
struct ControllerRecordDocument: Decodable {
  /// The `kind` of a controller record.
  static let kind = "Controller"

  /// The USB vendor ID of the model.
  let vendorID: Int
  /// The USB product ID of the model.
  let productID: Int
  /// The `default` mode, which runs when no other mode matches; nil when the record has none, so a
  /// device that matches no mode is unsupported.
  let defaultMode: ModeDocument?
  /// The mode that gives the record-level profile: the `default` mode, else the first mode.
  var baseMode: ModeDocument { defaultMode ?? modes[0] }
  /// The protocol of the base mode.
  var protocolInfo: ProtocolInfo { baseMode.protocolInfo }
  /// The record's modes: `default` and the alternatives of an HID controller, which are tried in
  /// order.
  let modes: [ModeDocument]
  /// The model's USB product string, verbatim; nil when the record names none.
  let name: String?
  /// The serial number that this model's firmware reports when it has none of its own; nil when
  /// the record names none.
  let placeholderSerial: String?
  /// The USB configuration and endpoint overrides; nil when the record sets none.
  let usb: USBOverride?
  /// Present exactly for Switch 2 controllers that connect over Bluetooth LE.
  let bluetoothLE: BluetoothLE?
  /// The corrections to the family's declared capabilities.
  let capabilities: ControllerCapabilityDelta
  /// Nil leaves a controller macOS supports to macOS.
  let server: ControllerServer?
  /// Set only on raw-USB records that OJD's USB extension serves.
  let route: ControllerRecordRoute?
  /// Whether Apple's own driver extension holds the controller's USB interface.
  let heldByAppleDriver: Bool
  /// Present for a `HIDReportLayout` record and for any record that holds `input.layouts`.
  let inputLayouts: ControllerInputLayouts?
  /// Present only for the `HIDDescriptor` family, which then replaces the description's map.
  let hidUsageMap: HIDUsageMap?
  /// The tuning values the record sets.
  let tuning: ControllerTuning
  /// The accepted community validations; empty when the record has none.
  let validations: [ControllerValidation]

  /// Decodes the record's `apiVersion`, `kind`, IDs, modes, sections and tuning; an unknown key, a
  /// wrong `kind` or an invalid combination of sections is rejected.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    let apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
    let documentKind = try container.decodeOptional(String.self, for: "kind")
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: apiVersion,
      kind: documentKind,
      expected: Self.kind
    ) {
      if problem.code != nil { throw problem }
      throw DecodingError.dataCorruptedError(
        forKey: DocumentKey("kind"),
        in: container,
        debugDescription: problem.message
      )
    }
    try container.rejectUnknown(allowed: [
      "apiVersion", "kind", "vendorID", "productID", "modes", "name", "placeholderSerial", "usb",
      "bluetoothLE", "capabilities", "server", "route", "heldByAppleDriver", "input", "tuning",
      "validations",
    ])
    vendorID = try container.decode(Int.self, for: "vendorID")
    productID = try container.decode(Int.self, for: "productID")
    modes = try container.decode([ModeDocument].self, for: "modes")
    guard !modes.isEmpty else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey("modes")],
          debugDescription: "modes must not be empty"
        )
      )
    }
    defaultMode = modes.first(where: \.isDefault)
    if modes.allSatisfy({ $0.idle != nil }) {
      let controlSections: Set<String> = [
        "usb", "bluetoothLE", "capabilities", "server", "route", "heldByAppleDriver", "input",
        "tuning", "validations",
      ]
      guard container.allKeys.allSatisfy({ !controlSections.contains($0.stringValue) }) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("modes")],
            debugDescription:
              "a record whose modes are all idle has no section that serves controls"
          )
        )
      }
    }
    name = try container.decodeOptional(String.self, for: "name")
    placeholderSerial = try container.decodeOptional(String.self, for: "placeholderSerial")
    for (key, value) in [("name", name), ("placeholderSerial", placeholderSerial)]
    where value?.isEmpty == true {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must not be empty"
        )
      )
    }
    usb = try container.decodeOptional(USBOverride.self, for: "usb")
    bluetoothLE = try container.decodeOptional(BluetoothLE.self, for: "bluetoothLE")
    capabilities =
      try container.decodeOptional(CapabilityDelta.self, for: "capabilities")?.delta ?? .none
    server = try container.decodeOptional(String.self, for: "server").map { name in
      guard let parsed = ControllerServer(rawValue: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: DocumentKey("server"),
          in: container,
          debugDescription: "server must be System or OJD"
        )
      }
      return parsed
    }
    route = try container.decodeOptional(String.self, for: "route").map { name in
      guard let parsed = ControllerRecordRoute(rawValue: name) else {
        throw DecodingError.dataCorruptedError(
          forKey: DocumentKey("route"),
          in: container,
          debugDescription: "route must be ExtensionOwned"
        )
      }
      return parsed
    }
    heldByAppleDriver = try container.decodeOptional(Bool.self, for: "heldByAppleDriver") ?? false
    let input = try container.decodeOptional(Input.self, for: "input")
    inputLayouts = input?.layouts
    hidUsageMap = input?.usageMap
    guard input?.shapes.isEmpty ?? true else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + [DocumentKey("input")],
          debugDescription: "descriptorShapes belong to a protocol description"
        )
      )
    }
    tuning = try container.decodeOptional(Tuning.self, for: "tuning")?.tuning ?? .none
    validations =
      try container.decodeOptional([ControllerValidation].self, for: "validations") ?? []
    if let index = validations.firstIndex(where: { validation in
      !modes.contains { $0.id == validation.modeID }
    }) {
      let path = ["validations", String(index), "mode"].map(DocumentKey.init)
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath + path,
          debugDescription: "mode \(validations[index].modeID) is not a mode of the record"
        )
      )
    }
    try validateTuning(codingPath: decoder.codingPath)
    try validateTransportSections(codingPath: decoder.codingPath)
    try validateModes(codingPath: decoder.codingPath)
  }

  /// Only the deltas a family's description declares have a driver that acts on them.
  ///
  /// The rule holds per capability: each one must be declared by the family of at least one mode,
  /// so a record may hold modes of two drivers when each capability belongs to one of them. A mode
  /// whose driver does not declare a capability does not act on it.
  func capabilitiesDeclared(byAnyOf protocolIDs: [PhysicalProtocolID]) -> Bool {
    let rules = protocolIDs.map { $0.protocolDescription.recordCapabilities }
    return
      (capabilities.presentControls.isEmpty
      || rules.contains { $0.presentControls == capabilities.presentControls })
      && (!capabilities.rumbleAbsent || rules.contains(where: \.rumbleAbsent))
  }

  /// The rumble template of a record, as a `report` target with its motor fields.
  struct RumbleTemplate: Decodable {
    /// The decoded template.
    let template: RumbleOutputTemplate

    /// Decodes `report`, `bytes`, `counter`, `resendIntervalMilliseconds` and one field per
    /// template motor; an unknown key or a template that `RumbleOutputTemplate` rejects is
    /// rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      let motors = RumbleOutputTemplate.templateMotors
      try container.rejectUnknown(
        allowed: Set(
          ["report", "bytes", "counter", "resendIntervalMilliseconds"] + motors.map(\.recordKey)
        )
      )
      let target = try container.decode(RumbleTarget.self, for: "report").target
      var fields: [PhysicalRumbleMotor: RumbleOutputTemplate.MotorField] = [:]
      for motor in motors {
        fields[motor] = try container.decodeOptional(MotorField.self, for: motor.recordKey)?.field
      }
      do {
        let bytes =
          container.contains(DocumentKey("bytes"))
          ? try HexBytes.decode(container, for: "bytes", what: "rumble template") : nil
        template = try RumbleOutputTemplate(
          target: target,
          bytes: bytes,
          motors: fields,
          counterByte: try container.decodeOptional(TemplateByte.self, for: "counter")?.byte,
          resendIntervalMilliseconds: try container.decodeOptional(
            Int.self,
            for: "resendIntervalMilliseconds"
          )
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(
          problem.context(at: decoder.codingPath)
        )
      }
    }
  }

  /// A rumble template's report: a HID output or feature report, or a raw-USB packet of
  /// `length` bytes to the family's output endpoint.
  struct RumbleTarget: Decodable {
    /// The decoded target.
    let target: RumbleOutputTemplate.Target

    /// Decodes a `USB` target with `length`, or a HID target with `kind`, `id` and `length`; an
    /// unknown key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      if try container.decode(String.self, for: "kind") == "USB" {
        try container.rejectUnknown(allowed: ["kind", "length"])
        target = .usb(length: try container.decode(Int.self, for: "length"))
      } else {
        target = .hid(try TemplateReport(from: decoder).report)
      }
    }
  }

  /// Where a rumble template writes one motor: its first byte and the value's encoding.
  struct MotorField: Decodable {
    /// The decoded motor field.
    let field: RumbleOutputTemplate.MotorField

    /// Decodes `byte` and an optional `encoding`; an unknown key or an unknown encoding is
    /// rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte", "encoding"])
      let encodingName = try container.decodeOptional(String.self, for: "encoding")
      guard let encoding = encodingName.map(RumbleMotorEncoding.init(rawValue:)) ?? .uInt8 else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "a rumble motor encoding is "
              + RumbleMotorEncoding.allCases.map(\.rawValue).joined(separator: ", ")
          )
        )
      }
      field = .init(byte: try container.decode(Int.self, for: "byte"), encoding: encoding)
    }
  }

  /// A HID report named by `kind`, `id` and `length`.
  struct TemplateReport: Decodable {
    /// The decoded report.
    let report: ControllerTemplateReport

    /// Decodes `kind`, `id` and `length`; an unknown key or kind is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["kind", "id", "length"])
      let reportKind = try container.decode(String.self, for: "kind")
      let reportID = try container.decode(Int.self, for: "id")
      let length = try container.decode(Int.self, for: "length")
      guard reportKind == "Output" || reportKind == "Feature",
        let id = UInt8(exactly: reportID)
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "report must be an output or feature report with ID 0...255"
          )
        )
      }
      report = ControllerTemplateReport(
        kind: reportKind == "Output" ? .output : .feature,
        reportID: id,
        length: length
      )
    }
  }

  /// A byte offset named by `byte`.
  struct TemplateByte: Decodable {
    /// The decoded offset.
    let byte: Int

    /// Decodes `byte`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["byte"])
      byte = try container.decode(Int.self, for: "byte")
    }
  }

  /// A mode's `protocol` section.
  struct ProtocolInfo: Decodable {
    /// The protocol family the mode runs.
    let protocolID: PhysicalProtocolID
    /// Nil unless the family stores its variant (``PhysicalProtocolID/storesVariant``).
    let protocolVariant: PhysicalProtocolVariantID?
    /// The protocol parameters the mode sets.
    let parameters: ProtocolParameters
    /// Named GIP initialization actions; nil selects the driver's default sequence.
    let initialization: [String]?
    /// Whether the GIP keep-alive is enabled; nil leaves the driver's default.
    let keepAliveEnabled: Bool?
    /// The named assembly policy; its vocabulary is empty, so every name fails.
    let assembly: ControllerAssemblyPolicy?

    /// Decodes `family`, `variant`, `parameters`, `initialization`, `keepAlive` and `assembly`; an
    /// unknown key, or a combination that the family's parameter rules reject, is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "family", "variant", "parameters", "initialization", "keepAlive", "assembly",
      ])
      let familyName = try container.decode(String.self, for: "family")
      let variantName = try container.decodeOptional(String.self, for: "variant")
      guard let family = PhysicalProtocolID(rawValue: familyName) else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "unknown family \(familyName)")
        )
      }
      let variant = variantName.flatMap(PhysicalProtocolVariantID.init(rawValue:))
      // Only families whose variant transport cannot decide store it, and it must be theirs.
      guard family.storesVariant == (variantName != nil),
        variantName == nil || variant.map(family.variants.contains) == true
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "variant must be a stored variant of family \(familyName)"
          )
        )
      }
      self.protocolID = family
      protocolVariant = variant
      parameters = try container.decodeOptional(ProtocolParameters.self, for: "parameters") ?? .none
      initialization = try container.decodeNamedPacketList(of: family, for: "initialization")
      keepAliveEnabled = try container.decodeOptional(Bool.self, for: "keepAlive")
      if let assemblyName = try container.decodeOptional(String.self, for: "assembly") {
        guard let policy = ControllerAssemblyPolicy(name: assemblyName) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath,
              debugDescription: "unknown assembly \(assemblyName)"
            )
          )
        }
        assembly = policy
      } else {
        assembly = nil
      }
      try validate(codingPath: decoder.codingPath)
    }

    /// Throws a decoding error at `codingPath` when the family, variant, parameters and
    /// initialization do not fit together.
    private func validate(codingPath: [any CodingKey]) throws {
      let violation: String? =
        if let problem = parameters.violation(family: protocolID, variant: protocolVariant) {
          problem
        } else if initialization != nil, protocolID.protocolDescription.namedPackets == nil {
          "initialization actions must be declared by the selected driver"
        } else if keepAliveEnabled != nil,
          !protocolID.protocolDescription.recordSections.contains(.keepAlive)
        {
          "keep-alive policy requires a driver that reads it"
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
    /// The decoded delta.
    let delta: ControllerCapabilityDelta

    /// Decodes `absent`, `present` and `rumble`; an unknown key or a repeated control is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["absent", "present", "rumble"])
      let absent = Set(try container.decodeUniqueList(Control.self, for: "absent") ?? [])
      let present = Set(try container.decodeUniqueList(Control.self, for: "present") ?? [])
      let rumble = try container.decodeOptional(String.self, for: "rumble")
      guard !container.allKeys.isEmpty, absent.isDisjoint(with: present),
        rumble == nil || rumble == "Absent"
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription:
              "capabilities must be nonempty, disjoint, and declare rumble only as Absent"
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

  /// A record's `usb` section.
  struct USBOverride: Decodable {
    /// The name of the USB configuration to claim; nil when the record names none.
    let configuration: String?
    /// The IN and OUT endpoint numbers; nil when the record names none.
    let endpoints: Endpoints?

    /// Decodes `configuration` and `endpoints`; an unknown key or an empty section is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["configuration", "endpoints"])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "usb must not be empty")
        )
      }
      configuration = try container.decodeOptional(String.self, for: "configuration")
      endpoints = try container.decodeOptional(Endpoints.self, for: "endpoints")
    }
  }

  /// The IN and OUT endpoint numbers of a record's `usb` section.
  struct Endpoints: Decodable {
    /// The IN endpoint number.
    let input: Int
    /// The OUT endpoint number.
    let output: Int

    /// Decodes `in` and `out`; the IN number must be 128...255 and the OUT number 1...127, and any
    /// other key is rejected.
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
  /// The field name.
  let stringValue: String
  /// Always `nil`, because the keys are strings.
  let intValue: Int? = nil

  /// Creates a key from a field name.
  init(_ value: String) { stringValue = value }
  /// Creates a key from any string.
  init?(stringValue: String) { self.init(stringValue) }
  /// Creates a key from the decimal text of an integer.
  init?(intValue: Int) { self.init(String(intValue)) }
}

extension KeyedDecodingContainer where Key == DocumentKey {
  /// Decodes the value under `key`.
  func decode<T: Decodable>(_ type: T.Type, for key: String) throws -> T {
    try decode(type, forKey: DocumentKey(key))
  }

  /// Decodes the value under `key`, or nil when the key is absent; an explicit null fails.
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
    _: Value.Type,
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

  /// Decodes a nonempty list of unique ids of named packets that the description of `family`
  /// defines.
  ///
  /// Any other id fails.
  func decodeNamedPacketList(of family: PhysicalProtocolID, for key: String) throws -> [String]? {
    guard let names = try decodeOptional([String].self, for: key) else { return nil }
    let plan = ProtocolDescription.bundled[family]?.namedPackets
    guard !names.isEmpty, Set(names).count == names.count,
      names.allSatisfy({ plan?.packet(named: $0) != nil })
    else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: codingPath + [DocumentKey(key)],
          debugDescription: "\(key) must contain unique, nonempty ids of the family's named packets"
        )
      )
    }
    return names
  }

  /// Fails when the container holds a key outside `allowed`.
  /// - Throws: `DecodingError.dataCorrupted` naming the unknown fields.
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
