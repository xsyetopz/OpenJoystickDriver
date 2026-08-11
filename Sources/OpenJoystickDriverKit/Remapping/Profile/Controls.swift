import Foundation

/// A stable, normalized physical control identifier used by remapping profiles.
public enum RemappingButton: String, Codable, CaseIterable, Hashable, Sendable {
  case south
  case east
  case west
  case north
  case leftShoulder = "left_shoulder"
  case rightShoulder = "right_shoulder"
  case leftStick = "left_stick"
  case rightStick = "right_stick"
  case start
  case back
  case guide
  case share
  case options
  case touchpad
  case auxiliary1 = "auxiliary_1"
  case auxiliary2 = "auxiliary_2"
  case auxiliary3 = "auxiliary_3"
  case auxiliary4 = "auxiliary_4"
  case auxiliary5 = "auxiliary_5"
  case auxiliary6 = "auxiliary_6"
  case auxiliary7 = "auxiliary_7"
  case auxiliary8 = "auxiliary_8"
}

public enum RemappingDpadDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case up
  case down
  case left
  case right
}

public enum RemappingAxis: String, Codable, CaseIterable, Hashable, Sendable {
  case leftStickX = "left_stick_x"
  case leftStickY = "left_stick_y"
  case rightStickX = "right_stick_x"
  case rightStickY = "right_stick_y"
  case leftTrigger = "left_trigger"
  case rightTrigger = "right_trigger"
}

public enum RemappingAxisDirection: String, Codable, Hashable, Sendable {
  case negative
  case positive
}

/// The controller-side origin of a binding.
public enum RemappingSource: Codable, Equatable, Hashable, Sendable {
  case button(RemappingButton)
  case dpad(RemappingDpadDirection)
  case axis(RemappingAxis)
  case axisDirection(RemappingAxis, RemappingAxisDirection)

  private enum Kind: String, Codable {
    case button
    case dpad
    case axis
    case axisDirection = "axis_direction"
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case button
    case direction
    case axis
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .button: self = .button(try container.decode(RemappingButton.self, forKey: .button))
    case .dpad: self = .dpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .axis: self = .axis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .axisDirection:
      self = .axisDirection(
        try container.decode(RemappingAxis.self, forKey: .axis),
        try container.decode(RemappingAxisDirection.self, forKey: .direction)
      )
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .button(let button):
      try container.encode(Kind.button, forKey: .type)
      try container.encode(button, forKey: .button)
    case .dpad(let direction):
      try container.encode(Kind.dpad, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .axis(let axis):
      try container.encode(Kind.axis, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .axisDirection(let axis, let direction):
      try container.encode(Kind.axisDirection, forKey: .type)
      try container.encode(axis, forKey: .axis)
      try container.encode(direction, forKey: .direction)
    }
  }
}

/// A symbolic keyboard key. Platform adapters translate this value to an OS key code.
public enum RemappingKeyboardKey: String, Codable, CaseIterable, Hashable, Sendable {
  case a, b, c, d, e, f, g, h, i, j, k, l, m
  case n, o, p, q, r, s, t, u, v, w, x, y, z
  case digit0 = "0"
  case digit1 = "1"
  case digit2 = "2"
  case digit3 = "3"
  case digit4 = "4"
  case digit5 = "5"
  case digit6 = "6"
  case digit7 = "7"
  case digit8 = "8"
  case digit9 = "9"
  case escape
  case tab
  case capsLock = "caps_lock"
  case space
  case returnKey = "return"
  case deleteBackward = "delete_backward"
  case deleteForward = "delete_forward"
  case help
  case insert
  case home
  case end
  case pageUp = "page_up"
  case pageDown = "page_down"
  case arrowUp = "arrow_up"
  case arrowDown = "arrow_down"
  case arrowLeft = "arrow_left"
  case arrowRight = "arrow_right"
  case minus
  case equal
  case leftBracket = "left_bracket"
  case rightBracket = "right_bracket"
  case backslash
  case semicolon
  case quote
  case comma
  case period
  case slash
  case grave
  case section
  case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
  case f13, f14, f15, f16, f17, f18, f19, f20
  case keypad0 = "keypad_0"
  case keypad1 = "keypad_1"
  case keypad2 = "keypad_2"
  case keypad3 = "keypad_3"
  case keypad4 = "keypad_4"
  case keypad5 = "keypad_5"
  case keypad6 = "keypad_6"
  case keypad7 = "keypad_7"
  case keypad8 = "keypad_8"
  case keypad9 = "keypad_9"
  case keypadDecimal = "keypad_decimal"
  case keypadMultiply = "keypad_multiply"
  case keypadPlus = "keypad_plus"
  case keypadClear = "keypad_clear"
  case keypadDivide = "keypad_divide"
  case keypadEnter = "keypad_enter"
  case keypadMinus = "keypad_minus"
  case keypadEqual = "keypad_equal"
}

public enum RemappingKeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
  case command
  case control
  case option
  case shift
}

public enum RemappingMouseButton: String, Codable, CaseIterable, Hashable, Sendable {
  case left
  case right
  case middle
  case back
  case forward
}

public enum RemappingPointerAxis: String, Codable, Hashable, Sendable {
  case x
  case y
}

/// The system-input destination of a binding.
public enum RemappingDestination: Codable, Equatable, Hashable, Sendable {
  case keyboard(key: RemappingKeyboardKey, modifiers: Set<RemappingKeyModifier>)
  case mouseButton(RemappingMouseButton)
  case mouseMovement(RemappingPointerAxis)
  case scroll(RemappingPointerAxis)

  public var acceptsTurbo: Bool {
    switch self {
    case .keyboard, .mouseButton: true
    case .mouseMovement, .scroll: false
    }
  }

  public var isContinuous: Bool {
    switch self {
    case .keyboard, .mouseButton: false
    case .mouseMovement, .scroll: true
    }
  }

  private enum Kind: String, Codable {
    case keyboard
    case mouseButton = "mouse_button"
    case mouseMovement = "mouse_movement"
    case scroll
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case key
    case modifiers
    case button
    case axis
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
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
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
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
    }
  }
}
