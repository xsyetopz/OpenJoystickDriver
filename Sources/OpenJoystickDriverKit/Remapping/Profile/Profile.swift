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

  private enum CodingKeys: String, CodingKey {
    case id
    case source
    case destination
    case behavior
    case pulseDurationMs = "pulse_duration_ms"
    case axisTuning = "axis_tuning"
    case turbo
    case longHold = "long_hold"
    case doubleTap = "double_tap"
    case additionalActions = "additional_actions"
  }

  public init(from decoder: any Decoder) throws {
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

/// A versioned, locally persisted controller-to-system-input mapping profile.
public struct RemappingProfile: Codable, Equatable, Identifiable, Sendable {
  public static let currentSchemaVersion = 3
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
  public let outputPolicy: RemappingOutputPolicy
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
    schemaVersion: Int = Self.currentSchemaVersion,
    id: UUID = UUID(),
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope,
    outputPolicy: RemappingOutputPolicy = .systemInput,
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
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.device = device
    self.applicationScope = applicationScope
    self.outputPolicy = outputPolicy
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

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case id
    case name
    case device
    case applicationScope = "application_scope"
    case outputPolicy = "output_policy"
    case motionTuning = "motion_tuning"
    case gyroOutput = "gyro_output"
    case joyConPair = "joy_con_pair"
    case stickMappings = "stick_mappings"
    case triggerMappings = "trigger_mappings"
    case touchMappings = "touch_mappings"
    case bindings
    case chords
    case sequences
    case layers
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentSchemaVersion else {
      throw RemappingValidationError.unsupportedSchemaVersion(schemaVersion)
    }
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

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(device, forKey: .device)
    try container.encode(applicationScope, forKey: .applicationScope)
    try container.encode(outputPolicy, forKey: .outputPolicy)
    if motionTuning != .default { try container.encode(motionTuning, forKey: .motionTuning) }
    if gyroOutput != .default { try container.encode(gyroOutput, forKey: .gyroOutput) }
    try container.encodeIfPresent(joyConPair, forKey: .joyConPair)
    if !stickMappings.isEmpty { try container.encode(stickMappings, forKey: .stickMappings) }
    if !triggerMappings.isEmpty { try container.encode(triggerMappings, forKey: .triggerMappings) }
    if !touchMappings.isEmpty { try container.encode(touchMappings, forKey: .touchMappings) }
    try container.encode(bindings, forKey: .bindings)
    try container.encode(chords, forKey: .chords)
    try container.encode(sequences, forKey: .sequences)
    try container.encode(layers, forKey: .layers)
  }
}
