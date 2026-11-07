import Foundation

/// The controller model, and optionally the one unit of it, that a profile is for.
public struct RemappingDeviceScope: Codable, Equatable, Hashable, Sendable {
  /// USB vendor ID of the controller model.
  public let vendorID: UInt16
  /// USB product ID of the controller model.
  public let productID: UInt16
  /// The one unit of the model the profile is for (see ``ControllerPortKey``); nil for every unit.
  public let unit: String?

  /// Creates a device scope.
  public init(vendorID: UInt16, productID: UInt16, unit: String? = nil) {
    self.vendorID = vendorID
    self.productID = productID
    self.unit = unit
  }

  /// Profile document keys of a device scope.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `vendorID`.
    case vendorID
    /// The JSON key of `productID`.
    case productID
    /// The JSON key of `unit`.
    case unit
  }

  /// Decodes a device scope from a profile document.
  /// - Throws: `DecodingError` for an unknown key, a missing key, a bad value, or a `unit` that is
  ///   not a
  ///   port key.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try values.decode(UInt16.self, forKey: .vendorID)
    productID = try values.decode(UInt16.self, forKey: .productID)
    unit = try values.decodeIfPresent(String.self, forKey: .unit)
    if let unit, ControllerPortKey(rawValue: unit) == nil {
      throw DecodingError.dataCorruptedError(
        forKey: .unit,
        in: values,
        debugDescription: "A port key is U- and 16 base64url characters."
      )
    }
  }
}

/// One conservative inner-payload bound shared by profiles, persistence, and remapping RPC.
public enum RemappingPayloadLimits {
  /// Largest encoded profile or payload, in bytes.
  public static let maximumEncodedBytes = 4 * 1_024 * 1_024
  /// Largest number of profiles in one payload.
  public static let maximumProfileCount = 128
}

/// Declares which foreground application receives synthesized input.
public enum RemappingApplicationScope: Codable, Equatable, Hashable, Sendable {
  /// Only the application with this bundle identifier.
  case application(appID: String)
  /// Whatever application is in front.
  case global

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    /// The `Application` case.
    case application = "Application"
    /// The `Global` case.
    case global = "Global"
  }

  /// Profile document keys of an application scope.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `type`.
    case type
    /// The JSON key of `appID`.
    case appID
  }

  /// Decodes an application scope from a profile document.
  ///
  /// The `type` field selects the case, and `appID` is allowed only for `Application`.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    let allowed: [CodingKeys] = kind == .application ? [.type, .appID] : [.type]
    try container.rejectKeys(otherThan: allowed)
    switch kind {
    case .application:
      self = .application(
        appID: try container.decode(String.self, forKey: .appID)
      )
    case .global: self = .global
    }
  }

  /// Encodes the case under its `type` value, with `appID` only for an application.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .application(let appID):
      try container.encode(Kind.application, forKey: .type)
      try container.encode(appID, forKey: .appID)
    case .global: try container.encode(Kind.global, forKey: .type)
    }
  }
}

/// Shape of the curve that maps an axis deflection to its output.
public enum RemappingResponseCurve: String, Codable, CaseIterable, Hashable, Sendable {
  /// Output equals the deflection.
  case linear = "Linear"
  /// Output grows slowly at first: the deflection squared.
  case easeIn = "EaseIn"
  /// Output grows quickly at first: the mirror of ``easeIn``.
  case easeOut = "EaseOut"
  /// Output eases in and out along a smooth S curve.
  case smoothStep = "SmoothStep"
}

/// Axis processing applied before a binding reaches its destination.
public struct RemappingAxisTuning: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``deadzone``.
  public static let deadzoneRange = 0.0...0.95
  /// Allowed range of ``gain``.
  public static let gainRange = 0.1...10.0
  /// Allowed range of ``digitalActivationThreshold``.
  public static let digitalActivationThresholdRange = 0.01...1.0
  /// ``deadzone`` used when none is given.
  public static let defaultDeadzone = 0.1
  /// ``gain`` used when none is given.
  public static let defaultGain = 1.0
  /// ``digitalActivationThreshold`` used when none is given.
  public static let defaultDigitalActivationThreshold = 0.5

  /// Deflection below which the axis reads as centered; the range above it is rescaled to 0 to 1.
  public let deadzone: Double
  /// Multiplier applied after the response curve.
  public let gain: Double
  /// Whether the output is negated.
  public let inverted: Bool
  /// Curve applied to the rescaled deflection.
  public let responseCurve: RemappingResponseCurve
  /// Tuned deflection at which an axis direction counts as pressed when it is a digital source.
  public let digitalActivationThreshold: Double

  /// Creates an axis tuning.
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

  /// Tuning with the default dead zone, gain, a linear curve and no inversion.
  public static let `default` = Self()

  /// Profile document keys of an axis tuning.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `deadzone`.
    case deadzone
    /// The JSON key of `gain`.
    case gain
    /// The JSON key of `inverted`.
    case inverted
    /// The JSON key of `responseCurve`.
    case responseCurve
    /// The JSON key of `digitalActivationThreshold`.
    case digitalActivationThreshold
  }

  /// Decodes an axis tuning from a profile document, which must give every field.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
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

/// Repeats a button output while its source is held.
public struct RemappingTurbo: Codable, Equatable, Hashable, Sendable {
  /// Allowed range of ``repeatRateHz``.
  public static let repeatRateHzRange = 1.0...60.0
  /// Allowed range of ``dutyCycle``.
  public static let dutyCycleRange = 0.05...0.95
  /// Allowed range of ``initialDelayMs``.
  public static let initialDelayMsRange = 0.0...2500.0
  /// Allowed range of ``maxRepeats``.
  public static let maxRepeatsRange = 1...500

  /// Presses per second.
  public let repeatRateHz: Double
  /// Fraction of each repeat period that the output is down.
  public let dutyCycle: Double
  /// Time from the first press to the first repeat in milliseconds; 0 when omitted.
  public let initialDelayMs: Double
  /// Repeats after the first press until the source is released; `nil` repeats while held.
  public let maxRepeats: Int?

  /// Creates a turbo setting.
  public init(
    repeatRateHz: Double,
    dutyCycle: Double,
    initialDelayMs: Double = 0,
    maxRepeats: Int? = nil
  ) {
    self.repeatRateHz = repeatRateHz
    self.dutyCycle = dutyCycle
    self.initialDelayMs = initialDelayMs
    self.maxRepeats = maxRepeats
  }

  /// Profile document keys of a turbo setting.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `repeatRateHz`.
    case repeatRateHz
    /// The JSON key of `dutyCycle`.
    case dutyCycle
    /// The JSON key of `initialDelayMs`.
    case initialDelayMs
    /// The JSON key of `maxRepeats`.
    case maxRepeats
  }

  /// Decodes a turbo setting from a profile document; the rate and duty cycle are required.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    repeatRateHz = try values.decode(Double.self, forKey: .repeatRateHz)
    dutyCycle = try values.decode(Double.self, forKey: .dutyCycle)
    initialDelayMs = try values.decodeIfPresent(Double.self, forKey: .initialDelayMs) ?? 0
    maxRepeats = try values.decodeIfPresent(Int.self, forKey: .maxRepeats)
  }

  /// Encodes a turbo setting and leaves out a zero delay and an absent cap.
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(repeatRateHz, forKey: .repeatRateHz)
    try values.encode(dutyCycle, forKey: .dutyCycle)
    if initialDelayMs != 0 { try values.encode(initialDelayMs, forKey: .initialDelayMs) }
    try values.encodeIfPresent(maxRepeats, forKey: .maxRepeats)
  }
}

/// How a binding drives its destination from its source.
public enum RemappingBindingBehavior: String, Codable, CaseIterable, Hashable, Sendable {
  /// The destination is down while the source is active.
  case hold = "Hold"
  /// Each activation of the source switches the destination between down and up.
  case toggle = "Toggle"
  /// A press and release of the destination when the source activates.
  case tapOnPress = "TapOnPress"
  /// A press and release of the destination when the source deactivates, if it was activated.
  case tapOnRelease = "TapOnRelease"
  /// The destination goes down on activation and up after ``RemappingBinding/pulseDurationMs``.
  case pulse = "Pulse"
  /// The destination goes down on activation and stays down.
  case press = "Press"
  /// Releases the held outputs of the destination on activation.
  case release = "Release"
}

/// Assigns one controller source to one destination, with timing, tuning and extra actions.
public struct RemappingBinding: Codable, Equatable, Hashable, Identifiable, Sendable {
  /// Allowed range of ``pulseDurationMs``.
  public static let pulseDurationRange = 1.0...5000.0
  /// ``pulseDurationMs`` used when none is given.
  public static let defaultPulseDurationMs = 100.0
  /// Stable identity of the binding inside its profile.
  public let id: UUID
  /// Controller input that triggers the binding.
  public let source: RemappingSource
  /// Output that the binding drives.
  public let destination: RemappingDestination
  /// How the source drives the destination.
  public let behavior: RemappingBindingBehavior
  /// Time the destination stays down for ``RemappingBindingBehavior/pulse``, in milliseconds.
  public let pulseDurationMs: Double
  /// Axis processing; required for an axis source and refused for any other source.
  public let axisTuning: RemappingAxisTuning?
  /// Repeat setting for a button destination while the source is held.
  public let turbo: RemappingTurbo?
  /// Alternate action when the source is held past a duration.
  public let longHold: RemappingLongHold?
  /// Alternate actions when the source is tapped several times in a row, by tap count.
  public let multiTap: [RemappingMultiTap]
  /// Further actions that the same source triggers.
  public let additionalActions: [RemappingAction]

  /// Creates a binding.
  public init(
    id: UUID = UUID(),
    source: RemappingSource,
    destination: RemappingDestination,
    behavior: RemappingBindingBehavior = .hold,
    pulseDurationMs: Double = Self.defaultPulseDurationMs,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    multiTap: [RemappingMultiTap] = [],
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
    self.multiTap = multiTap
    self.additionalActions = additionalActions
  }

  /// Profile document keys of a binding.
  enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `id`.
    case id
    /// The JSON key of `source`.
    case source
    /// The JSON key of `destination`.
    case destination
    /// The JSON key of `behavior`.
    case behavior
    /// The JSON key of `pulseDurationMs`.
    case pulseDurationMs
    /// The JSON key of `axisTuning`.
    case axisTuning
    /// The JSON key of `turbo`.
    case turbo
    /// The JSON key of `longHold`.
    case longHold
    /// The JSON key of `multiTap`.
    case multiTap
    /// The JSON key of `additionalActions`.
    case additionalActions
  }

  /// Decodes a binding from a profile document; omitted behavior, pulse duration and additional
  /// actions take their defaults.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
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
    multiTap =
      try container.decodeIfPresent([RemappingMultiTap].self, forKey: .multiTap) ?? []
    additionalActions =
      try container.decodeIfPresent([RemappingAction].self, forKey: .additionalActions) ?? []
  }

  /// Encodes a binding and leaves out the fields that hold their default.
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
    if !multiTap.isEmpty { try container.encode(multiTap, forKey: .multiTap) }
    if !additionalActions.isEmpty {
      try container.encode(additionalActions, forKey: .additionalActions)
    }
  }
}

/// A named set of mappings for one controller model and one application scope.
public struct RemappingProfile: Codable, Equatable, Identifiable, Sendable {
  /// Returns the form of a profile name that the library compares.
  ///
  /// Two profiles cannot have names that are equal in this form.
  public static func normalizedName(_ name: String) -> String {
    name.lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  /// The `kind` of a profile document.
  public static let kind = "Profile"
  /// Largest number of mappings; each binding, extra action, chord, sequence, layer, trigger
  /// mapping and touch mapping counts as one.
  public static let maximumBindingCount = 512
  /// Largest encoded profile, in bytes.
  public static let maximumEncodedBytes = RemappingPayloadLimits.maximumEncodedBytes
  /// Allowed length of a profile name, in characters.
  public static let profileNameLengthRange = 1...80
  /// Allowed length of a layer name, in characters.
  public static let layerNameLengthRange = 1...40
  /// Allowed length of an application bundle identifier, in bytes.
  public static let appIDLengthRange = 3...255

  /// Stable identity of the profile.
  public let id: UUID
  /// Name shown to the user.
  public let name: String
  /// Controller model, and optionally unit, that the profile is for.
  public let device: RemappingDeviceScope
  /// Foreground application that receives synthesized input.
  public let applicationScope: RemappingApplicationScope
  /// Where controls with no mapping go and how much physical ownership is required.
  public let outputPolicy: RemappingOutputPolicy
  /// Light color the profile sets on the physical controller, or `nil` to leave it.
  public let physicalColor: ControllerColor?
  /// Angular motion tuning.
  public let motionTuning: RemappingMotionTuning
  /// Gyro output.
  public let gyroOutput: RemappingGyroOutput
  /// Settings for a paired left and right Joy-Con session, or `nil` for a single controller.
  public let joyConPair: RemappingJoyConPairSettings?
  /// Advanced stick mappings, at most one per stick.
  public let stickMappings: [RemappingStickMapping]
  /// Dual-stage trigger mappings, at most one per trigger.
  public let triggerMappings: [RemappingTriggerMapping]
  /// Continuous touch mappings, at most one per touch surface.
  public let touchMappings: [RemappingTouchMapping]
  /// Bindings of the base layer, at most one per source.
  public let bindings: [RemappingBinding]
  /// Combinations of sources that fire one destination.
  public let chords: [RemappingChord]
  /// Ordered source sequences that fire one destination.
  public let sequences: [RemappingSequence]
  /// Alternate mapping sets that an activator source turns on.
  public let layers: [RemappingLayer]
  /// Macros that `Macro` destinations run.
  public let macros: [RemappingMacro]

  /// Creates a profile.
  ///
  /// The initializer does not validate; call ``validate()``.
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
    layers: [RemappingLayer] = [],
    macros: [RemappingMacro] = []
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
    self.macros = macros
  }

  /// Decodes a profile from a profile document.
  ///
  /// Omitted optional sections take their defaults. The document header must name the profile kind
  /// and a supported API version.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value, or the header
  ///   problem
  ///   of a document of another kind or version.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      if problem.code != nil { throw problem }
      throw DecodingError.dataCorruptedError(
        forKey: .kind,
        in: container,
        debugDescription: problem.message
      )
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
    macros = try container.decodeIfPresent([RemappingMacro].self, forKey: .macros) ?? []
  }
}
