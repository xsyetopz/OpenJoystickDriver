import Foundation

/// Per-device transport configuration resolved from controller records.
public struct DeviceTransportProfile: Equatable, Sendable {
  public let inputEndpoint: UInt8
  public let outputEndpoint: UInt8
  public let interfaceNumber: UInt8
  public let alternateSetting: UInt8
  public let hasInterfaceOverride: Bool
  public let hasEndpointOverride: Bool
  /// When true, pipeline calls setConfiguration(1) before claiming interface.
  /// Required for controllers that enumerate unconfigured (e.g. Vader 5S).
  public let needsSetConfiguration: Bool
  /// Delay after protocol handshake and before the first IN read.
  public let postHandshakeSettleNanoseconds: UInt64

  public init(
    inputEndpoint: UInt8,
    outputEndpoint: UInt8,
    interfaceNumber: UInt8 = 0,
    alternateSetting: UInt8 = 0,
    hasInterfaceOverride: Bool = false,
    hasEndpointOverride: Bool = false,
    needsSetConfiguration: Bool,
    postHandshakeSettleNanoseconds: UInt64 = 0
  ) {
    self.inputEndpoint = inputEndpoint
    self.outputEndpoint = outputEndpoint
    self.interfaceNumber = interfaceNumber
    self.alternateSetting = alternateSetting
    self.hasInterfaceOverride = hasInterfaceOverride
    self.hasEndpointOverride = hasEndpointOverride
    self.needsSetConfiguration = needsSetConfiguration
    self.postHandshakeSettleNanoseconds = postHandshakeSettleNanoseconds
  }

  public static let gipDefault = Self(
    inputEndpoint: 0x82,
    outputEndpoint: 0x02,
    needsSetConfiguration: false
  )
}

/// Controller protocol family/variant used for long-term compatibility metadata.
public enum ControllerProtocolVariant: String, Sendable {
  case xboxOriginal
  case xbox360
  case xbox360Wireless
  case xboxOne
  case dualShock3
  case dualShock4
  case dualSense
  case steamController
  case switchPro
  case xboxAdaptiveJoystick
  case genericHID
  case unknown
}

/// Stable mapping flags modeled after Linux xpad's per-device quirks.
public struct ControllerMappingOptions: OptionSet, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let dpadToButtons = Self(rawValue: 1 << 0)
  public static let triggersToButtons = Self(rawValue: 1 << 1)
  public static let sticksToNull = Self(rawValue: 1 << 2)
  public static let shareButton = Self(rawValue: 1 << 3)
  public static let paddles = Self(rawValue: 1 << 4)
  public static let profileButton = Self(rawValue: 1 << 5)
  public static let shareOffset = Self(rawValue: 1 << 6)

  public var names: [String] {
    var result: [String] = []
    if contains(.dpadToButtons) { result.append("dpadToButtons") }
    if contains(.triggersToButtons) { result.append("triggersToButtons") }
    if contains(.sticksToNull) { result.append("sticksToNull") }
    if contains(.shareButton) { result.append("shareButton") }
    if contains(.paddles) { result.append("paddles") }
    if contains(.profileButton) { result.append("profileButton") }
    if contains(.shareOffset) { result.append("shareOffset") }
    return result
  }
}

/// Complete runtime profile for one physical controller model.
public struct DeviceRuntimeProfile: Sendable {
  public let parserName: String
  public let virtualProfile: VirtualDeviceProfile
  public let transportProfile: DeviceTransportProfile
  public let protocolVariant: ControllerProtocolVariant
  public let mappingFlags: [String]
  public let mappingOptions: ControllerMappingOptions
  public let preferredBackends: [VirtualControllerBackendID]
  public let gipStartupPackets: [GIPStartupPacket]
  public let hardwareVerified: Bool
}

/// Loads the canonical VID/PID controller records bundled with the driver.
struct DeviceCatalog: Sendable {
  private let profiles: [String: DeviceRuntimeProfile]
  private let rawUSBPipelineIdentifiers: Set<String>
  let hidProfileIdentifiers: [DeviceIdentifier]

  init() {
    do {
      var loaded: [String: DeviceRuntimeProfile] = [:]
      var hid: [DeviceIdentifier] = []
      var rawUSBPipelineIdentifiers: Set<String> = []
      for record in try Self.loadRecords() {
        let key = "\(record.vendorID):\(record.productID)"
        guard loaded[key] == nil else { throw CatalogError("duplicate controller identity \(key)") }
        loaded[key] = try Self.makeRuntimeProfile(record)
        if Self.supportsRawUSBPipeline(record) { rawUSBPipelineIdentifiers.insert(key) }
        if record.transport == "hid" {
          hid.append(
            DeviceIdentifier(vendorID: UInt16(record.vendorID), productID: UInt16(record.productID))
          )
        }
      }
      profiles = loaded
      self.rawUSBPipelineIdentifiers = rawUSBPipelineIdentifiers
      hidProfileIdentifiers = hid.sorted {
        if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
        return $0.productID < $1.productID
      }
    } catch { fatalError("[DeviceCatalog] Invalid controller catalog: \(error)") }
  }

  func parserName(for identifier: DeviceIdentifier) -> String {
    profiles[key(for: identifier)]?.parserName ?? "GenericHID"
  }

  func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    profiles[key(for: identifier)]?.virtualProfile ?? .default
  }

  func transportProfile(for identifier: DeviceIdentifier) -> DeviceTransportProfile {
    profiles[key(for: identifier)]?.transportProfile ?? .gipDefault
  }

  func runtimeProfile(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile {
    profiles[key(for: identifier)]
      ?? DeviceRuntimeProfile(
        parserName: "GenericHID",
        virtualProfile: .default,
        transportProfile: .gipDefault,
        protocolVariant: .genericHID,
        mappingFlags: [],
        mappingOptions: [],
        preferredBackends: [.driverKitHID, .userSpaceHID],
        gipStartupPackets: GIPStartupPacket.defaultSequence,
        hardwareVerified: false
      )
  }

  func supportsRawUSBPipeline(for identifier: DeviceIdentifier) -> Bool {
    rawUSBPipelineIdentifiers.contains(key(for: identifier))
  }

  private func key(for identifier: DeviceIdentifier) -> String {
    "\(identifier.vendorID):\(identifier.productID)"
  }

  private static func loadRecords() throws -> [ControllerRecord] {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
      .filter { isControllerRecordFilename($0.lastPathComponent) }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    guard !urls.isEmpty else { throw CatalogError("controller catalog is empty") }

    let decoder = JSONDecoder()
    return try urls.map { url in
      let data = try Data(contentsOf: url)
      try validateShape(JSONSerialization.jsonObject(with: data), path: url.path)
      do {
        let record = try decoder.decode(ControllerRecord.self, from: data)
        let expectedName = String(format: "%04x-%04x.json", record.vendorID, record.productID)
        guard url.lastPathComponent == expectedName else {
          throw CatalogError("\(url.path): filename must be \(expectedName)")
        }
        return record
      } catch { throw CatalogError("\(url.path): \(error)") }
    }
  }

  private static func isControllerRecordFilename(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(5)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  private static func validateShape(_ value: Any, path: String) throws {
    guard let root = value as? [String: Any] else {
      throw CatalogError("\(path): root must be an object")
    }
    try requireKeys(
      root,
      allowed: [
        "$schema", "vendor_id", "product_id", "transport", "protocol", "usb", "provenance",
      ],
      required: ["$schema", "vendor_id", "product_id", "transport", "protocol", "provenance"],
      path: path
    )
    guard root["$schema"] as? String == ControllerRecord.schemaID else {
      throw CatalogError("\(path): invalid $schema")
    }
    guard let protocolObject = root["protocol"] as? [String: Any] else {
      throw CatalogError("\(path): protocol must be an object")
    }
    try requireKeys(
      protocolObject,
      allowed: ["driver", "variant", "flags", "startup_packets"],
      required: ["driver", "variant"],
      path: "\(path).protocol"
    )
    guard let provenance = root["provenance"] as? [String: Any] else {
      throw CatalogError("\(path): provenance must be an object")
    }
    try requireKeys(
      provenance,
      allowed: ["source", "revision", "verified"],
      required: ["source", "verified"],
      path: "\(path).provenance"
    )
    if let usb = root["usb"] as? [String: Any] {
      try requireKeys(
        usb,
        allowed: ["interface", "configuration", "post_handshake_settle_ms", "endpoints"],
        required: [],
        path: "\(path).usb"
      )
      if let endpoints = usb["endpoints"] as? [String: Any] {
        try requireKeys(
          endpoints,
          allowed: ["in", "out"],
          required: ["in", "out"],
          path: "\(path).usb.endpoints"
        )
      }
    }
  }

  private static func requireKeys(
    _ object: [String: Any],
    allowed: Set<String>,
    required: Set<String>,
    path: String
  ) throws {
    let keys = Set(object.keys)
    let unknown = keys.subtracting(allowed).sorted()
    let missing = required.subtracting(keys).sorted()
    if !unknown.isEmpty {
      throw CatalogError("\(path): unknown fields \(unknown.joined(separator: ", "))")
    }
    if !missing.isEmpty {
      throw CatalogError("\(path): missing fields \(missing.joined(separator: ", "))")
    }
  }

  private static func makeRuntimeProfile(_ record: ControllerRecord) throws -> DeviceRuntimeProfile
  {
    guard (1...65_535).contains(record.vendorID), (0...65_535).contains(record.productID) else {
      throw CatalogError("invalid controller identity \(record.vendorID):\(record.productID)")
    }
    guard record.transport == "usb" || record.transport == "hid" else {
      throw CatalogError("unsupported transport \(record.transport)")
    }
    let driver = record.protocolInfo.driver
    guard let contract = protocolContracts[driver] else {
      throw CatalogError("unsupported parser \(driver)")
    }
    guard contract.variants.contains(record.protocolInfo.variant),
      let variant = ControllerProtocolVariant(rawValue: record.protocolInfo.variant)
    else {
      throw CatalogError(
        "unsupported protocol variant \(record.protocolInfo.variant) for \(driver)"
      )
    }

    let flags = record.protocolInfo.flags ?? []
    let unknownFlags = Set(flags).subtracting(contract.flags).sorted()
    guard unknownFlags.isEmpty else {
      throw CatalogError("unsupported flags \(unknownFlags.joined(separator: ", "))")
    }
    guard Set(flags).count == flags.count else {
      throw CatalogError("duplicate flags for \(record.vendorID):\(record.productID)")
    }

    let defaultEndpoints = driver == "Xbox360" ? (input: 129, output: 1) : (input: 130, output: 2)
    let inputEndpoint = record.usb?.endpoints?.input ?? defaultEndpoints.input
    let outputEndpoint = record.usb?.endpoints?.output ?? defaultEndpoints.output
    if record.usb != nil && record.transport != "usb" {
      throw CatalogError("USB overrides require usb transport")
    }
    if let configuration = record.usb?.configuration, configuration != "set1-before-claim" {
      throw CatalogError("unsupported USB configuration \(configuration)")
    }
    let interfaceNumber = record.usb?.interface ?? 0
    let settleMilliseconds = record.usb?.postHandshakeSettleMilliseconds ?? 0
    if record.usb?.interface == 0 || record.usb?.postHandshakeSettleMilliseconds == 0 {
      throw CatalogError("protocol-default USB values must be omitted")
    }
    if let endpoints = record.usb?.endpoints,
      endpoints.input == defaultEndpoints.input && endpoints.output == defaultEndpoints.output
    {
      throw CatalogError("protocol-default endpoints must be omitted")
    }
    if let usb = record.usb, usb.interface == nil, usb.configuration == nil,
      usb.postHandshakeSettleMilliseconds == nil, usb.endpoints == nil
    {
      throw CatalogError("empty USB override")
    }
    guard supportedSources.contains(record.provenance.source) else {
      throw CatalogError("unsupported provenance source \(record.provenance.source)")
    }
    guard (128...255).contains(inputEndpoint), (1...127).contains(outputEndpoint),
      (0...255).contains(interfaceNumber), settleMilliseconds >= 0
    else { throw CatalogError("invalid USB override for \(record.vendorID):\(record.productID)") }

    let packetNames = record.protocolInfo.startupPackets ?? []
    let startupPackets = packetNames.compactMap(GIPStartupPacket.init(rawValue:))
    guard startupPackets.count == packetNames.count else {
      throw CatalogError("unsupported startup packets \(packetNames)")
    }
    guard packetNames.isEmpty || driver == "GIP" else {
      throw CatalogError("startup packets require the GIP parser")
    }

    return DeviceRuntimeProfile(
      parserName: driver,
      virtualProfile: .default,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(inputEndpoint),
        outputEndpoint: UInt8(outputEndpoint),
        interfaceNumber: UInt8(interfaceNumber),
        hasInterfaceOverride: record.usb?.interface != nil,
        hasEndpointOverride: record.usb?.endpoints != nil,
        needsSetConfiguration: record.usb?.configuration == "set1-before-claim",
        postHandshakeSettleNanoseconds: UInt64(settleMilliseconds) * 1_000_000
      ),
      protocolVariant: variant,
      mappingFlags: flags,
      mappingOptions: mappingOptions(from: flags),
      preferredBackends: [.driverKitHID, .userSpaceHID],
      gipStartupPackets: startupPackets.isEmpty ? GIPStartupPacket.defaultSequence : startupPackets,
      hardwareVerified: record.provenance.verified
    )
  }

  private static func supportsRawUSBPipeline(_ record: ControllerRecord) -> Bool {
    record.transport == "usb" && rawUSBParserNames.contains(record.protocolInfo.driver)
  }

  private static func mappingOptions(from flags: [String]) -> ControllerMappingOptions {
    var result: ControllerMappingOptions = []
    for flag in flags {
      switch flag {
      case "dpadToButtons": result.insert(.dpadToButtons)
      case "triggersToButtons": result.insert(.triggersToButtons)
      case "sticksToNull": result.insert(.sticksToNull)
      case "shareButton": result.insert(.shareButton)
      case "paddles": result.insert(.paddles)
      case "profileButton": result.insert(.profileButton)
      case "shareOffset": result.insert(.shareOffset)
      default: break
      }
    }
    return result
  }

  private static let protocolContracts: [String: (variants: Set<String>, flags: Set<String>)] = [
    "GIP": (
      ["xboxOriginal", "xboxOne", "unknown"],
      [
        "dpadToButtons", "triggersToButtons", "sticksToNull", "shareButton", "paddles",
        "profileButton", "shareOffset",
      ]
    ),
    "Xbox360": (
      ["xbox360", "xbox360Wireless", "unknown"],
      ["dpadToButtons", "triggersToButtons", "sticksToNull"]
    ),
    "DS3": (
      ["dualShock3", "unknown"],
      ["gyro", "accelerometer", "battery", "experimental", "needsHardwareTest"]
    ),
    "DS4": (
      ["dualShock4", "unknown"], ["touchpad", "gyro", "accelerometer", "battery", "lightbar"]
    ),
    "DualSense": (
      ["dualSense", "unknown"],
      [
        "touchpad", "gyro", "accelerometer", "battery", "lightbar", "microphoneMute",
        "adaptiveTriggers", "experimental", "needsHardwareTest",
      ]
    ),
    "SteamController": (
      ["steamController", "unknown"],
      [
        "lizardMode", "trackpads", "gyro", "battery", "wirelessReceiver", "experimental",
        "needsHardwareTest",
      ]
    ),
    "SwitchPro": (
      ["switchPro", "unknown"],
      ["usbHandshake", "calibration", "imu", "rumble", "experimental", "needsHardwareTest"]
    ),
    "XboxAdaptiveJoystick": (
      ["xboxAdaptiveJoystick", "unknown"],
      ["rawUSBPackets", "genericHIDPackets", "experimental", "needsHardwareTest"]
    ),
    "GenericHID": (["genericHID"], []),
  ]

  private static let supportedSources: Set<String> = [
    "local-hardware", "linux-xpad.c", "linux-hid-steam.c", "linux-hid-playstation.c",
    "linux-hid-sony.c", "linux-hid-nintendo.c", "tester-packets",
  ]

  private static let rawUSBParserNames: Set<String> = ["GIP", "Xbox360"]

  private struct ControllerRecord: Decodable {
    static let schemaID =
      "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/"
      + "Resources/Schemas/controller.schema.json"

    let vendorID: Int
    let productID: Int
    let transport: String
    let protocolInfo: ProtocolInfo
    let usb: USBOverride?
    let provenance: Provenance

    enum CodingKeys: String, CodingKey {
      case vendorID = "vendor_id"
      case productID = "product_id"
      case transport
      case protocolInfo = "protocol"
      case usb
      case provenance
    }

    struct ProtocolInfo: Decodable {
      let driver: String
      let variant: String
      let flags: [String]?
      let startupPackets: [String]?

      enum CodingKeys: String, CodingKey {
        case driver
        case variant
        case flags
        case startupPackets = "startup_packets"
      }
    }

    struct USBOverride: Decodable {
      let interface: Int?
      let configuration: String?
      let postHandshakeSettleMilliseconds: Int?
      let endpoints: Endpoints?

      enum CodingKeys: String, CodingKey {
        case interface
        case configuration
        case postHandshakeSettleMilliseconds = "post_handshake_settle_ms"
        case endpoints
      }
    }

    struct Endpoints: Decodable {
      let input: Int
      let output: Int

      enum CodingKeys: String, CodingKey {
        case input = "in"
        case output = "out"
      }
    }

    struct Provenance: Decodable {
      let source: String
      let revision: String?
      let verified: Bool
    }
  }

  private struct CatalogError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
  }
}
