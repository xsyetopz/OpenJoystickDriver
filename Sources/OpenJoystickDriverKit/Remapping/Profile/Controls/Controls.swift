import Foundation

/// Direction of the d-pad.
public enum RemappingDpadDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// Up.
  case up = "DpadUp"
  /// Down.
  case down = "DpadDown"
  /// Left.
  case left = "DpadLeft"
  /// Right.
  case right = "DpadRight"
}

/// A stick axis or a trigger of the control vocabulary; the raw value is its control id.
public enum RemappingAxis: String, Codable, CaseIterable, Hashable, Sendable {
  /// Left stick horizontal axis.
  case leftStickX = "LeftStickX"
  /// Left stick vertical axis.
  case leftStickY = "LeftStickY"
  /// Right stick horizontal axis.
  case rightStickX = "RightStickX"
  /// Right stick vertical axis.
  case rightStickY = "RightStickY"
  /// Left trigger.
  case leftTrigger = "LeftTrigger"
  /// Right trigger.
  case rightTrigger = "RightTrigger"

  /// The control this axis is.
  public var control: Control {
    switch self {
    case .leftStickX: .leftStickX
    case .leftStickY: .leftStickY
    case .rightStickX: .rightStickX
    case .rightStickY: .rightStickY
    case .leftTrigger: .leftTrigger
    case .rightTrigger: .rightTrigger
    }
  }
}

/// Half of an axis range.
public enum RemappingAxisDirection: String, Codable, CaseIterable, Hashable, Sendable {
  /// The deflection below the center.
  case negative = "Negative"
  /// The deflection above the center.
  case positive = "Positive"
}

/// The controller-side origin of a binding.
public enum RemappingSource: Codable, Equatable, Hashable, Sendable {
  /// A button or other digital control.
  case button(Control)
  /// A d-pad direction.
  case dpad(RemappingDpadDirection)
  /// An analog axis, as a continuous value.
  case axis(RemappingAxis)
  /// One direction of an analog axis, as a digital press.
  case axisDirection(RemappingAxis, RemappingAxisDirection)
  /// The soft or full stage of a dual-stage trigger.
  case triggerStage(RemappingTriggerSource, RemappingTriggerStage)
  /// A lean of the controller to the left or right.
  case motionLean(RemappingMotionLeanDirection)
  /// Any contact on a touch surface.
  case touchContact(RemappingTouchSurface)
  /// One cell of a touch-surface grid.
  case touchGrid(RemappingTouchGridSource)
  /// A swipe on a touch surface.
  case touchSwipe(RemappingTouchSwipeSource)
  /// A ring and optional sector of a stick.
  case stickRegion(RemappingStickRegionSource)
  /// A pressure band of a trigger.
  case triggerBand(RemappingTriggerBandSource)
  /// A rectangle of a touch surface.
  case touchArea(RemappingTouchAreaSource)

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    /// The `Button` case.
    case button = "Button"
    /// The `Dpad` case.
    case dpad = "Dpad"
    /// The `Axis` case.
    case axis = "Axis"
    /// The `AxisDirection` case.
    case axisDirection = "AxisDirection"
    /// The `TriggerStage` case.
    case triggerStage = "TriggerStage"
    /// The `MotionLean` case.
    case motionLean = "MotionLean"
    /// The `TouchContact` case.
    case touchContact = "TouchContact"
    /// The `TouchGrid` case.
    case touchGrid = "TouchGrid"
    /// The `TouchSwipe` case.
    case touchSwipe = "TouchSwipe"
    /// The `StickRegion` case.
    case stickRegion = "StickRegion"
    /// The `TriggerBand` case.
    case triggerBand = "TriggerBand"
    /// The `TouchArea` case.
    case touchArea = "TouchArea"

    /// Keys that a profile document may give for this case, which `type` selects.
    var fields: [CodingKeys] {
      switch self {
      case .button: [.type, .button]
      case .dpad, .motionLean: [.type, .direction]
      case .axis: [.type, .axis]
      case .axisDirection: [.type, .axis, .direction]
      case .triggerStage: [.type, .trigger, .stage]
      case .touchContact: [.type, .surface]
      case .touchGrid: [.type, .surface, .columns, .rows, .column, .row]
      case .touchSwipe: [.type, .surface, .direction, .minimumDistance]
      case .stickRegion:
        [.type, .stick, .innerRadius, .outerRadius, .fromDegrees, .toDegrees, .hysteresis]
      case .triggerBand: [.type, .trigger, .from, .to, .hysteresis]
      case .touchArea: [.type, .surface, .x, .y, .width, .height]
      }
    }
  }

  /// Profile document keys of a source, merged across all cases.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `type`.
    case type
    /// The JSON key of `button`.
    case button
    /// The JSON key of `direction`.
    case direction
    /// The JSON key of `axis`.
    case axis
    /// The JSON key of `surface`.
    case surface
    /// The JSON key of `columns`.
    case columns
    /// The JSON key of `rows`.
    case rows
    /// The JSON key of `column`.
    case column
    /// The JSON key of `row`.
    case row
    /// The JSON key of `minimumDistance`.
    case minimumDistance
    /// The JSON key of `trigger`.
    case trigger
    /// The JSON key of `stage`.
    case stage
    /// The JSON key of `stick`.
    case stick
    /// The JSON key of `innerRadius`.
    case innerRadius
    /// The JSON key of `outerRadius`.
    case outerRadius
    /// The JSON key of `fromDegrees`.
    case fromDegrees
    /// The JSON key of `toDegrees`.
    case toDegrees
    /// The JSON key of `hysteresis`.
    case hysteresis
    /// The JSON key of `from`.
    case from
    /// The JSON key of `to`.
    case to
    /// The JSON key of `x`.
    case x
    /// The JSON key of `y`.
    case y
    /// The JSON key of `width`.
    case width
    /// The JSON key of `height`.
    case height
  }

  /// Decodes a source from a profile document.
  ///
  /// The `type` field selects the case, and keys that belong to another case are rejected.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    try container.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .button: self = .button(try container.decode(Control.self, forKey: .button))
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
    case .stickRegion:
      let from = try container.decodeIfPresent(Double.self, forKey: .fromDegrees)
      let to = try container.decodeIfPresent(Double.self, forKey: .toDegrees)
      guard (from == nil) == (to == nil) else {
        throw DecodingError.dataCorruptedError(
          forKey: .toDegrees,
          in: container,
          debugDescription: "fromDegrees and toDegrees come together."
        )
      }
      self = .stickRegion(
        RemappingStickRegionSource(
          stick: try container.decode(RemappingStickSource.self, forKey: .stick),
          innerRadius: try container.decode(Double.self, forKey: .innerRadius),
          outerRadius: try container.decode(Double.self, forKey: .outerRadius),
          fromDegrees: from,
          toDegrees: to,
          hysteresis: try container.decode(Double.self, forKey: .hysteresis)
        )
      )
    case .triggerBand:
      self = .triggerBand(
        RemappingTriggerBandSource(
          trigger: try container.decode(RemappingTriggerSource.self, forKey: .trigger),
          from: try container.decode(Double.self, forKey: .from),
          to: try container.decode(Double.self, forKey: .to),
          hysteresis: try container.decode(Double.self, forKey: .hysteresis)
        )
      )
    case .touchArea:
      self = .touchArea(
        RemappingTouchAreaSource(
          surface: try container.decode(RemappingTouchSurface.self, forKey: .surface),
          x: try container.decode(Double.self, forKey: .x),
          y: try container.decode(Double.self, forKey: .y),
          width: try container.decode(Double.self, forKey: .width),
          height: try container.decode(Double.self, forKey: .height)
        )
      )
    }
  }

  /// Encodes the case under its `type` value with only its own keys.
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
    case .stickRegion(let source):
      try container.encode(Kind.stickRegion, forKey: .type)
      try container.encode(source.stick, forKey: .stick)
      try container.encode(source.innerRadius, forKey: .innerRadius)
      try container.encode(source.outerRadius, forKey: .outerRadius)
      try container.encodeIfPresent(source.fromDegrees, forKey: .fromDegrees)
      try container.encodeIfPresent(source.toDegrees, forKey: .toDegrees)
      try container.encode(source.hysteresis, forKey: .hysteresis)
    case .triggerBand(let source):
      try container.encode(Kind.triggerBand, forKey: .type)
      try container.encode(source.trigger, forKey: .trigger)
      try container.encode(source.from, forKey: .from)
      try container.encode(source.to, forKey: .to)
      try container.encode(source.hysteresis, forKey: .hysteresis)
    case .touchArea(let source):
      try container.encode(Kind.touchArea, forKey: .type)
      try container.encode(source.surface, forKey: .surface)
      try container.encode(source.x, forKey: .x)
      try container.encode(source.y, forKey: .y)
      try container.encode(source.width, forKey: .width)
      try container.encode(source.height, forKey: .height)
    }
  }
}

/// A symbolic keyboard key, identified by its W3C key code name.
///
/// The raw value is the W3C `KeyboardEvent.code`. Platform adapters translate this value to an OS
/// key code.
public enum RemappingKeyboardKey: String, Codable, CaseIterable, Hashable, Sendable {
  /// The A key.
  case a = "KeyA"
  /// The B key.
  case b = "KeyB"
  /// The C key.
  case c = "KeyC"
  /// The D key.
  case d = "KeyD"
  /// The E key.
  case e = "KeyE"
  /// The F key.
  case f = "KeyF"
  /// The G key.
  case g = "KeyG"
  /// The H key.
  case h = "KeyH"
  /// The I key.
  case i = "KeyI"
  /// The J key.
  case j = "KeyJ"
  /// The K key.
  case k = "KeyK"
  /// The L key.
  case l = "KeyL"
  /// The M key.
  case m = "KeyM"
  /// The N key.
  case n = "KeyN"
  /// The O key.
  case o = "KeyO"
  /// The P key.
  case p = "KeyP"
  /// The Q key.
  case q = "KeyQ"
  /// The R key.
  case r = "KeyR"
  /// The S key.
  case s = "KeyS"
  /// The T key.
  case t = "KeyT"
  /// The U key.
  case u = "KeyU"
  /// The V key.
  case v = "KeyV"
  /// The W key.
  case w = "KeyW"
  /// The X key.
  case x = "KeyX"
  /// The Y key.
  case y = "KeyY"
  /// The Z key.
  case z = "KeyZ"
  /// The 0 key on the number row.
  case digit0 = "Digit0"
  /// The 1 key on the number row.
  case digit1 = "Digit1"
  /// The 2 key on the number row.
  case digit2 = "Digit2"
  /// The 3 key on the number row.
  case digit3 = "Digit3"
  /// The 4 key on the number row.
  case digit4 = "Digit4"
  /// The 5 key on the number row.
  case digit5 = "Digit5"
  /// The 6 key on the number row.
  case digit6 = "Digit6"
  /// The 7 key on the number row.
  case digit7 = "Digit7"
  /// The 8 key on the number row.
  case digit8 = "Digit8"
  /// The 9 key on the number row.
  case digit9 = "Digit9"
  /// The Escape key.
  case escape = "Escape"
  /// The Tab key.
  case tab = "Tab"
  /// The Caps Lock key.
  case capsLock = "CapsLock"
  /// The Space bar.
  case space = "Space"
  /// The Return key.
  case returnKey = "Enter"
  /// The Delete key that removes the character before the cursor (Backspace).
  case deleteBackward = "Backspace"
  /// The Delete key that removes the character after the cursor (Forward Delete).
  case deleteForward = "Delete"
  /// The Help key.
  case help = "Help"
  /// The Insert key.
  case insert = "Insert"
  /// The Home key.
  case home = "Home"
  /// The End key.
  case end = "End"
  /// The Page Up key.
  case pageUp = "PageUp"
  /// The Page Down key.
  case pageDown = "PageDown"
  /// The Up Arrow key.
  case arrowUp = "ArrowUp"
  /// The Down Arrow key.
  case arrowDown = "ArrowDown"
  /// The Left Arrow key.
  case arrowLeft = "ArrowLeft"
  /// The Right Arrow key.
  case arrowRight = "ArrowRight"
  /// The Minus key.
  case minus = "Minus"
  /// The Equal key.
  case equal = "Equal"
  /// The left bracket key.
  case leftBracket = "BracketLeft"
  /// The right bracket key.
  case rightBracket = "BracketRight"
  /// The Backslash key.
  case backslash = "Backslash"
  /// The Semicolon key.
  case semicolon = "Semicolon"
  /// The Quote key.
  case quote = "Quote"
  /// The Comma key.
  case comma = "Comma"
  /// The Period key.
  case period = "Period"
  /// The Slash key.
  case slash = "Slash"
  /// The Grave (backquote) key.
  case grave = "Backquote"
  /// The key next to Left Shift on ISO layouts (Intl Backslash).
  case section = "IntlBackslash"
  /// The F1 key.
  case f1 = "F1"
  /// The F2 key.
  case f2 = "F2"
  /// The F3 key.
  case f3 = "F3"
  /// The F4 key.
  case f4 = "F4"
  /// The F5 key.
  case f5 = "F5"
  /// The F6 key.
  case f6 = "F6"
  /// The F7 key.
  case f7 = "F7"
  /// The F8 key.
  case f8 = "F8"
  /// The F9 key.
  case f9 = "F9"
  /// The F10 key.
  case f10 = "F10"
  /// The F11 key.
  case f11 = "F11"
  /// The F12 key.
  case f12 = "F12"
  /// The F13 key.
  case f13 = "F13"
  /// The F14 key.
  case f14 = "F14"
  /// The F15 key.
  case f15 = "F15"
  /// The F16 key.
  case f16 = "F16"
  /// The F17 key.
  case f17 = "F17"
  /// The F18 key.
  case f18 = "F18"
  /// The F19 key.
  case f19 = "F19"
  /// The F20 key.
  case f20 = "F20"
  /// The 0 key of the numeric keypad.
  case keypad0 = "Numpad0"
  /// The 1 key of the numeric keypad.
  case keypad1 = "Numpad1"
  /// The 2 key of the numeric keypad.
  case keypad2 = "Numpad2"
  /// The 3 key of the numeric keypad.
  case keypad3 = "Numpad3"
  /// The 4 key of the numeric keypad.
  case keypad4 = "Numpad4"
  /// The 5 key of the numeric keypad.
  case keypad5 = "Numpad5"
  /// The 6 key of the numeric keypad.
  case keypad6 = "Numpad6"
  /// The 7 key of the numeric keypad.
  case keypad7 = "Numpad7"
  /// The 8 key of the numeric keypad.
  case keypad8 = "Numpad8"
  /// The 9 key of the numeric keypad.
  case keypad9 = "Numpad9"
  /// The decimal key of the numeric keypad.
  case keypadDecimal = "NumpadDecimal"
  /// The multiply key of the numeric keypad.
  case keypadMultiply = "NumpadMultiply"
  /// The plus key of the numeric keypad.
  case keypadPlus = "NumpadAdd"
  /// The Clear (Num Lock) key of the numeric keypad.
  case keypadClear = "NumLock"
  /// The divide key of the numeric keypad.
  case keypadDivide = "NumpadDivide"
  /// The Enter key of the numeric keypad.
  case keypadEnter = "NumpadEnter"
  /// The minus key of the numeric keypad.
  case keypadMinus = "NumpadSubtract"
  /// The equal key of the numeric keypad.
  case keypadEqual = "NumpadEqual"
}

/// Modifier key held together with a keyboard key.
public enum RemappingKeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
  /// The Meta key (Command on macOS).
  case meta = "Meta"
  /// The Control key.
  case control = "Control"
  /// The Alt key (Option on macOS).
  case alt = "Alt"
  /// The Shift key.
  case shift = "Shift"
}

/// Button of the pointer.
public enum RemappingMouseButton: String, Codable, CaseIterable, Hashable, Sendable {
  /// The left button.
  case left = "Left"
  /// The right button.
  case right = "Right"
  /// The middle button.
  case middle = "Middle"
  /// The back button.
  case back = "Back"
  /// The forward button.
  case forward = "Forward"
}

/// Axis of the pointer or of scrolling.
public enum RemappingPointerAxis: String, Codable, CaseIterable, Hashable, Sendable {
  /// Horizontal.
  case x = "X"
  /// Vertical.
  case y = "Y"
}
