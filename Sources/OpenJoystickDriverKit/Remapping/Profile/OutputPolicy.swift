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

  /// Preserves the behavior of profiles written before virtual remapping support.
  public static let systemInput = Self()

  /// Virtual remapping requires isolation even when shared system input was requested.
  public var requiresExclusiveInput: Bool {
    physicalInput == .exclusive || virtualGamepad != .disabled
  }

  private enum CodingKeys: String, CodingKey {
    case virtualGamepad = "virtual_gamepad"
    case physicalInput = "physical_input"
  }
}


extension RemappingProfile {
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
    if Self.containsSystemInput(bindings: bindings, chords: chords, sequences: sequences) {
      return true
    }
    return layers.contains {
      Self.containsSystemInput(bindings: $0.bindings, chords: $0.chords, sequences: $0.sequences)
    }
  }

  private static func containsSystemInput(
    bindings: [RemappingBinding], chords: [RemappingChord], sequences: [RemappingSequence]
  ) -> Bool {
    bindings.flatMap(\.expandedActions).contains {
      $0.destination.isSystemInput || $0.longHold?.destination.isSystemInput == true
        || $0.doubleTap?.destination.isSystemInput == true
    } || chords.contains { $0.destination.isSystemInput }
      || sequences.contains { $0.destination.isSystemInput }
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
