import Foundation

/// Selects the virtual contribution of controls that have no active mapping.
public enum RemappingVirtualGamepadPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  /// Synthesizes system input without creating a virtual gamepad.
  case disabled
  /// Emits only destinations explicitly assigned by the profile.
  case mapped
  /// Also forwards controls that the active mapping does not consume.
  case passthrough
}

/// Physical ownership required before the profile may emit input.
public enum RemappingPhysicalInputPolicy: String, Codable, CaseIterable, Hashable, Sendable {
  /// Allows system-input mappings while native physical input remains visible.
  case shared
  /// Requires confirmed exclusive physical ownership.
  case exclusive
}

/// Declares output routing and physical isolation independently of individual bindings.
public struct RemappingOutputPolicy: Codable, Equatable, Hashable, Sendable {
  public let virtualGamepad: RemappingVirtualGamepadPolicy
  public let physicalInput: RemappingPhysicalInputPolicy

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

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case virtualGamepad
    case physicalInput
  }

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

  /// Whether the profile emits nothing: no virtual gamepad, system-input, or physical output,
  /// and no light color. Activating such a profile leaves the controller inert.
  public var producesNoOutput: Bool {
    suppressesAllControllerInput && physicalColor == nil && !requiresSystemInputAccess
      && !containsDestination { _ in true }
  }

  /// Restores unmodified virtual controller input without changing profile content.
  public func restoringDefaultInput() -> Self {
    replacingInputConfiguration(
      outputPolicy: RemappingOutputPolicy(
        virtualGamepad: .passthrough,
        physicalInput: outputPolicy.physicalInput
      )
    )
  }

  /// Removes all input processing while retaining profile identity and physical-output settings.
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
      layers: []
    )
  }

  /// Whether this profile can synthesize keyboard, pointer, or scroll input.
  /// Includes inactive layers and alternate activation destinations so permission loss cannot
  /// become a partial mapping. System-only profiles retain their previous permission contract.
  public var requiresSystemInputAccess: Bool {
    if stickMappings.contains(where: { $0.mode != .steering })
      || touchMappings.contains(where: { $0.mode == .pointer })
    {
      return true
    }
    if outputPolicy.virtualGamepad == .disabled || gyroOutput.mode == .mouse { return true }
    return containsDestination(where: \.isSystemInput)
  }

  /// Whether a binding, chord, or sequence, in any layer or activation, targets a match.
  private func containsDestination(where matches: (RemappingDestination) -> Bool) -> Bool {
    Self.containsDestination(bindings: bindings, chords: chords, sequences: sequences, matches)
      || layers.contains {
        Self.containsDestination(
          bindings: $0.bindings,
          chords: $0.chords,
          sequences: $0.sequences,
          matches
        )
      }
  }

  private static func containsDestination(
    bindings: [RemappingBinding],
    chords: [RemappingChord],
    sequences: [RemappingSequence],
    _ matches: (RemappingDestination) -> Bool
  ) -> Bool {
    bindings.flatMap(\.expandedActions).contains { binding in
      matches(binding.destination) || binding.longHold.map { matches($0.destination) } == true
        || binding.doubleTap.map { matches($0.destination) } == true
    } || chords.contains { matches($0.destination) }
      || sequences.contains { matches($0.destination) }
  }

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
    layers: [RemappingLayer]? = nil
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
      stickMappings: stickMappings ?? self.stickMappings,
      triggerMappings: triggerMappings ?? self.triggerMappings,
      touchMappings: touchMappings ?? self.touchMappings,
      bindings: bindings ?? self.bindings,
      chords: chords ?? self.chords,
      sequences: sequences ?? self.sequences,
      layers: layers ?? self.layers
    )
  }
}

extension RemappingDestination {
  /// Identifies destinations that require operating-system input-posting authorization.
  public var isSystemInput: Bool {
    switch self {
    case .keyboard, .mouseButton, .mouseMovement, .scroll: true
    case .gamepadButton, .gamepadDpad, .gamepadAxis, .physical: false
    }
  }

  var isVirtualGamepad: Bool {
    switch self {
    case .gamepadButton, .gamepadDpad, .gamepadAxis: true
    case .keyboard, .mouseButton, .mouseMovement, .scroll, .physical: false
    }
  }
}
