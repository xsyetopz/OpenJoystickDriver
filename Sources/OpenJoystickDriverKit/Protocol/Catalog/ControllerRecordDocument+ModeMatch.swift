import Foundation

extension ControllerRecordDocument {
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
      var found = ControllerModeMatch()
      if let name = try container.decodeOptional(String.self, for: "link") {
        guard let link = PhysicalTransport(rawValue: name) else {
          throw ModeDocument.invalid(
            "link",
            "link is USB, BluetoothClassic, BluetoothLE or ProprietaryRadioReceiver",
            decoder
          )
        }
        found.link = link
      }
      found.interfaceSignature =
        try container.decodeOptional(
          ModeInterfaceSignatureDocument.self,
          for: "interfaceSignature"
        )?
        .signature
      found.manufacturer = try Self.text("manufacturer", container, decoder)
      found.product = try Self.text("product", container, decoder)
      found.bcdDevice = try container.decodeOptional(BCDRangeDocument.self, for: "bcdDevice")?.range
      if let entries = try container.decodeOptional([ModeProbeDocument].self, for: "probes") {
        guard !entries.isEmpty else {
          throw ModeDocument.invalid("probes", "a mode needs at least one probe", decoder)
        }
        found.probes = entries.map(\.probe)
      }
      self.match = found
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
        guard let value = UInt8(exactly: try container.decode(Int.self, for: key)) else {
          throw ModeDocument.invalid(key, "\(key) is 0...255", decoder)
        }
        return value
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
      var parsed = ControllerModeMatch.InterfaceSignature.Endpoint()
      if let address = try container.decodeOptional(Int.self, for: "address") {
        guard let byte = UInt8(exactly: address) else {
          throw ModeDocument.invalid("address", "address is 0...255", decoder)
        }
        parsed.address = byte
      }
      if let name = try container.decodeOptional(String.self, for: "direction") {
        guard let direction = USBEndpointDirection(rawValue: name) else {
          throw ModeDocument.invalid("direction", "direction is In or Out", decoder)
        }
        parsed.direction = direction
      }
      if let name = try container.decodeOptional(String.self, for: "transferType") {
        guard let type = USBEndpointTransferType(rawValue: name), type != .unknown else {
          throw ModeDocument.invalid(
            "transferType",
            "transferType is Control, Isochronous, Bulk, or Interrupt",
            decoder
          )
        }
        parsed.transferType = type
      }
      if let size = try container.decodeOptional(Int.self, for: "maxPacketSize") {
        guard let word = UInt16(exactly: size) else {
          throw ModeDocument.invalid("maxPacketSize", "maxPacketSize is 0...65535", decoder)
        }
        parsed.maxPacketSize = word
      }
      self.endpoint = parsed
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
}
