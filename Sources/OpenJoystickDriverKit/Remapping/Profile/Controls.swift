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
  case mute
  case leftTriggerClick = "left_trigger_click"
  case rightTriggerClick = "right_trigger_click"
  case leftGrip = "left_grip"
  case rightGrip = "right_grip"
  case leftPadClick = "left_pad_click"
  case rightPadClick = "right_pad_click"
  case leftSL = "left_sl"
  case leftSR = "left_sr"
  case rightSL = "right_sl"
  case rightSR = "right_sr"
  case leftFunction = "left_function"
  case rightFunction = "right_function"
  case leftPaddle = "left_paddle"
  case rightPaddle = "right_paddle"

  public var supportsVirtualOutput: Bool {
    switch self {
    case .leftFunction, .rightFunction, .leftPaddle, .rightPaddle,
      .leftSL, .leftSR, .rightSL, .rightSR,
      .leftGrip, .rightGrip, .leftPadClick, .rightPadClick: false
    default: true
    }
  }
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
  case triggerStage(RemappingTriggerSource, RemappingTriggerStage)
  case motionLean(RemappingMotionLeanDirection)
  case touchContact(RemappingTouchSurface)
  case touchGrid(RemappingTouchGridSource)
  case touchSwipe(RemappingTouchSwipeSource)

  private enum Kind: String, Codable {
    case button
    case dpad
    case axis
    case axisDirection = "axis_direction"
    case triggerStage = "trigger_stage"
    case motionLean = "motion_lean"
    case touchContact = "touch_contact"
    case touchGrid = "touch_grid"
    case touchSwipe = "touch_swipe"
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case button
    case direction
    case axis
    case surface
    case columns
    case rows
    case column
    case row
    case minimumDistance = "minimum_distance"
    case trigger
    case stage
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
    case .triggerStage:
      self = .triggerStage(
        try container.decode(RemappingTriggerSource.self, forKey: .trigger),
        try container.decode(RemappingTriggerStage.self, forKey: .stage)
      )
    case .motionLean:
      self = .motionLean(
        try container.decode(RemappingMotionLeanDirection.self, forKey: .direction)
      )
    case .touchContact:
      self = .touchContact(try container.decode(RemappingTouchSurface.self, forKey: .surface))
    case .touchGrid:
      self = .touchGrid(
        RemappingTouchGridSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          columns: try container.decode(Int.self, forKey: .columns),
          rows: try container.decode(Int.self, forKey: .rows),
          column: try container.decode(Int.self, forKey: .column),
          row: try container.decode(Int.self, forKey: .row)
        )
      )
    case .touchSwipe:
      self = .touchSwipe(
        RemappingTouchSwipeSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          direction: try container.decode(RemappingTouchSwipeDirection.self, forKey: .direction),
          minimumDistance: try container.decode(Double.self, forKey: .minimumDistance)
        )
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
    case .triggerStage(let trigger, let stage):
      try container.encode(Kind.triggerStage, forKey: .type)
      try container.encode(trigger, forKey: .trigger)
      try container.encode(stage, forKey: .stage)
    case .motionLean(let direction):
      try container.encode(Kind.motionLean, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .touchContact(let surface):
      try container.encode(Kind.touchContact, forKey: .type)
      try container.encode(surface, forKey: .surface)
    case .touchGrid(let source):
      try container.encode(Kind.touchGrid, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.columns, forKey: .columns)
      try container.encode(source.rows, forKey: .rows)
      try container.encode(source.column, forKey: .column)
      try container.encode(source.row, forKey: .row)
    case .touchSwipe(let source):
      try container.encode(Kind.touchSwipe, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.direction, forKey: .direction)
      try container.encode(source.minimumDistance, forKey: .minimumDistance)
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
  case gamepadButton(RemappingButton)
  case gamepadDpad(RemappingDpadDirection)
  case gamepadAxis(RemappingAxis)
  case keyboard(key: RemappingKeyboardKey, modifiers: Set<RemappingKeyModifier>)
  case mouseButton(RemappingMouseButton)
  case mouseMovement(RemappingPointerAxis)
  case scroll(RemappingPointerAxis)
  case physical(RemappingPhysicalOutput)

  public var acceptsTurbo: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad: true
    case .mouseMovement, .scroll, .gamepadAxis, .physical: false
    }
  }

  public var isContinuous: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .physical: false
    case .mouseMovement, .scroll, .gamepadAxis: true
    }
  }

  private enum Kind: String, Codable {
    case keyboard
    case gamepadButton = "gamepad_button"
    case gamepadDpad = "gamepad_dpad"
    case gamepadAxis = "gamepad_axis"
    case mouseButton = "mouse_button"
    case mouseMovement = "mouse_movement"
    case scroll
    case physical
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case key
    case modifiers
    case button
    case axis
    case direction
    case physical
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .type) {
    case .gamepadAxis:
      self = .gamepadAxis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .gamepadDpad:
      self = .gamepadDpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .gamepadButton:
      self = .gamepadButton(try container.decode(RemappingButton.self, forKey: .button))
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
    }
  }

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
    }
  }
}
