import Foundation

/// The output a binding drives: virtual gamepad, keyboard, pointer, or physical controller.
public enum RemappingDestination: Codable, Equatable, Hashable, Sendable {
  /// A button of the virtual gamepad.
  case gamepadButton(Control)
  /// A d-pad direction of the virtual gamepad.
  case gamepadDpad(RemappingDpadDirection)
  /// An axis of the virtual gamepad.
  case gamepadAxis(RemappingAxis)
  /// A keyboard key with its modifiers.
  case keyboard(key: RemappingKeyboardKey, modifiers: Set<RemappingKeyModifier>)
  /// A pointer button.
  case mouseButton(RemappingMouseButton)
  /// Pointer movement along one axis.
  case mouseMovement(RemappingPointerAxis)
  /// Scrolling along one axis.
  case scroll(RemappingPointerAxis)
  /// A channel of the physical controller, such as rumble or light.
  case physical(RemappingPhysicalOutput)
  /// The macro of the profile with this identifier.
  case macro(UUID)

  /// Whether the destination can repeat as turbo: a keyboard key, pointer button or virtual gamepad
  /// button or d-pad direction.
  public var acceptsTurbo: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad: true
    case .mouseMovement, .scroll, .gamepadAxis, .physical, .macro: false
    }
  }

  /// Whether the destination takes a continuous amount: pointer movement, scrolling or a virtual
  /// gamepad axis.
  public var isContinuous: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .physical, .macro: false
    case .mouseMovement, .scroll, .gamepadAxis: true
    }
  }

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    /// The `Keyboard` case.
    case keyboard = "Keyboard"
    /// The `GamepadButton` case.
    case gamepadButton = "GamepadButton"
    /// The `GamepadDpad` case.
    case gamepadDpad = "GamepadDpad"
    /// The `GamepadAxis` case.
    case gamepadAxis = "GamepadAxis"
    /// The `MouseButton` case.
    case mouseButton = "MouseButton"
    /// The `MouseMovement` case.
    case mouseMovement = "MouseMovement"
    /// The `Scroll` case.
    case scroll = "Scroll"
    /// The `Physical` case.
    case physical = "Physical"
    /// The `Macro` case.
    case macro = "Macro"

    /// Keys that a profile document may give for this case, which `type` selects.
    var fields: [CodingKeys] {
      switch self {
      case .keyboard: [.type, .key, .modifiers]
      case .gamepadButton, .mouseButton: [.type, .button]
      case .gamepadDpad: [.type, .direction]
      case .gamepadAxis, .mouseMovement, .scroll: [.type, .axis]
      case .physical: [.type, .physical]
      case .macro: [.type, .macro]
      }
    }
  }

  /// Profile document keys of a destination, merged across all cases.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `type`.
    case type
    /// The JSON key of `key`.
    case key
    /// The JSON key of `modifiers`.
    case modifiers
    /// The JSON key of `button`.
    case button
    /// The JSON key of `axis`.
    case axis
    /// The JSON key of `direction`.
    case direction
    /// The JSON key of `physical`.
    case physical
    /// The JSON key of `macro`.
    case macro
  }

  /// Decodes a destination from a profile document.
  ///
  /// The `type` field selects the case, and keys that belong to another case are rejected.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    try container.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .gamepadAxis: self = .gamepadAxis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .gamepadDpad:
      self = .gamepadDpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .gamepadButton:
      self = .gamepadButton(try container.decode(Control.self, forKey: .button))
    case .keyboard:
      let modifiers = try container.decode([RemappingKeyModifier].self, forKey: .modifiers)
      self = .keyboard(
        key: try container.decode(RemappingKeyboardKey.self, forKey: .key),
        modifiers: Set(modifiers)
      )
    case .mouseButton:
      self = .mouseButton(try container.decode(RemappingMouseButton.self, forKey: .button))
    case .mouseMovement:
      self = .mouseMovement(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .scroll: self = .scroll(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .physical:
      self = .physical(try container.decode(RemappingPhysicalOutput.self, forKey: .physical))
    case .macro: self = .macro(try container.decode(UUID.self, forKey: .macro))
    }
  }

  /// Encodes the case under its `type` value with only its own keys; keyboard modifiers are sorted.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .gamepadAxis(let axis):
      try container.encode(Kind.gamepadAxis, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .gamepadDpad(let direction):
      try container.encode(Kind.gamepadDpad, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .gamepadButton(let button):
      try container.encode(Kind.gamepadButton, forKey: .type)
      try container.encode(button, forKey: .button)
    case .keyboard(let key, let modifiers):
      try container.encode(Kind.keyboard, forKey: .type)
      try container.encode(key, forKey: .key)
      try container.encode(modifiers.sorted { $0.rawValue < $1.rawValue }, forKey: .modifiers)
    case .mouseButton(let button):
      try container.encode(Kind.mouseButton, forKey: .type)
      try container.encode(button, forKey: .button)
    case .mouseMovement(let axis):
      try container.encode(Kind.mouseMovement, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .scroll(let axis):
      try container.encode(Kind.scroll, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .physical(let output):
      try container.encode(Kind.physical, forKey: .type)
      try container.encode(output, forKey: .physical)
    case .macro(let id):
      try container.encode(Kind.macro, forKey: .type)
      try container.encode(id, forKey: .macro)
    }
  }
}
