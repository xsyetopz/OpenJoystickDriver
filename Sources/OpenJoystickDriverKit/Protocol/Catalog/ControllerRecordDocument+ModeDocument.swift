import Foundation

extension ControllerRecordDocument {
  /// One entry of the record's `modes`: an ID, the protocol that mode runs, and, for every mode
  /// but `default`, the match keys that select it.
  struct ModeDocument: Decodable {
    /// The ID of the mode that has no match keys.
    static let defaultID = "default"

    /// The mode ID: lowercase words joined by hyphens.
    let id: String
    /// The protocol, variant and parameters the mode runs.
    let protocolInfo: ProtocolInfo
    /// Nil exactly for the `default` mode.
    let match: ControllerModeMatch?
    /// The device interfaces the mode drives; nil keeps the default binding.
    let interfaceRange: ClosedRange<UInt8>?
    /// The steps this mode runs; a mode without a `session` runs none.
    let session: ControllerSession
    /// Why the mode serves nothing while it matches; nil for a mode that serves the device.
    let idle: ControllerIdleReason?
    /// Who serves the controller while this mode is selected; nil keeps the record's `server`.
    let server: ControllerServer?
    /// The input this mode reads in place of the record's; nil reads the record's.
    let input: Input?

    /// Whether this is the `default` mode.
    var isDefault: Bool { id == Self.defaultID }

    /// Decodes `id`, `protocol` and the optional `match`, `interface`, `session`, `idle`, `server`
    /// and `input`; an unknown key, a malformed ID, a `default` mode with a match, an input or a
    /// server, another mode without a match, an unknown `idle` reason, an idle mode with an
    /// `interface`, a `session` or an input, a server on a mode with probes, an
    /// `AwaitsReenumeration` mode without `server: OJD`, or an input with `descriptorShapes` is
    /// rejected.
    ///
    /// The HID stream decides who serves a device before any probe can run, so only a mode chosen
    /// by its enumerated keys states a server.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(
        allowed: ["id", "protocol", "match", "interface", "session", "idle", "server", "input"]
      )
      let identifier = try container.decode(String.self, for: "id")
      guard Self.isValidID(identifier) else {
        throw Self.invalid("id", "a mode id is lowercase words joined by hyphens", decoder)
      }
      let modeMatch = try container.decodeOptional(ModeMatchDocument.self, for: "match")?.match
      let isDefaultMode = identifier == Self.defaultID
      if isDefaultMode, modeMatch != nil {
        throw Self.invalid(
          "match",
          "the default mode has no match; it runs when no other mode does",
          decoder
        )
      }
      if !isDefaultMode, modeMatch == nil {
        throw Self.invalid("match", "every mode but default needs a match", decoder)
      }
      idle = try Self.idleReason(container, decoder)
      server = try Self.server(container, decoder)
      try Self.checkServer(server, idle: idle, isDefault: isDefaultMode, match: modeMatch, decoder)
      self.id = identifier
      self.match = modeMatch
      protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
      interfaceRange = try container.decodeOptional(ModeInterfaceDocument.self, for: "interface")?
        .range
      session =
        try container.decodeOptional(SessionDocument.self, for: "session")?.session ?? .none
      input = try container.decodeOptional(Input.self, for: "input")
      if isDefaultMode, input != nil {
        throw Self.invalid("input", "the default mode reads the record's input", decoder)
      }
      guard input?.shapes.isEmpty ?? true else {
        throw Self.invalid("input", "descriptorShapes belong to a protocol description", decoder)
      }
    }

    /// Creates the decoding error that names `key` in the current coding path with `message`.
    static func invalid(
      _ key: String,
      _ message: String,
      _ decoder: any Decoder
    ) -> DecodingError {
      .dataCorrupted(
        .init(codingPath: decoder.codingPath + [DocumentKey(key)], debugDescription: message)
      )
    }

    /// Reads an optional `idle` reason; an unknown reason, or an idle mode with an `interface`, a
    /// `session` or an `input`, is rejected.
    private static func idleReason(
      _ container: KeyedDecodingContainer<DocumentKey>,
      _ decoder: any Decoder
    ) throws -> ControllerIdleReason? {
      guard let name = try container.decodeOptional(String.self, for: "idle") else { return nil }
      guard let reason = ControllerIdleReason(rawValue: name) else {
        throw Self.invalid(
          "idle",
          "idle is NoControllerLinked, Bootloader or AwaitsReenumeration",
          decoder
        )
      }
      guard !container.contains(DocumentKey("interface")),
        !container.contains(DocumentKey("session")), !container.contains(DocumentKey("input"))
      else {
        throw Self.invalid(
          "idle",
          "an idle mode has no interface, no session and no input",
          decoder
        )
      }
      return reason
    }

    /// Rejects a `server` on the default mode or on a mode with probes, and an
    /// `AwaitsReenumeration` mode that does not state `server: OJD`.
    private static func checkServer(
      _ server: ControllerServer?,
      idle: ControllerIdleReason?,
      isDefault: Bool,
      match: ControllerModeMatch?,
      _ decoder: any Decoder
    ) throws {
      if server != nil, isDefault {
        throw Self.invalid("server", "the default mode uses the record's server", decoder)
      }
      if server != nil, match?.probes.isEmpty == false {
        throw Self.invalid(
          "server",
          "a mode with probes uses the record's server; the server is chosen before probes run",
          decoder
        )
      }
      if idle == .awaitsReenumeration, server != .ojd {
        throw Self.invalid(
          "server",
          "an AwaitsReenumeration mode states server OJD, so OJD holds the device",
          decoder
        )
      }
    }

    /// Reads an optional `server`; a name other than System or OJD is rejected.
    private static func server(
      _ container: KeyedDecodingContainer<DocumentKey>,
      _ decoder: any Decoder
    ) throws -> ControllerServer? {
      guard let name = try container.decodeOptional(String.self, for: "server") else { return nil }
      guard let stated = ControllerServer(rawValue: name) else {
        throw Self.invalid("server", "server is System or OJD", decoder)
      }
      return stated
    }

    /// Lowercase ASCII words joined by single hyphens, the first starting with a letter.
    private static func isValidID(_ id: String) -> Bool {
      let words = id.split(separator: "-", omittingEmptySubsequences: false)
      return id.first?.isLetter == true
        && words.allSatisfy { word in
          !word.isEmpty
            && word.unicodeScalars.allSatisfy {
              ("a"..."z").contains($0) || ("0"..."9").contains($0)
            }
        }
    }

    /// The runtime form of this mode.
    var mode: ControllerMode {
      ControllerMode(
        id: id,
        physicalProtocolID: protocolInfo.protocolID,
        physicalProtocolVariant: protocolInfo.protocolVariant,
        parameters: protocolInfo.parameters,
        gipStartupPackets: protocolInfo.initialization ?? [],
        gipKeepAlivePolicy: protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled }
          ?? .enabled,
        assemblyPolicy: protocolInfo.assembly,
        match: match ?? ControllerModeMatch(),
        interfaceRange: interfaceRange,
        session: session,
        idle: idle,
        server: server,
        inputLayouts: input?.layouts,
        hidUsageMap: input?.usageMap
      )
    }
  }
}
