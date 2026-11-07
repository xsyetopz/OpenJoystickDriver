import Foundation

extension ProtocolDescription {
  /// The JSON document of a protocol description.
  struct Document: Decodable {
    /// One interface signature that binds a variant.
    struct Signature: Decodable {
      /// The name of the variant the signature binds.
      let variant: String
      /// The USB interface class.
      let interfaceClass: UInt8
      /// The USB interface subclass.
      let interfaceSubclass: UInt8
      /// The USB interface protocol.
      let interfaceProtocol: UInt8
      /// The interface number that carries data; nil when any interface does.
      let interfaceNumber: UInt8?

      /// Decodes `variant`, the class triple and an optional `interfaceNumber`; an unknown key is
      /// rejected.
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

    /// The defaults that the family's records layer over.
    struct Defaults: Decodable {
      /// The session defaults; nil when the description sets none.
      let session: Session?
      /// The input defaults; nil when the description sets none.
      let input: ControllerRecordDocument.Input?
      /// The tuning defaults; nil when the description sets none.
      let tuning: ControllerTuning?
      /// Tuning by variant name, layered over `tuning` for that variant.
      let variantTuning: [String: ControllerTuning]
      /// Rumble templates by variant name, each overriding the flat `session.rumble`.
      let variantRumble: [String: RumbleOutputTemplate]

      /// Decodes `session`, `input`, `tuning` and `variants`; an unknown key or an empty section is
      /// rejected.
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

    /// `defaults.session`: what runs while the device is open.
    ///
    /// The startup writes and rumble template, the keep-alive, the Switch 1 subcommands, the GIP
    /// named packets and the counts that bound the startup resends.
    struct Session: Decodable {
      /// The startup writes; nil when the description sets none.
      let startup: ControllerRecordDocument.StartupList?
      /// The rumble template; nil when the description sets none.
      let rumble: RumbleOutputTemplate?
      /// The keep-alive; nil when the description sets none.
      let keepAlive: KeepAlive?
      /// For the Valve families, the reports sent in order when the controller is activated.
      let activation: [RecordStartupWrite]?
      /// For the Valve families, the reports sent in order when the controller is deactivated.
      let deactivation: [RecordStartupWrite]?
      /// The subcommand reports; nil when the description sets none.
      let subcommands: SubcommandPlan?
      /// The named packets; nil when the description sets none.
      let namedPackets: NamedPacketPlan?
      /// The startup attempts a raw-USB handshake makes before it fails.
      let handshakeAttempts: Int?
      /// The most startup resends after announces before the first input.
      let announceResendLimit: Int?
      /// The USB interface that carries commands and their replies.
      let commandChannel: ProtocolDescription.CommandChannel?
      /// The zero-amplitude packets the rumble refresh sends after a stop.
      let trailingStopPackets: Int?
      /// The wire facts of the Wii Remote.
      let wiiRemote: ProtocolDescription.WiiRemote?
      /// The keys every family may set.
      ///
      /// The description schema lists the same keys as `$defs/generalSessionKeys`, which a test
      /// pins this to.
      static let generalKeys: Set<String> = ["startup", "rumble", "keepAlive"]
      /// The keys of the session that only some families have: every key but the general ones.
      let familyFields: Set<String>

      /// Decodes the session keys; an unknown key or a count outside its range is rejected.
      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: [
          "startup", "rumble", "keepAlive", "activation", "deactivation", "subcommands",
          "namedPackets", "handshakeAttempts",
          "announceResendLimit", "commandChannel",
          "trailingStopPackets", "wiiRemote",
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
        wiiRemote = try container.decodeOptional(
          ProtocolDescription.WiiRemote.self,
          for: "wiiRemote"
        )
      }
    }

    /// `defaults.session.activation` or `deactivation`: 1...16 HID reports sent in order, each
    /// with a report, its bytes and optionally the one transport it is sent on.
    struct SessionWriteList: Decodable {
      /// The writes in the order they are sent.
      let writes: [RecordStartupWrite]

      /// Decodes 1...16 writes, each with `report`, `bytes` and an optional `transport`; any other
      /// count or key is rejected.
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
      /// The action that starts input.
      let action: InputStartAction
      /// The variant names the action is limited to; every variant when empty.
      let variants: [String]

      /// Decodes `action` and optional unique `variants`; an unknown action, a repeated or empty
      /// variant list, or an unknown key is rejected.
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
      /// The variant's tuning; nil when it sets none.
      let tuning: ControllerTuning?
      /// The variant's rumble template; nil when it sets none.
      let rumble: RumbleOutputTemplate?

      /// Decodes `tuning` and `session`; an unknown key or an empty variant is rejected.
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
      /// The rumble template that overrides the family's.
      let rumble: RumbleOutputTemplate

      /// Decodes `rumble`; any other key is rejected.
      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["rumble"])
        rumble = try container.decode(ControllerRecordDocument.RumbleTemplate.self, for: "rumble")
          .template
      }
    }

    /// The version of the API that the document declares.
    let apiVersion: String?
    /// The kind of the document.
    let kind: String?
    /// The name of the protocol family.
    let family: String
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

    /// Decodes a full protocol description; an unknown key, an empty section, a repeated variant, a
    /// missing field, or a combination of fields that the description rules reject is rejected.
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
