import Foundation

extension ProtocolDescription.Document {
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
    /// The packet a receiver slot gets when OJD closes it on purpose; nil when the description
    /// sets none.
    let receiverPowerOff: USBStartupWrite?

    /// Decodes `session`, `input`, `tuning`, `variants` and `receiverPowerOff`; an unknown key
    /// or an empty section is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "session", "input", "tuning", "variants", "receiverPowerOff",
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
      let perVariant = try container.decodeOptional(
        [String: VariantDefaults].self,
        for: "variants"
      )
      guard perVariant?.isEmpty != true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("variants")],
            debugDescription: "variants must not be empty"
          )
        )
      }
      variantTuning = perVariant?.compactMapValues(\.tuning) ?? [:]
      variantRumble = perVariant?.compactMapValues(\.rumble) ?? [:]
      receiverPowerOff = try container.decodeOptional(
        ReceiverPowerOff.self,
        for: "receiverPowerOff"
      )?.write
    }
  }

  /// `defaults.receiverPowerOff`: one raw-USB packet with `bytes`, and optionally `endpoint`,
  /// `timeoutMilliseconds` and `variants`.
  struct ReceiverPowerOff: Decodable {
    /// The packet.
    let write: USBStartupWrite

    /// Decodes the packet; an unknown key or a value outside its range is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "bytes", "endpoint", "timeoutMilliseconds", "variants",
      ])
      let condition = try StartupWriteCondition.decode(from: container, decoder: decoder)
      do {
        write = try ControllerRecordDocument.StartupWrite.usbWrite(
          container,
          condition: condition
        )
      } catch let problem as ControllerRecordProblem {
        throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
      }
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
        try container.decodeOptional(Int.self, for: key, in: range)
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
      var decoded: [RecordStartupWrite] = []
      while !list.isAtEnd {
        let container = try list.nestedContainer(keyedBy: DocumentKey.self)
        try container.rejectUnknown(allowed: ["report", "bytes", "transport"])
        do {
          decoded.append(
            try ControllerRecordDocument.StartupWrite.hidWrite(container, condition: .always)
          )
        } catch let problem as ControllerRecordProblem {
          throw DecodingError.dataCorrupted(problem.context(at: decoder.codingPath))
        }
      }
      guard (1...16).contains(decoded.count) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "activation and deactivation name 1...16 writes"
          )
        )
      }
      self.writes = decoded
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
      guard let parsed = InputStartAction(rawValue: actionName), names?.isEmpty != true,
        Set(names ?? []).count == names?.count ?? 0
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "inputStart has a known action and unique variants"
          )
        )
      }
      self.action = parsed
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
}
