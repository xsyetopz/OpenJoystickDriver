public import Foundation

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
    case vendorID
    case productID
    case unit
  }

  /// Decodes a device scope from a profile document.
  /// - Throws: `DecodingError` for an unknown key, a missing key, a bad value, or a `unit` that is
  ///   not a port key.
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

/// One size cap for profile data, shared by profiles, saved files, and remapping messages.
public enum RemappingPayloadLimits {
  /// Largest encoded profile or data, in bytes.
  public static let maximumEncodedBytes = 4 * 1_024 * 1_024
  /// Largest number of profiles in one block of data.
  public static let maximumProfileCount = 128
}

/// Declares which foreground application receives synthesized input.
public enum RemappingApplicationScope: Codable, Equatable, Hashable, Sendable {
  /// Only the applications with these bundle identifiers.
  case application(appIDs: [String])
  /// Whatever application is in front.
  case global

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    case application = "Application"
    case global = "Global"
  }

  /// Profile document keys of an application scope.
  enum CodingKeys: String, CodingKey, CaseIterable {
    case type
    case appIDs
  }

  /// Decodes an application scope from a profile document.
  ///
  /// The `type` field selects the case, and `appIDs` is allowed only for `Application`. A
  /// document with the key `appID` is refused by name.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectStaleKey("appID", use: "appIDs")
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    let allowed: [CodingKeys] = kind == .application ? [.type, .appIDs] : [.type]
    try container.rejectKeys(otherThan: allowed)
    switch kind {
    case .application:
      let appIDs = try container.decode([String].self, forKey: .appIDs)
      guard !appIDs.isEmpty else {
        throw DecodingError.dataCorruptedError(
          forKey: .appIDs,
          in: container,
          debugDescription: "appIDs holds at least one bundle identifier"
        )
      }
      self = .application(appIDs: appIDs)
    case .global: self = .global
    }
  }

  /// Encodes the case under its `type` value, with `appIDs` only for an application.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .application(let appIDs):
      try container.encode(Kind.application, forKey: .type)
      try container.encode(appIDs, forKey: .appIDs)
    case .global: try container.encode(Kind.global, forKey: .type)
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
  /// Scale of all pointer movement, or `nil` for none.
  public let pointerSpeed: RemappingPointerSpeed?
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

  /// Whether any binding, chord, sequence, layer or gyro source reads `PointerX` or `PointerY`.
  ///
  /// Macro steps are destinations, so a macro adds no source.
  public var bindsPointer: Bool {
    let layered = layers.contains {
      $0.activator.isPointer || $0.bindings.contains { $0.source.isPointer }
        || $0.chords.contains { $0.sources.contains(where: \.isPointer) }
        || $0.sequences.contains { $0.sources.contains(where: \.isPointer) }
    }
    return layered || bindings.contains { $0.source.isPointer }
      || chords.contains { $0.sources.contains(where: \.isPointer) }
      || sequences.contains { $0.sources.contains(where: \.isPointer) }
      || gyroOutput.activationSource?.isPointer == true
      || gyroOutput.trackball?.source.isPointer == true
  }

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
    pointerSpeed: RemappingPointerSpeed? = nil,
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
    self.pointerSpeed = pointerSpeed
    self.stickMappings = stickMappings
    self.triggerMappings = triggerMappings
    self.touchMappings = touchMappings
    self.bindings = bindings
    self.chords = chords
    self.sequences = sequences
    self.layers = layers
    self.macros = macros
  }

  /// The profile with `scope` as its application scope.
  public func withApplicationScope(_ scope: RemappingApplicationScope) -> Self {
    Self(
      id: id,
      name: name,
      device: device,
      applicationScope: scope,
      outputPolicy: outputPolicy,
      physicalColor: physicalColor,
      motionTuning: motionTuning,
      gyroOutput: gyroOutput,
      joyConPair: joyConPair,
      pointerSpeed: pointerSpeed,
      stickMappings: stickMappings,
      triggerMappings: triggerMappings,
      touchMappings: touchMappings,
      bindings: bindings,
      chords: chords,
      sequences: sequences,
      layers: layers,
      macros: macros
    )
  }

  /// Decodes a profile from a profile document.
  ///
  /// Omitted optional sections take their defaults. The document header must name the profile kind
  /// and a supported API version.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value, or the header
  ///   problem of a document of another kind or version.
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
    pointerSpeed = try container.decodeIfPresent(RemappingPointerSpeed.self, forKey: .pointerSpeed)
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
