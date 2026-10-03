import Foundation

public struct RemappingDeviceScope: Codable, Equatable, Hashable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  /// The one unit of the model the profile is for (see ``UnitIdentity``); nil for every unit.
  public let unit: String?

  public init(vendorID: UInt16, productID: UInt16, unit: String? = nil) {
    self.vendorID = vendorID
    self.productID = productID
    self.unit = unit
  }

  enum CodingKeys: String, CodingKey, CaseIterable {
    case vendorID
    case productID
    case unit
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try values.decode(UInt16.self, forKey: .vendorID)
    productID = try values.decode(UInt16.self, forKey: .productID)
    unit = try values.decodeIfPresent(String.self, forKey: .unit)
    if let unit, !UnitIdentity.isWellFormed(unit) {
      throw DecodingError.dataCorruptedError(
        forKey: .unit,
        in: values,
        debugDescription: "A unit ID is U- and 16 base64url characters."
      )
    }
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

  enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case bundleIdentifier
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    let allowed: [CodingKeys] = kind == .application ? [.type, .bundleIdentifier] : [.type]
    try container.rejectKeys(otherThan: allowed)
    switch kind {
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

  enum CodingKeys: String, CodingKey, CaseIterable {
    case deadzone
    case gain
    case inverted
    case responseCurve
    case digitalActivationThreshold
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    deadzone = try values.decode(Double.self, forKey: .deadzone)
    gain = try values.decode(Double.self, forKey: .gain)
    inverted = try values.decode(Bool.self, forKey: .inverted)
    responseCurve = try values.decode(RemappingResponseCurve.self, forKey: .responseCurve)
    digitalActivationThreshold = try values.decode(Double.self, forKey: .digitalActivationThreshold)
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

  enum CodingKeys: String, CodingKey, CaseIterable {
    case repeatRateHz
    case dutyCycle
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    repeatRateHz = try values.decode(Double.self, forKey: .repeatRateHz)
    dutyCycle = try values.decode(Double.self, forKey: .dutyCycle)
  }
}

public enum RemappingBindingBehavior: String, Codable, CaseIterable, Hashable, Sendable {
  case hold
  case toggle
  case tapOnPress = "tap_on_press"
  case tapOnRelease = "tap_on_release"
  case pulse
  case press
  case release
}

public struct RemappingBinding: Codable, Equatable, Hashable, Identifiable, Sendable {
  public static let pulseDurationRange = 1.0...5000.0
  public static let defaultPulseDurationMs = 100.0
  public let id: UUID
  public let source: RemappingSource
  public let destination: RemappingDestination
  public let behavior: RemappingBindingBehavior
  public let pulseDurationMs: Double
  public let axisTuning: RemappingAxisTuning?
  public let turbo: RemappingTurbo?
  public let longHold: RemappingLongHold?
  public let doubleTap: RemappingDoubleTap?
  public let additionalActions: [RemappingAction]

  public init(
    id: UUID = UUID(),
    source: RemappingSource,
    destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    pulseDurationMs: Double = Self.defaultPulseDurationMs,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    doubleTap: RemappingDoubleTap? = nil,
    additionalActions: [RemappingAction] = []
  ) {
    self.id = id
    self.source = source
    self.destination = destination
    self.behavior = behavior
    self.pulseDurationMs = pulseDurationMs
    self.axisTuning = axisTuning
    self.turbo = turbo
    self.longHold = longHold
    self.doubleTap = doubleTap
    self.additionalActions = additionalActions
  }

  enum CodingKeys: String, CodingKey, CaseIterable {
    case id
    case source
    case destination
    case behavior
    case pulseDurationMs
    case axisTuning
    case turbo
    case longHold
    case doubleTap
    case additionalActions
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    source = try container.decode(RemappingSource.self, forKey: .source)
    destination = try container.decode(RemappingDestination.self, forKey: .destination)
    behavior =
      try container.decodeIfPresent(RemappingBindingBehavior.self, forKey: .behavior) ?? .hold
    pulseDurationMs =
      try container.decodeIfPresent(Double.self, forKey: .pulseDurationMs)
      ?? Self.defaultPulseDurationMs
    axisTuning = try container.decodeIfPresent(RemappingAxisTuning.self, forKey: .axisTuning)
    turbo = try container.decodeIfPresent(RemappingTurbo.self, forKey: .turbo)
    longHold = try container.decodeIfPresent(RemappingLongHold.self, forKey: .longHold)
    doubleTap = try container.decodeIfPresent(RemappingDoubleTap.self, forKey: .doubleTap)
    additionalActions =
      try container.decodeIfPresent([RemappingAction].self, forKey: .additionalActions) ?? []
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(source, forKey: .source)
    try container.encode(destination, forKey: .destination)
    if behavior != .hold { try container.encode(behavior, forKey: .behavior) }
    if pulseDurationMs != Self.defaultPulseDurationMs || behavior == .pulse {
      try container.encode(pulseDurationMs, forKey: .pulseDurationMs)
    }
    try container.encodeIfPresent(axisTuning, forKey: .axisTuning)
    try container.encodeIfPresent(turbo, forKey: .turbo)
    try container.encodeIfPresent(longHold, forKey: .longHold)
    try container.encodeIfPresent(doubleTap, forKey: .doubleTap)
    if !additionalActions.isEmpty {
      try container.encode(additionalActions, forKey: .additionalActions)
    }
  }
}

public struct RemappingProfile: Codable, Equatable, Identifiable, Sendable {
  public static let maximumBindingCount = 512
  public static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes
  public static let profileNameLengthRange = 1...80
  public static let layerNameLengthRange = 1...40
  public static let bundleIdentifierLengthRange = 3...255

  public let id: UUID
  public let name: String
  public let device: RemappingDeviceScope
  public let applicationScope: RemappingApplicationScope
  public let outputPolicy: RemappingOutputPolicy
  public let physicalColor: ControllerColor?
  public let motionTuning: RemappingMotionTuning
  public let gyroOutput: RemappingGyroOutput
  public let joyConPair: RemappingJoyConPairSettings?
  public let stickMappings: [RemappingStickMapping]
  public let triggerMappings: [RemappingTriggerMapping]
  public let touchMappings: [RemappingTouchMapping]
  public let bindings: [RemappingBinding]
  public let chords: [RemappingChord]
  public let sequences: [RemappingSequence]
  public let layers: [RemappingLayer]

  public init(
    id: UUID = UUID(),
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope,
    outputPolicy: RemappingOutputPolicy = .systemInput,
    physicalColor: ControllerColor? = nil,
    motionTuning: RemappingMotionTuning = .default,
    gyroOutput: RemappingGyroOutput = .default,
    joyConPair: RemappingJoyConPairSettings? = nil,
    stickMappings: [RemappingStickMapping] = [],
    triggerMappings: [RemappingTriggerMapping] = [],
    touchMappings: [RemappingTouchMapping] = [],
    bindings: [RemappingBinding],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = [],
    layers: [RemappingLayer] = []
  ) {
    self.id = id
    self.name = name
    self.device = device
    self.applicationScope = applicationScope
    self.outputPolicy = outputPolicy
    self.physicalColor = physicalColor
    self.motionTuning = motionTuning
    self.gyroOutput = gyroOutput
    self.joyConPair = joyConPair
    self.stickMappings = stickMappings
    self.triggerMappings = triggerMappings
    self.touchMappings = touchMappings
    self.bindings = bindings
    self.chords = chords
    self.sequences = sequences
    self.layers = layers
  }

  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    device = try container.decode(RemappingDeviceScope.self, forKey: .device)
    applicationScope = try container.decode(
      RemappingApplicationScope.self,
      forKey: .applicationScope
    )
    outputPolicy =
      try container.decodeIfPresent(RemappingOutputPolicy.self, forKey: .outputPolicy)
      ?? .systemInput
    physicalColor = try container.decodeIfPresent(ControllerColor.self, forKey: .physicalColor)
    motionTuning =
      try container.decodeIfPresent(RemappingMotionTuning.self, forKey: .motionTuning) ?? .default
    gyroOutput =
      try container.decodeIfPresent(RemappingGyroOutput.self, forKey: .gyroOutput) ?? .default
    joyConPair = try container.decodeIfPresent(
      RemappingJoyConPairSettings.self,
      forKey: .joyConPair
    )
    stickMappings =
      try container.decodeIfPresent([RemappingStickMapping].self, forKey: .stickMappings) ?? []
    triggerMappings =
      try container.decodeIfPresent([RemappingTriggerMapping].self, forKey: .triggerMappings) ?? []
    touchMappings =
      try container.decodeIfPresent([RemappingTouchMapping].self, forKey: .touchMappings) ?? []
    bindings = try container.decode([RemappingBinding].self, forKey: .bindings)
    chords = try container.decodeIfPresent([RemappingChord].self, forKey: .chords) ?? []
    sequences = try container.decodeIfPresent([RemappingSequence].self, forKey: .sequences) ?? []
    layers = try container.decodeIfPresent([RemappingLayer].self, forKey: .layers) ?? []
  }
}
