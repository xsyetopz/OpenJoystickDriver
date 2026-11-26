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
    try Self.requireHeader(in: container)
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
    try Self.requireNoControlSectionsForIdleModes(
      modes,
      in: container,
      codingPath: decoder.codingPath
    )
    name = try container.decodeOptional(String.self, for: "name")
    placeholderSerial = try container.decodeOptional(String.self, for: "placeholderSerial")
    try Self.requireNonEmpty(
      [("name", name), ("placeholderSerial", placeholderSerial)],
      codingPath: decoder.codingPath
    )
    usb = try container.decodeOptional(USBOverride.self, for: "usb")
    bluetoothLE = try container.decodeOptional(BluetoothLE.self, for: "bluetoothLE")
    capabilities =
      try container.decodeOptional(CapabilityDelta.self, for: "capabilities")?.delta ?? .none
    server = try Self.decodeChoice(
      for: "server",
      expecting: "server must be System or OJD",
      in: container
    )
    route = try Self.decodeChoice(
      for: "route",
      expecting: "route must be ExtensionOwned",
      in: container
    )
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
    try Self.requireValidationModes(validations, in: modes, codingPath: decoder.codingPath)
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
