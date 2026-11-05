import Foundation

extension ProtocolDescription {
  struct Document: Decodable {
    struct Signature: Decodable {
      let variant: String
      let interfaceClass: UInt8
      let interfaceSubclass: UInt8
      let interfaceProtocol: UInt8
      let interfaceNumber: UInt8?

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: [
          "variant", "interfaceClass", "interfaceSubclass", "interfaceProtocol", "interfaceNumber",
        ])
        variant = try container.decode(String.self, for: "variant")
        interfaceClass = try container.decode(UInt8.self, for: "interfaceClass")
        interfaceSubclass = try container.decode(UInt8.self, for: "interfaceSubclass")
        interfaceProtocol = try container.decode(UInt8.self, for: "interfaceProtocol")
        interfaceNumber = try container.decodeOptional(UInt8.self, for: "interfaceNumber")
      }
    }

    struct Defaults: Decodable {
      let session: Session?
      let input: ControllerRecordDocument.Input?
      let tuning: ControllerTuning?
      /// Tuning by variant name, layered over `tuning` for that variant.
      let variantTuning: [String: ControllerTuning]
      /// Rumble templates by variant name, each overriding the flat `session.rumble`.
      let variantRumble: [String: RumbleOutputTemplate]

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: [
          "session", "input", "tuning", "variants",
        ])
        guard !container.allKeys.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "defaults must not be empty")
          )
        }
        session = try container.decodeOptional(Session.self, for: "session")
        input = try container.decodeOptional(ControllerRecordDocument.Input.self, for: "input")
        tuning = try container.decodeOptional(ControllerRecordDocument.Tuning.self, for: "tuning")?
          .tuning
        let variants = try container.decodeOptional([String: VariantDefaults].self, for: "variants")
        guard variants?.isEmpty != true else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath + [DocumentKey("variants")],
              debugDescription: "variants must not be empty"
            )
          )
        }
        variantTuning = variants?.compactMapValues(\.tuning) ?? [:]
        variantRumble = variants?.compactMapValues(\.rumble) ?? [:]
      }
    }

    /// `defaults.session`: what runs while the device is open. The startup writes and rumble
    /// template, the keep-alive, the Switch 1 subcommands, the GIP named packets and the counts
    /// that bound the startup resends.
    struct Session: Decodable {
      let startup: ControllerRecordDocument.StartupList?
      let rumble: RumbleOutputTemplate?
      let keepAlive: KeepAlive?
      let activation: [RecordStartupWrite]?
      let deactivation: [RecordStartupWrite]?
      let subcommands: SubcommandPlan?
      let namedPackets: NamedPacketPlan?
      let handshakeAttempts: Int?
      let announceResendLimit: Int?
      let commandChannel: ProtocolDescription.CommandChannel?
      let trailingStopPackets: Int?
      /// The keys every family may set. The description schema lists the same keys as
      /// `$defs/generalSessionKeys`, which a test pins this to.
      static let generalKeys: Set<String> = ["startup", "rumble", "keepAlive"]
      /// The keys of the session that only some families have: every key but the general ones.
      let familyFields: Set<String>

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: [
          "startup", "rumble", "keepAlive", "activation", "deactivation", "subcommands",
          "namedPackets", "handshakeAttempts",
          "announceResendLimit", "commandChannel",
          "trailingStopPackets",
        ])
        familyFields = Set(container.allKeys.map(\.stringValue)).subtracting(Self.generalKeys)
        guard !container.allKeys.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "session must not be empty")
          )
        }
        startup = try container.decodeOptional(
          ControllerRecordDocument.StartupList.self,
          for: "startup"
        )
        rumble = try container.decodeOptional(
          ControllerRecordDocument.RumbleTemplate.self,
          for: "rumble"
        )?.template
        keepAlive = try container.decodeOptional(KeepAlive.self, for: "keepAlive")
        activation = try container.decodeOptional(SessionWriteList.self, for: "activation")?.writes
        deactivation = try container.decodeOptional(SessionWriteList.self, for: "deactivation")?
          .writes
        subcommands = try container.decodeOptional(SubcommandPlan.self, for: "subcommands")
        namedPackets = try container.decodeOptional(NamedPacketPlan.self, for: "namedPackets")
        func count(_ key: String, _ range: ClosedRange<Int>) throws -> Int? {
          let value = try container.decodeOptional(Int.self, for: key)
          guard value.map(range.contains) ?? true else {
            throw DecodingError.dataCorrupted(
              .init(
                codingPath: decoder.codingPath + [DocumentKey(key)],
                debugDescription: "\(key) must be in \(range.lowerBound)...\(range.upperBound)"
              )
            )
          }
          return value
        }
        handshakeAttempts = try count("handshakeAttempts", 1...10)
        announceResendLimit = try count("announceResendLimit", 1...100)
        commandChannel = try container.decodeOptional(
          ProtocolDescription.CommandChannel.self,
          for: "commandChannel"
        )
        trailingStopPackets = try count("trailingStopPackets", 1...10)
      }
    }

    /// `defaults.session.activation` or `deactivation`: 1...16 HID reports sent in order, each
    /// with a report, its bytes and optionally the one transport it is sent on.
    struct SessionWriteList: Decodable {
      let writes: [RecordStartupWrite]

      init(from decoder: any Decoder) throws {
        var list = try decoder.unkeyedContainer()
        var writes: [RecordStartupWrite] = []
        while !list.isAtEnd {
          let container = try list.nestedContainer(keyedBy: DocumentKey.self)
          try container.rejectUnknown(allowed: ["report", "bytes", "transport"])
          do {
            writes.append(
              try ControllerRecordDocument.StartupWrite.hidWrite(container, condition: .always)
            )
          } catch let problem as ControllerRecordProblem {
            throw DecodingError.dataCorrupted(
              .init(codingPath: decoder.codingPath, debugDescription: problem.description)
            )
          }
        }
        guard (1...16).contains(writes.count) else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath,
              debugDescription: "activation and deactivation name 1...16 writes"
            )
          )
        }
        self.writes = writes
      }
    }

    /// `inputStart`: a known action and the unique variant names it is limited to.
    struct InputStartDocument: Decodable {
      let action: InputStartAction
      let variants: [String]

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["action", "variants"])
        let actionName = try container.decode(String.self, for: "action")
        let names = try container.decodeOptional([String].self, for: "variants")
        guard let action = InputStartAction(rawValue: actionName), names?.isEmpty != true,
          Set(names ?? []).count == names?.count ?? 0
        else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: decoder.codingPath,
              debugDescription: "inputStart has a known action and unique variants"
            )
          )
        }
        self.action = action
        variants = names ?? []
      }
    }

    /// `defaults.variants.<variant>`: the tuning and rumble template a variant starts from.
    struct VariantDefaults: Decodable {
      let tuning: ControllerTuning?
      let rumble: RumbleOutputTemplate?

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["tuning", "session"])
        guard !container.allKeys.isEmpty else {
          throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath, debugDescription: "a variant must not be empty")
          )
        }
        tuning = try container.decodeOptional(ControllerRecordDocument.Tuning.self, for: "tuning")?
          .tuning
        rumble = try container.decodeOptional(VariantSession.self, for: "session")?.rumble
      }
    }

    /// `defaults.variants.<variant>.session`: the rumble template that overrides the family's.
    struct VariantSession: Decodable {
      let rumble: RumbleOutputTemplate

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["rumble"])
        rumble = try container.decode(ControllerRecordDocument.RumbleTemplate.self, for: "rumble")
          .template
      }
    }

    let apiVersion: String?
    let kind: String?
    let family: String
    let variants: [PhysicalProtocolVariantID]
    let storesVariant: Bool
    let endpoints: Endpoints
    let rawUSB: RawUSBDeclaration?
    let recordSections: Set<RecordSection>
    /// The general `defaults.session` keys the driver reads beyond the rumble template.
    let sessionKeys: Set<SessionKey>
    let tuningKeys: Set<ControllerTuning.Key>
    let rawUSBTuningKeys: Set<ControllerTuning.Key>
    let controls: ControllerCapabilities?
    let recordCapabilities: RecordCapabilityRules
    let macOSOwnedOutput: MacOSOwnedOutput
    let inputStart: InputStartDocument?
    let interfaceSignatures: [Signature]
    let parameters: [String: ParameterType]
    let parameterRules: [ParameterRule]
    let writeTransports: Set<PhysicalTransport>
    let defaults: Defaults?

    /// `parameterRules[]`: a kind, the parameters it lists and the variants it limits itself to.
    struct RuleDocument: Decodable {
      let rule: ParameterRule

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["rule", "parameters", "variants"])
        let kindName = try container.decode(String.self, for: "rule")
        let names = try container.decodeOptional([String].self, for: "parameters")
        let variantNames = try container.decodeOptional([String].self, for: "variants")
        let variants = (variantNames ?? []).compactMap(PhysicalProtocolVariantID.init(rawValue:))
        guard let kind = ParameterRule.Kind(rawValue: kindName),
          (kind == .none) == (names == nil), names?.isEmpty != true,
          Set(names ?? []).count == names?.count ?? 0,
          variantNames?.isEmpty != true, variants.count == variantNames?.count ?? 0,
          Set(variants).count == variants.count
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
        rule = ParameterRule(kind: kind, parameters: Set(names ?? []), variants: Set(variants))
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

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "apiVersion", "kind", "family", "variants", "storesVariant", "endpoints", "rawUSB",
        "recordSections", "sessionKeys", "tuningKeys", "rawUSBTuningKeys", "controls",
        "recordCapabilities",
        "macOSOwnedOutput", "inputStart",
        "interfaceSignatures", "parameters", "parameterRules", "writeTransports", "defaults",
      ])
      apiVersion = try container.decodeOptional(String.self, for: "apiVersion")
      kind = try container.decodeOptional(String.self, for: "kind")
      family = try container.decode(String.self, for: "family")
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
