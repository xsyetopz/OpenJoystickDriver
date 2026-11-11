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

    /// Whether this is the `default` mode.
    var isDefault: Bool { id == Self.defaultID }

    /// Decodes `id`, `protocol` and the optional `match`, `interface`, `session` and `idle`; an
    /// unknown key, a malformed ID, a `default` mode with a match, another mode without one, an
    /// unknown `idle` reason, or an idle mode with an `interface` or a `session` is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(
        allowed: ["id", "protocol", "match", "interface", "session", "idle"]
      )
      let id = try container.decode(String.self, for: "id")
      guard Self.isValidID(id) else {
        throw Self.invalid("id", "a mode id is lowercase words joined by hyphens", decoder)
      }
      let match = try container.decodeOptional(ModeMatchDocument.self, for: "match")?.match
      let isDefault = id == Self.defaultID
      if isDefault, match != nil {
        throw Self.invalid(
          "match",
          "the default mode has no match; it runs when no other mode does",
          decoder
        )
      }
      if !isDefault, match == nil {
        throw Self.invalid("match", "every mode but default needs a match", decoder)
      }
      if let name = try container.decodeOptional(String.self, for: "idle") {
        guard let reason = ControllerIdleReason(rawValue: name) else {
          throw Self.invalid("idle", "idle is NoControllerLinked or Bootloader", decoder)
        }
        guard !container.contains(DocumentKey("interface")),
          !container.contains(DocumentKey("session"))
        else {
          throw Self.invalid("idle", "an idle mode has no interface and no session", decoder)
        }
        idle = reason
      } else {
        idle = nil
      }
      self.id = id
      self.match = match
      protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
      interfaceRange = try container.decodeOptional(ModeInterfaceDocument.self, for: "interface")?
        .range
      session =
        try container.decodeOptional(SessionDocument.self, for: "session")?.session ?? .none
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
        idle: idle
      )
    }
  }

  /// A mode's `interface`: an inclusive range of interface numbers.
  struct ModeInterfaceDocument: Decodable {
    /// The inclusive interface-number range.
    let range: ClosedRange<UInt8>

    /// Decodes `first` and `last`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["first", "last"])
      let first = try container.decode(Int.self, for: "first")
      let last = try container.decode(Int.self, for: "last")
      guard let low = UInt8(exactly: first), let high = UInt8(exactly: last), low <= high else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "an interface range is 0...255 with first not above last"
          )
        )
      }
      range = low...high
    }
  }

  /// A mode's match keys; every key present must hold.
  struct ModeMatchDocument: Decodable {
    /// The decoded match keys.
    let match: ControllerModeMatch

    /// Decodes the match keys `link`, `interfaceSignature`, `manufacturer`, `product`, `bcdDevice`
    /// and `probes`; an unknown key or an empty string is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(
        allowed: ["link", "interfaceSignature", "manufacturer", "product", "bcdDevice", "probes"]
      )
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "a match needs at least one key")
        )
      }
      var match = ControllerModeMatch()
      if let name = try container.decodeOptional(String.self, for: "link") {
        guard let link = PhysicalTransport(rawValue: name) else {
          throw ModeDocument.invalid(
            "link",
            "link is USB, BluetoothClassic, BluetoothLE or ProprietaryRadioReceiver",
            decoder
          )
        }
        match.link = link
      }
      match.interfaceSignature =
        try container.decodeOptional(
          ModeInterfaceSignatureDocument.self,
          for: "interfaceSignature"
        )?
        .signature
      match.manufacturer = try Self.text("manufacturer", container, decoder)
      match.product = try Self.text("product", container, decoder)
      match.bcdDevice = try container.decodeOptional(BCDRangeDocument.self, for: "bcdDevice")?.range
      if let entries = try container.decodeOptional([ModeProbeDocument].self, for: "probes") {
        guard !entries.isEmpty else {
          throw ModeDocument.invalid("probes", "a mode needs at least one probe", decoder)
        }
        match.probes = entries.map(\.probe)
      }
      self.match = match
    }

    /// Reads an optional string for `key`; an empty string is rejected.
    private static func text(
      _ key: String,
      _ container: KeyedDecodingContainer<DocumentKey>,
      _ decoder: any Decoder
    ) throws -> String? {
      guard let text = try container.decodeOptional(String.self, for: key) else { return nil }
      guard !text.isEmpty else {
        throw ModeDocument.invalid(key, "\(key) must not be empty", decoder)
      }
      return text
    }
  }

  /// An interface the device must expose: its USB class triple and, optionally, its HID usage.
  struct ModeInterfaceSignatureDocument: Decodable {
    /// The decoded interface signature.
    let signature: ControllerModeMatch.InterfaceSignature

    /// Decodes an interface's class triple, optional HID usage and optional endpoint set; an
    /// unknown key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(
        allowed: [
          "interfaceClass", "interfaceSubclass", "interfaceProtocol", "usagePage", "usage",
          "endpoints",
        ]
      )
      func byte(_ key: String) throws -> UInt8 {
        guard let byte = UInt8(exactly: try container.decode(Int.self, for: key)) else {
          throw ModeDocument.invalid(key, "\(key) is 0...255", decoder)
        }
        return byte
      }
      func word(_ key: String) throws -> UInt32? {
        guard let value = try container.decodeOptional(Int.self, for: key) else { return nil }
        guard (0...65_535).contains(value) else {
          throw ModeDocument.invalid(key, "\(key) is 0...65535", decoder)
        }
        return UInt32(value)
      }
      let usagePage = try word("usagePage")
      let usage = try word("usage")
      guard usage == nil || usagePage != nil else {
        throw ModeDocument.invalid("usage", "usage needs usagePage", decoder)
      }
      signature = ControllerModeMatch.InterfaceSignature(
        interfaceClass: try byte("interfaceClass"),
        interfaceSubclass: try byte("interfaceSubclass"),
        interfaceProtocol: try byte("interfaceProtocol"),
        usagePage: usagePage,
        usage: usage,
        endpoints: try container.decodeOptional([ModeEndpointDocument].self, for: "endpoints")?
          .map(\.endpoint)
      )
      if let count = signature.endpoints?.count, count == 0 {
        throw ModeDocument.invalid("endpoints", "endpoints names at least one endpoint", decoder)
      }
    }
  }

  /// One endpoint of an interface signature's endpoint set.
  struct ModeEndpointDocument: Decodable {
    /// The decoded endpoint pattern.
    let endpoint: ControllerModeMatch.InterfaceSignature.Endpoint

    /// Decodes `address`, `direction`, `transferType` and `maxPacketSize`; an unknown key, a
    /// direction other than In or Out, or a packet size outside 0...65535 is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "address", "direction", "transferType", "maxPacketSize",
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "an endpoint needs at least one key"
          )
        )
      }
      var endpoint = ControllerModeMatch.InterfaceSignature.Endpoint()
      if let address = try container.decodeOptional(Int.self, for: "address") {
        guard let byte = UInt8(exactly: address) else {
          throw ModeDocument.invalid("address", "address is 0...255", decoder)
        }
        endpoint.address = byte
      }
      if let name = try container.decodeOptional(String.self, for: "direction") {
        guard let direction = USBEndpointDirection(rawValue: name) else {
          throw ModeDocument.invalid("direction", "direction is In or Out", decoder)
        }
        endpoint.direction = direction
      }
      if let name = try container.decodeOptional(String.self, for: "transferType") {
        guard let type = USBEndpointTransferType(rawValue: name), type != .unknown else {
          throw ModeDocument.invalid(
            "transferType",
            "transferType is Control, Isochronous, Bulk, or Interrupt",
            decoder
          )
        }
        endpoint.transferType = type
      }
      if let size = try container.decodeOptional(Int.self, for: "maxPacketSize") {
        guard let word = UInt16(exactly: size) else {
          throw ModeDocument.invalid("maxPacketSize", "maxPacketSize is 0...65535", decoder)
        }
        endpoint.maxPacketSize = word
      }
      self.endpoint = endpoint
    }
  }

  /// An inclusive range of `bcdDevice` values.
  struct BCDRangeDocument: Decodable {
    /// The decoded release range.
    let range: ClosedRange<UInt16>

    /// Decodes `min` and `max`, 0...65535 with `min` not above `max`; any other key is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["min", "max"])
      let low = try container.decode(Int.self, for: "min")
      let high = try container.decode(Int.self, for: "max")
      guard let min = UInt16(exactly: low), let max = UInt16(exactly: high), min <= max else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "a bcdDevice range is 0...65535 with min not above max"
          )
        )
      }
      range = min...max
    }
  }

  /// A probe: a read of one feature report, with no way to write.
  struct ModeProbeDocument: Decodable {
    /// The decoded probe.
    let probe: ControllerModeProbe

    /// Decodes `report`, `length`, `expect` and the `offset` and `bytes` of a byte expectation; an
    /// unknown key, an unknown expectation, or `offset` and `bytes` on any expectation but `Bytes`
    /// is rejected.
    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: ["report", "length", "expect", "offset", "bytes"])
      let report = try container.decode(Int.self, for: "report")
      let length = try container.decode(Int.self, for: "length")
      let expect = try container.decode(String.self, for: "expect")
      let offset = try container.decodeOptional(Int.self, for: "offset")
      let hex = try container.decodeOptional(String.self, for: "bytes")
      guard let reportID = UInt8(exactly: report), (1...65_535).contains(length) else {
        throw Self.invalid("a probe reads report 0...255 with a length of 1...65535", decoder)
      }
      let expectation: ControllerModeProbe.Expectation
      switch (expect, offset, hex) {
      case ("Answers", nil, nil): expectation = .answers
      case ("Stalls", nil, nil): expectation = .stalls
      case ("Bytes", let offset?, let hex?):
        guard let expected = HexBytes.parse(hex), offset >= 0, offset + expected.count <= length
        else {
          throw Self.invalid(
            "probe bytes are uppercase hex pairs that fit the read length",
            decoder
          )
        }
        expectation = .bytes(offset: offset, expected: expected)
      default:
        throw Self.invalid(
          "a probe expects Answers, Stalls, or Bytes; only Bytes carries offset and bytes",
          decoder
        )
      }
      probe = ControllerModeProbe(reportID: reportID, length: length, expectation: expectation)
    }

    /// Creates the decoding error for a probe with `message`.
    private static func invalid(_ message: String, _ decoder: any Decoder) -> DecodingError {
      .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
    }
  }

  /// The record's modes: unique IDs and at most one `default`; every mode's protocol obeys the same
  /// record-level rules the default protocol does, whether the record has one mode or many.
  ///
  /// A mode's session runs only what its own protocol can (see `sessionViolation`), and `interface`
  /// selects among HID interfaces, so a raw-USB mode has none. A HID route reports no endpoint set,
  /// so only a raw-USB mode's interface signature may carry `endpoints`.
  func validateModes(codingPath: [any CodingKey]) throws {
    let path = codingPath + [DocumentKey("modes")]
    func fail(_ rule: String, _ message: String) -> DecodingError {
      fail(.rule(rule, message))
    }
    func fail(_ problem: ControllerRecordProblem) -> DecodingError {
      .dataCorrupted(problem.context(at: path))
    }
    guard !modes.isEmpty else { throw fail("error.E5007.modes.empty", "modes must not be empty") }
    guard modes.filter(\.isDefault).count <= 1 else {
      throw fail("error.E5007.modes.defaultCount", "modes need at most one mode with the id default")
    }
    guard Set(modes.map(\.id)).count == modes.count else {
      throw fail("error.E5007.modes.uniqueIDs", "mode IDs must be unique")
    }
    for mode in modes {
      let info = mode.protocolInfo
      let rawUSB = info.protocolID.usesRawUSB(storedVariant: info.protocolVariant)
      if let problem = mode.sessionViolation() { throw fail(problem) }
      if rawUSB {
        if mode.interfaceRange != nil {
          throw fail(
            "error.E5007.modes.interfaceRawUSB",
            "interface selects among HID interfaces; a raw-USB mode claims the interface its"
              + " usb transport resolves"
          )
        }
      } else if mode.match?.interfaceSignature?.endpoints != nil {
        throw fail(
          "error.E5007.modes.endpointsHID",
          "a HID mode's interfaceSignature has no endpoints; only the raw USB scanner reads"
            + " an interface's endpoint set"
        )
      }
      if inputLayouts == nil, info.protocolID.requiresRecordInputLayout {
        throw fail("error.E5007.modes.inputLayoutNeeded", "a HIDReportLayout mode needs the record's input layout")
      }
      if inputLayouts != nil, info.protocolID == .hidDescriptor {
        throw fail("error.E5007.modes.usageMapNotLayouts", "a HIDDescriptor mode reads a usage map, not input layouts")
      }
      if hidUsageMap != nil,
        !info.protocolID.protocolDescription.recordSections.contains(.hidUsageMap)
      {
        throw fail(
          "error.E5007.modes.usageMapDriver",
          "a HID usage map applies only to a driver that reads one, in every mode"
        )
      }
    }
    guard capabilitiesAreDeclared(byAnyOf: modes.map(\.protocolInfo.protocolID)) else {
      throw fail("error.E5007.modes.capabilities", "capabilities must be deltas the driver of some mode declares")
    }
  }
}
