import Foundation

public struct RemappingDeviceScope: Codable, Equatable, Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16

  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  private enum CodingKeys: String, CodingKey {
    case vendorID = "vendor_id"
    case productID = "product_id"
  }
}

/// One conservative inner-payload bound shared by profiles, persistence, and remapping RPC.
public enum RemappingPayloadLimits {
  public static let maximumEncodedBytes = 4 * 1_024 * 1_024
  public static let maximumProfileCount = 128
}

/// Declares which foreground application receives synthesized input.
public enum RemappingApplicationScope: Codable, Equatable, Hashable, Sendable {
  case application(bundleIdentifier: String)
  case global

  private enum Kind: String, Codable {
    case application
    case global
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case bundleIdentifier = "bundle_id"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .application:
      self = .application(
        bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier)
      )
    case .global: self = .global
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .application(let bundleIdentifier):
      try container.encode(Kind.application, forKey: .type)
      try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
    case .global: try container.encode(Kind.global, forKey: .type)
    }
  }
}

public enum RemappingResponseCurve: String, Codable, CaseIterable, Hashable, Sendable {
  case linear
  case easeIn = "ease_in"
  case easeOut = "ease_out"
  case smoothStep = "smooth_step"
}

/// Axis processing applied before a binding reaches its destination.
public struct RemappingAxisTuning: Codable, Equatable, Hashable, Sendable {
  public static let deadzoneRange = 0.0...0.95
  public static let gainRange = 0.1...10.0
  public static let digitalActivationThresholdRange = 0.01...1.0
  public static let defaultDeadzone = 0.1
  public static let defaultGain = 1.0
  public static let defaultDigitalActivationThreshold = 0.5

  public let deadzone: Double
  public let gain: Double
  public let inverted: Bool
  public let responseCurve: RemappingResponseCurve
  public let digitalActivationThreshold: Double

  public init(
    deadzone: Double = Self.defaultDeadzone,
    gain: Double = Self.defaultGain,
    inverted: Bool = false,
    responseCurve: RemappingResponseCurve = .linear,
    digitalActivationThreshold: Double = Self.defaultDigitalActivationThreshold
  ) {
    self.deadzone = deadzone
    self.gain = gain
    self.inverted = inverted
    self.responseCurve = responseCurve
    self.digitalActivationThreshold = digitalActivationThreshold
  }

  public static let `default` = Self()

  private enum CodingKeys: String, CodingKey {
    case deadzone
    case gain
    case inverted
    case responseCurve = "response_curve"
    case digitalActivationThreshold = "digital_activation_threshold"
  }
}

public struct RemappingTurbo: Codable, Equatable, Hashable, Sendable {
  public static let repeatRateHzRange = 1.0...60.0
  public static let dutyCycleRange = 0.05...0.95

  public let repeatRateHz: Double
  public let dutyCycle: Double

  public init(repeatRateHz: Double, dutyCycle: Double) {
    self.repeatRateHz = repeatRateHz
    self.dutyCycle = dutyCycle
  }

  private enum CodingKeys: String, CodingKey {
    case repeatRateHz = "repeat_rate_hz"
    case dutyCycle = "duty_cycle"
  }
}

public struct RemappingBinding: Codable, Equatable, Hashable, Identifiable, Sendable {
  public let id: UUID
  public let source: RemappingSource
  public let destination: RemappingDestination
  public let axisTuning: RemappingAxisTuning?
  public let turbo: RemappingTurbo?
  public let longHold: RemappingLongHold?
  public let doubleTap: RemappingDoubleTap?

  public init(
    id: UUID = UUID(),
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    doubleTap: RemappingDoubleTap? = nil
  ) {
    self.id = id
    self.source = source
    self.destination = destination
    self.axisTuning = axisTuning
    self.turbo = turbo
    self.longHold = longHold
    self.doubleTap = doubleTap
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case source
    case destination
    case axisTuning = "axis_tuning"
    case turbo
    case longHold = "long_hold"
    case doubleTap = "double_tap"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    source = try container.decode(RemappingSource.self, forKey: .source)
    destination = try container.decode(RemappingDestination.self, forKey: .destination)
    axisTuning = try container.decodeIfPresent(RemappingAxisTuning.self, forKey: .axisTuning)
    turbo = try container.decodeIfPresent(RemappingTurbo.self, forKey: .turbo)
    longHold = try container.decodeIfPresent(RemappingLongHold.self, forKey: .longHold)
    doubleTap = try container.decodeIfPresent(RemappingDoubleTap.self, forKey: .doubleTap)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(source, forKey: .source)
    try container.encode(destination, forKey: .destination)
    try container.encodeIfPresent(axisTuning, forKey: .axisTuning)
    try container.encodeIfPresent(turbo, forKey: .turbo)
    try container.encodeIfPresent(longHold, forKey: .longHold)
    try container.encodeIfPresent(doubleTap, forKey: .doubleTap)
  }
}

/// A versioned, locally persisted controller-to-system-input mapping profile.
public struct RemappingProfile: Codable, Equatable, Identifiable, Sendable {
  public static let currentSchemaVersion = 2
  public static let maximumBindingCount = 512
  public static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes
  public static let profileNameLengthRange = 1...80
  public static let layerNameLengthRange = 1...40
  public static let bundleIdentifierLengthRange = 3...255

  public let schemaVersion: Int
  public let id: UUID
  public let name: String
  public let device: RemappingDeviceScope
  public let applicationScope: RemappingApplicationScope
  public let bindings: [RemappingBinding]
  public let chords: [RemappingChord]
  public let sequences: [RemappingSequence]
  public let layers: [RemappingLayer]

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    id: UUID = UUID(),
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope,
    bindings: [RemappingBinding],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = [],
    layers: [RemappingLayer] = []
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.device = device
    self.applicationScope = applicationScope
    self.bindings = bindings
    self.chords = chords
    self.sequences = sequences
    self.layers = layers
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case name
    case device
    case applicationScope = "application_scope"
    case bindings
    case chords
    case sequences
    case layers
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    device = try container.decode(RemappingDeviceScope.self, forKey: .device)
    applicationScope = try container.decode(
      RemappingApplicationScope.self,
      forKey: .applicationScope
    )
    bindings = try container.decode([RemappingBinding].self, forKey: .bindings)
    chords = try container.decodeIfPresent([RemappingChord].self, forKey: .chords) ?? []
    sequences = try container.decodeIfPresent([RemappingSequence].self, forKey: .sequences) ?? []
    layers = try container.decodeIfPresent([RemappingLayer].self, forKey: .layers) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(device, forKey: .device)
    try container.encode(applicationScope, forKey: .applicationScope)
    try container.encode(bindings, forKey: .bindings)
    try container.encode(chords, forKey: .chords)
    try container.encode(sequences, forKey: .sequences)
    try container.encode(layers, forKey: .layers)
  }
}
