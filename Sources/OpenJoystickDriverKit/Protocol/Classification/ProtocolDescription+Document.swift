import Foundation

extension ProtocolDescription {
  /// The JSON document of a protocol description.
  struct Document: Decodable {
    /// The version of the API that the document declares.
    let apiVersion: String?
    /// The kind of the document.
    let kind: String?
    /// The name of the protocol family.
    let family: String
    /// The name of a documented family as a person reads it; nil for a built-in family.
    let displayName: String?
    /// The family's implemented variants.
    let variants: [PhysicalProtocolVariantID]
    /// Whether catalog records store the family's variant.
    let storesVariant: Bool
    /// The default USB endpoints.
    let endpoints: Endpoints
    /// How the family reaches raw USB; nil when it never does.
    let rawUSB: RawUSBDeclaration?
    /// The record sections the family's driver reads.
    let recordSections: Set<RecordSection>
    /// The general `defaults.session` keys the driver reads beyond the rumble template.
    let sessionKeys: Set<SessionKey>
    /// The tuning keys the family reads through IOHID beyond the always-read keys.
    let tuningKeys: Set<ControllerTuning.Key>
    /// The tuning keys a raw-USB variant reads beyond the always-read keys.
    let rawUSBTuningKeys: Set<ControllerTuning.Key>
    /// The controls every controller of the family has; nil when they follow the layout.
    let controls: ControllerCapabilities?
    /// The capability deltas a record may declare.
    let recordCapabilities: RecordCapabilityRules
    /// What OJD still sends when macOS serves the controller.
    let macOSOwnedOutput: MacOSOwnedOutput
    /// What the user does before a controller sends input; nil when input starts on its own.
    let inputStart: InputStartDocument?
    /// The interface signatures that bind the variants.
    let interfaceSignatures: [Signature]
    /// The parameters records may set, by name.
    let parameters: [String: ParameterType]
    /// The rules the parameters obey beyond their types.
    let parameterRules: [ParameterRule]
    /// The transports an activation or deactivation write may name.
    let writeTransports: Set<PhysicalTransport>
    /// The defaults that the family's records layer over; nil when there are none.
    let defaults: Defaults?

    /// `parameterRules[]`: a kind, the parameters it lists and the variants it limits itself to.
    struct RuleDocument: Decodable {
      /// The decoded rule.
      let rule: ParameterRule

      /// Decodes `rule` with its `parameters` and `variants`; an unknown key or kind is rejected.
      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["rule", "parameters", "variants"])
        let kindName = try container.decode(String.self, for: "rule")
        let names = try container.decodeOptional([String].self, for: "parameters")
        let variantNames = try container.decodeOptional([String].self, for: "variants")
        let known = (variantNames ?? []).compactMap(PhysicalProtocolVariantID.init(rawValue:))
        guard let ruleKind = ParameterRule.Kind(rawValue: kindName),
          (ruleKind == .none) == (names == nil), names?.isEmpty != true,
          Set(names ?? []).count == names?.count ?? 0,
          variantNames?.isEmpty != true, known.count == variantNames?.count ?? 0,
          Set(known).count == known.count
        else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath,
              debugDescription:
                "a parameter rule has a known kind, unique parameters (none for None) and "
                + "unique variants"
            )
          )
        }
        rule = ParameterRule(kind: ruleKind, parameters: Set(names ?? []), variants: Set(known))
      }
    }

    /// A unique, nonempty list of `Element` names as a set; empty when absent.
    static func decodeSet<Element: RawRepresentable & Hashable>(
      _: Element.Type,
      _ key: String,
      _ container: KeyedDecodingContainer<DocumentKey>
    ) throws -> Set<Element> where Element.RawValue == String {
      guard let names = try container.decodeOptional([String].self, for: key) else { return [] }
      let elements = names.compactMap(Element.init(rawValue:))
      guard !names.isEmpty, elements.count == names.count, Set(elements).count == names.count else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: container.codingPath + [DocumentKey(key)],
            debugDescription: "\(key) lists unique, known names"
          )
        )
      }
      return Set(elements)
    }

    /// Decodes a full protocol description; an unknown key, an empty section, a repeated variant, a
    /// missing field, or a combination of fields that the description rules reject is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "apiVersion", "kind", "family", "displayName", "variants", "storesVariant", "endpoints",
        "rawUSB",
        "recordSections", "sessionKeys", "tuningKeys", "rawUSBTuningKeys", "controls",
        "recordCapabilities",
        "macOSOwnedOutput", "inputStart",
        "interfaceSignatures", "parameters", "parameterRules", "writeTransports", "defaults",
      ])
      apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
      kind = try container.decodeOptional(String.self, for: "kind")
      family = try container.decode(String.self, for: "family")
      displayName = try container.decodeOptional(String.self, for: "displayName")
      guard displayName?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("displayName")],
            debugDescription: "displayName must not be empty"
          )
        )
      }
      let variantNames = try container.decodeOptional([String].self, for: "variants")
      let familyVariants = (variantNames ?? [])
        .compactMap(PhysicalProtocolVariantID.init(rawValue:))
      guard variantNames?.isEmpty != true, familyVariants.count == variantNames?.count ?? 0,
        Set(familyVariants).count == familyVariants.count
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("variants")],
            debugDescription: "variants lists unique, known names"
          )
        )
      }
      variants = familyVariants
      let stores = try container.decodeOptional(Bool.self, for: "storesVariant")
      guard stores == nil || (stores == true && !variants.isEmpty) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("storesVariant")],
            debugDescription: "storesVariant is true and needs variants"
          )
        )
      }
      storesVariant = stores == true
      endpoints = try container.decode(EndpointsDocument.self, for: "endpoints").endpoints
      rawUSB = try container.decodeOptional(RawUSBDeclaration.self, for: "rawUSB")
      recordSections = try Self.decodeSet(RecordSection.self, "recordSections", container)
      sessionKeys = try Self.decodeSet(SessionKey.self, "sessionKeys", container)
      tuningKeys = try Self.decodeSet(ControllerTuning.Key.self, "tuningKeys", container)
      rawUSBTuningKeys = try Self.decodeSet(
        ControllerTuning.Key.self,
        "rawUSBTuningKeys",
        container
      )
      guard !tuningKeys.contains(.stickDeadzone), !rawUSBTuningKeys.contains(.stickDeadzone) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("tuningKeys")],
            debugDescription: "stickDeadzone is read by every driver"
          )
        )
      }
      controls = try container.decodeOptional(ControlsDocument.self, for: "controls")?.value
      recordCapabilities =
        try container.decodeOptional(RecordCapabilitiesDocument.self, for: "recordCapabilities")?
        .value ?? .none
      macOSOwnedOutput =
        try container.decodeOptional(MacOSOwnedOutputDocument.self, for: "macOSOwnedOutput")?.value
        ?? .none
      inputStart = try container.decodeOptional(InputStartDocument.self, for: "inputStart")
      let signatures = try container.decodeOptional([Signature].self, for: "interfaceSignatures")
      guard signatures?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("interfaceSignatures")],
            debugDescription: "interfaceSignatures must not be empty"
          )
        )
      }
      interfaceSignatures = signatures ?? []
      let declarations = try container.decodeOptional([String: Declaration].self, for: "parameters")
      guard declarations?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("parameters")],
            debugDescription: "parameters must not be empty"
          )
        )
      }
      let unknown = Set(declarations.map { Array($0.keys) } ?? []).subtracting(
        ProtocolParameters.names
      )
      guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("parameters")],
            debugDescription:
              "no driver reads parameter(s): \(unknown.sorted().joined(separator: ", "))"
          )
        )
      }
      parameters = declarations?.mapValues(\.type) ?? [:]
      let rules = try container.decodeOptional([RuleDocument].self, for: "parameterRules")
      guard rules?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("parameterRules")],
            debugDescription: "parameterRules must not be empty"
          )
        )
      }
      parameterRules = rules?.map(\.rule) ?? []
      writeTransports = try Self.decodeSet(PhysicalTransport.self, "writeTransports", container)
      defaults = try container.decodeOptional(Defaults.self, for: "defaults")
    }
  }
}
