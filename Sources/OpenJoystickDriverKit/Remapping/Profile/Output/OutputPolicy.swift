import Foundation

/// Selects the virtual contribution of controls that have no active mapping.
public enum RemappingVirtualGamepadPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  /// Synthesizes system input without creating a virtual gamepad.
  case disabled = "Disabled"
  /// Emits only destinations explicitly assigned by the profile.
  case mapped = "Mapped"
  /// Also forwards controls that the active mapping does not consume.
  case passthrough = "Passthrough"
}

/// Physical ownership required before the profile may emit input.
public enum RemappingPhysicalInputPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  /// Allows system-input mappings while native physical input remains visible.
  case shared = "Shared"
  /// Requires confirmed exclusive physical ownership.
  case exclusive = "Exclusive"
}

/// Declares output routing and physical isolation independently of individual bindings.
public struct RemappingOutputPolicy: Codable, Equatable, Hashable, Sendable {
  /// Virtual gamepad contribution of controls that have no mapping.
  public let virtualGamepad: RemappingVirtualGamepadPolicy
  /// Physical ownership the profile requires.
  public let physicalInput: RemappingPhysicalInputPolicy

  /// Creates an output policy.
  public init(
    virtualGamepad: RemappingVirtualGamepadPolicy = .disabled,
    physicalInput: RemappingPhysicalInputPolicy = .shared
  ) {
    self.virtualGamepad = virtualGamepad
    self.physicalInput = physicalInput
  }

  /// Default policy: no virtual gamepad, physical input shared with the system.
  public static let systemInput = Self()

  /// Virtual remapping requires isolation even when shared system input was requested.
  public var requiresExclusiveInput: Bool {
    physicalInput == .exclusive || virtualGamepad != .disabled
  }

  /// Profile document keys of an output policy.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `virtualGamepad`.
    case virtualGamepad
    /// The JSON key of `physicalInput`.
    case physicalInput
  }

  /// Decodes an output policy from a profile document, which must give both fields.
  /// - Throws: `DecodingError` for an unknown key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    virtualGamepad = try values.decode(RemappingVirtualGamepadPolicy.self, forKey: .virtualGamepad)
    physicalInput = try values.decode(RemappingPhysicalInputPolicy.self, forKey: .physicalInput)
  }
}

extension RemappingProfile {
  /// Whether mapped-only output leaves every controller control without a virtual destination.
  public var suppressesAllControllerInput: Bool {
    guard outputPolicy.virtualGamepad == .mapped else { return false }
    if gyroOutput.mode == .leftStick || gyroOutput.mode == .rightStick
      || motionTuning.steering != nil
      || layers.contains(where: { $0.motionTuning?.steering != nil })
      || stickMappings.contains(where: { $0.mode == .steering || $0.passthrough })
      || triggerMappings.contains(where: \.passthrough)
      || touchMappings.contains(where: { $0.mode != .pointer })
    {
      return false
    }
    return !containsDestination(where: \.isVirtualGamepad)
  }

  /// Whether the profile emits nothing.
  ///
  /// Nothing means no virtual gamepad, system-input, or physical output, and no light color.
  /// Activating such a profile leaves the controller inert.
  public var producesNoOutput: Bool {
    suppressesAllControllerInput && physicalColor == nil && !requiresSystemInputAccess
      && !containsDestination { _ in true }
  }

  /// Returns a copy that forwards unconsumed controls to the virtual gamepad.
  ///
  /// Every mapping and the physical-input policy stay as they are.
  public func restoringDefaultInput() -> Self {
    replacingInputConfiguration(
      outputPolicy: RemappingOutputPolicy(
        virtualGamepad: .passthrough,
        physicalInput: outputPolicy.physicalInput
      )
    )
  }

  /// Returns a copy without any input processing.
  ///
  /// The copy keeps the profile identity and physical-output settings, and maps nothing to a
  /// virtual gamepad.
  public func clearingAllInput() -> Self {
    replacingInputConfiguration(
      outputPolicy: RemappingOutputPolicy(
        virtualGamepad: .mapped,
        physicalInput: outputPolicy.physicalInput
      ),
      motionTuning: .default,
      gyroOutput: .default,
      stickMappings: [],
      triggerMappings: [],
      touchMappings: [],
      bindings: [],
      chords: [],
      sequences: [],
      layers: [],
      macros: []
    )
  }

  /// Whether this profile can synthesize keyboard, pointer, or scroll input.
  ///
  /// Includes inactive layers and alternate activation destinations, so a lost permission cannot
  /// leave a partial mapping.
  public var requiresSystemInputAccess: Bool {
    if stickMappings.contains(where: { $0.mode != .steering })
      || touchMappings.contains(where: { $0.mode == .pointer })
    {
      return true
    }
    if outputPolicy.virtualGamepad == .disabled || gyroOutput.mode == .mouse { return true }
    return containsDestination(where: \.isSystemInput)
  }

  /// The targets of the `ProfileSwitch` destinations of the profile.
  var profileSwitchTargets: [RemappingProfileTarget] {
    var targets: [RemappingProfileTarget] = []
    _ = containsDestination {
      if case .profileSwitch(let target) = $0 { targets.append(target) }
      return false
    }
    return targets
  }

  /// The actions of the profile that launch something, one line each, without repeats.
  ///
  /// A line is the destination type and its value, such as `OpenURL: https://example.com`, with
  /// the URL in full. Counts destinations in layers, macros and alternate activations.
  public var launchedActions: [String] {
    var lines: [String] = []
    _ = containsDestination {
      let line: String
      switch $0 {
      case .openApplication(let identifier): line = "OpenApplication: \(identifier)"
      case .openURL(let url): line = "OpenURL: \(url)"
      case .runShortcut(let name): line = "RunShortcut: \(name)"
      case .typeText(let text): line = "TypeText: \(text)"
      default: return false
      }
      if !lines.contains(line) { lines.append(line) }
      return false
    }
    return lines
  }

  /// The voices that the `Speak` destinations of the profile name.
  var speechVoices: [String] {
    var voices: [String] = []
    _ = containsDestination {
      if case .speak(_, let voice?) = $0 { voices.append(voice) }
      return false
    }
    return voices
  }

  /// Whether a binding, chord, or sequence, in any layer or activation, targets a match.
  func containsDestination(where matches: (RemappingDestination) -> Bool) -> Bool {
    macros.contains { $0.steps.flatMap(\.destinations).contains(where: matches) }
      || Self.containsDestination(bindings: bindings, chords: chords, sequences: sequences, matches)
      || layers.contains {
        Self.containsDestination(
          bindings: $0.bindings,
          chords: $0.chords,
          sequences: $0.sequences,
          matches
        )
      }
  }

  /// Whether any binding, chord or sequence of one scope targets a match, including its long-hold
  /// and multi-tap destinations.
  private static func containsDestination(
    bindings: [RemappingBinding],
    chords: [RemappingChord],
    sequences: [RemappingSequence],
    _ matches: (RemappingDestination) -> Bool
  ) -> Bool {
    bindings.flatMap(\.expandedActions).contains { binding in
      matches(binding.destination) || binding.longHold.map { matches($0.destination) } == true
        || binding.multiTap.contains { matches($0.destination) }
    } || chords.contains { matches($0.destination) }
      || sequences.contains { matches($0.destination) }
  }

  /// Returns a copy with the given output policy and, for each argument that is given, a
  /// replacement for that part of the input configuration; everything else is kept.
  private func replacingInputConfiguration(
    outputPolicy: RemappingOutputPolicy,
    motionTuning: RemappingMotionTuning? = nil,
    gyroOutput: RemappingGyroOutput? = nil,
    stickMappings: [RemappingStickMapping]? = nil,
    triggerMappings: [RemappingTriggerMapping]? = nil,
    touchMappings: [RemappingTouchMapping]? = nil,
    bindings: [RemappingBinding]? = nil,
    chords: [RemappingChord]? = nil,
    sequences: [RemappingSequence]? = nil,
    layers: [RemappingLayer]? = nil,
    macros: [RemappingMacro]? = nil
  ) -> Self {
    Self(
      id: id,
      name: name,
      device: device,
      applicationScope: applicationScope,
      outputPolicy: outputPolicy,
      physicalColor: physicalColor,
      motionTuning: motionTuning ?? self.motionTuning,
      gyroOutput: gyroOutput ?? self.gyroOutput,
      joyConPair: joyConPair,
      pointerSpeed: pointerSpeed,
      stickMappings: stickMappings ?? self.stickMappings,
      triggerMappings: triggerMappings ?? self.triggerMappings,
      touchMappings: touchMappings ?? self.touchMappings,
      bindings: bindings ?? self.bindings,
      chords: chords ?? self.chords,
      sequences: sequences ?? self.sequences,
      layers: layers ?? self.layers,
      macros: macros ?? self.macros
    )
  }
}

extension RemappingDestination {
  /// Identifies destinations that require operating-system input-posting authorization.
  public var isSystemInput: Bool {
    switch self {
    case .keyboard, .mouseButton, .mouseMovement, .scroll, .systemKey, .typeText: true
    case .gamepadButton, .gamepadDpad, .gamepadAxis, .physical, .macro, .profileSwitch, .layerSet,
      .pause, .systemAction, .openApplication, .openURL, .runShortcut, .speak,
      .midiNote, .midiControlChange:
      false
    }
  }

  /// Whether the destination is a virtual gamepad button, d-pad or axis.
  var isVirtualGamepad: Bool {
    switch self {
    case .gamepadButton, .gamepadDpad, .gamepadAxis: true
    case .keyboard, .mouseButton, .mouseMovement, .scroll, .physical, .macro, .profileSwitch,
      .layerSet, .pause, .systemKey, .systemAction, .openApplication, .openURL, .runShortcut,
      .typeText, .speak,
      .midiNote, .midiControlChange:
      false
    }
  }
}
