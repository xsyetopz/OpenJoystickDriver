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
  let transport: String
  let protocolInfo: ProtocolInfo
  let usb: USBOverride?

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: DocumentKey.self)
    try container.rejectUnknown(allowed: [
      "$schema", "vendor_id", "product_id", "transport", "protocol", "usb"
    ])
    let schema = try container.decode(String.self, for: "$schema")
    guard schema == Self.schemaID else {
      throw DecodingError.dataCorruptedError(
        forKey: DocumentKey("$schema"),
        in: container,
        debugDescription: "$schema must identify the current controller contract"
      )
    }
    vendorID = try container.decode(Int.self, for: "vendor_id")
    productID = try container.decode(Int.self, for: "product_id")
    transport = try container.decode(String.self, for: "transport")
    protocolInfo = try container.decode(ProtocolInfo.self, for: "protocol")
    usb = try container.decodeOptional(USBOverride.self, for: "usb")
    if let endpoints = usb?.endpoints {
      let defaultEndpoints = protocolInfo.driver == "Xbox360" ? (129, 1) : (130, 2)
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

  struct ProtocolInfo: Decodable {
    let driver: String
    let variant: String
    let quirks: [String]?
    let startupPackets: [String]?
    let keepAliveEnabled: Bool?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "driver", "variant", "quirks", "startup_packets", "keep_alive"
      ])
      driver = try container.decode(String.self, for: "driver")
      variant = try container.decode(String.self, for: "variant")
      quirks = try container.decodeOptional([String].self, for: "quirks")
      startupPackets = try container.decodeOptional([String].self, for: "startup_packets")
      keepAliveEnabled = try container.decodeOptional(Bool.self, for: "keep_alive")
      try Self.validateUniqueNonempty(quirks, field: "quirks", codingPath: decoder.codingPath)
      try Self.validateUniqueNonempty(
        startupPackets,
        field: "startup_packets",
        codingPath: decoder.codingPath
      )
      guard let contract = Self.contracts[driver], contract.variants.contains(variant) else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath,
            debugDescription: "driver and variant must match the current controller contract"
          )
        )
      }
      let unknownQuirks = Set(quirks ?? []).subtracting(contract.quirks)
      guard unknownQuirks.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("quirks")],
            debugDescription: "quirks must match the selected driver contract"
          )
        )
      }
    }

    private static func validateUniqueNonempty(
      _ values: [String]?,
      field: String,
      codingPath: [any CodingKey]
    ) throws {
      guard let values else { return }
      guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }), Set(values).count == values.count
      else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: codingPath + [DocumentKey(field)],
            debugDescription: "\(field) must contain unique, nonempty values"
          )
        )
      }
    }

    private static let contracts: [String: (variants: Set<String>, quirks: Set<String>)] = [
      "GIP": (
        ["xboxOriginal", "xboxOne", "unknown"],
        ["dpadToButtons", "triggersToButtons", "sticksToNull", "shareOffset"]
      ),
      "Xbox360": (
        ["xbox360", "xbox360Wireless", "unknown"],
        ["dpadToButtons", "triggersToButtons", "sticksToNull"]
      ), "DS3": (["dualShock3", "unknown"], ["gyro", "accelerometer", "battery"]),
      "DS4": (
        ["dualShock4", "unknown"], ["touchpad", "gyro", "accelerometer", "battery", "lightbar"]
      ),
      "DualSense": (
        ["dualSense", "unknown"],
        [
          "touchpad", "gyro", "accelerometer", "battery", "lightbar", "microphoneMute",
          "adaptiveTriggers"
        ]
      ),
      "SteamController": (
        ["steamController", "unknown"],
        ["lizardMode", "trackpads", "gyro", "battery", "wirelessReceiver"]
      ), "SwitchPro": (["switchPro", "unknown"], ["usbHandshake", "calibration", "imu", "rumble"]),
      "XboxAdaptiveJoystick": (
        ["xboxAdaptiveJoystick", "unknown"], ["rawUSBPackets", "genericHIDPackets"]
      ), "GenericHID": (["genericHID"], [])
    ]
  }

  struct USBOverride: Decodable {
    let interface: Int?
    let configuration: String?
    let postHandshakeSettleMilliseconds: Int?
    let endpoints: Endpoints?

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: DocumentKey.self)
      try container.rejectUnknown(allowed: [
        "interface", "configuration", "post_handshake_settle_ms", "endpoints"
      ])
      guard !container.allKeys.isEmpty else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "usb must not be empty")
        )
      }
      interface = try container.decodeOptional(Int.self, for: "interface")
      configuration = try container.decodeOptional(String.self, for: "configuration")
      postHandshakeSettleMilliseconds = try container.decodeOptional(
        Int.self,
        for: "post_handshake_settle_ms"
      )
      endpoints = try container.decodeOptional(Endpoints.self, for: "endpoints")
      guard interface.map({ (1...255).contains($0) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("interface")],
            debugDescription: "interface must be in 1...255"
          )
        )
      }
      guard postHandshakeSettleMilliseconds.map({ (1...60_000).contains($0) }) ?? true else {
        throw DecodingError.dataCorrupted(
          .init(
            codingPath: decoder.codingPath + [DocumentKey("post_handshake_settle_ms")],
            debugDescription: "post_handshake_settle_ms must be in 1...60000"
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
      guard (128...255).contains(input), (1...127).contains(output) else {
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

private struct DocumentKey: CodingKey, Hashable {
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
