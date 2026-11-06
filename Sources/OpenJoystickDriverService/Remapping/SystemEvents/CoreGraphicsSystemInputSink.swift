import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OpenJoystickDriverKit

/// The failure to post a keyboard or pointer event through CoreGraphics.
public enum CoreGraphicsSystemInputSinkError: Error, Equatable, LocalizedError, Sendable {
  /// Post-event access is not granted.
  case postEventAccessNotGranted
  /// The profile key has no macOS virtual key.
  case unsupportedKeyboardKey(RemappingKeyboardKey)
  /// CoreGraphics could not create the event.
  case eventPreparationFailed
  /// CoreGraphics could not post the event.
  case eventPostingFailed

  /// The text that explains the failure to a user.
  public var errorDescription: String? {
    switch self {
    case .postEventAccessNotGranted: "Keyboard and pointer posting access is not granted."
    case .unsupportedKeyboardKey(let key):
      "The keyboard key '\(key.rawValue)' is not supported on macOS."
    case .eventPreparationFailed: "CoreGraphics could not prepare a system-input event."
    case .eventPostingFailed: "CoreGraphics could not post a system-input event."
    }
  }
}

/// The modifier keys that are held down.
struct CoreGraphicsModifierFlags: OptionSet, Equatable, Sendable {
  /// The bits of the held modifiers.
  let rawValue: UInt64

  /// The Command key.
  static let command = Self(rawValue: 1 << 0)
  /// The Control key.
  static let control = Self(rawValue: 1 << 1)
  /// The Option key.
  static let option = Self(rawValue: 1 << 2)
  /// The Shift key.
  static let shift = Self(rawValue: 1 << 3)
}

/// A mouse button, with its CoreGraphics button number.
enum CoreGraphicsMouseButton: UInt32, Equatable, Sendable {
  /// The left button.
  case left = 0
  /// The right button.
  case right = 1
  /// The middle button.
  case middle = 2
  /// The back button.
  case back = 3
  /// The forward button.
  case forward = 4
}

/// An event that is ready to post.
enum CoreGraphicsPreparedEvent: Equatable, Sendable {
  /// A key press or release with the held modifiers.
  case keyboard(virtualKey: CGKeyCode, isDown: Bool, flags: CoreGraphicsModifierFlags)
  /// A change of the held modifiers by the modifier key `virtualKey`.
  case modifier(virtualKey: CGKeyCode, flags: CoreGraphicsModifierFlags)
  /// A mouse button press or release at `location`.
  case mouseButton(button: CoreGraphicsMouseButton, isDown: Bool, location: CGPoint)
  /// A pointer move to `location` by the given deltas.
  case pointer(location: CGPoint, deltaX: Double, deltaY: Double)
  /// A scroll by the given line counts.
  case scroll(deltaX: Int32, deltaY: Int32)
}

/// The failure to create a CoreGraphics event.
enum CoreGraphicsEventPosterError: Error {
  /// The system refused to create the event.
  case eventCreationFailed
}

/// Posts prepared events and reads the pointer position.
protocol CoreGraphicsEventPosting: Sendable {
  /// Returns the current pointer position.
  func currentPointerLocation() throws -> CGPoint
  /// Posts `event`.
  func post(_ event: CoreGraphicsPreparedEvent) throws
}

/// Maps a profile key to a macOS virtual key.
protocol CoreGraphicsKeyboardTranslating: Sendable {
  /// Returns the virtual key of `key`, or nil when macOS has none.
  func virtualKey(for key: RemappingKeyboardKey) -> CGKeyCode?
}

/// The poster that creates CoreGraphics events and posts them to the HID event tap.
private struct PlatformCoreGraphicsEventPoster: CoreGraphicsEventPosting {
  /// Returns the pointer position that a CoreGraphics event reports.
  ///
  /// - Throws: ``CoreGraphicsEventPosterError/eventCreationFailed`` when the event cannot be
  ///   created.
  func currentPointerLocation() throws -> CGPoint {
    guard let event = CGEvent(source: nil) else {
      throw CoreGraphicsEventPosterError.eventCreationFailed
    }
    return event.location
  }

  /// Creates the CoreGraphics event of `prepared` and posts it to the HID event tap.
  ///
  /// - Throws: ``CoreGraphicsEventPosterError/eventCreationFailed`` when the source or event cannot
  ///   be created.
  func post(_ prepared: CoreGraphicsPreparedEvent) throws {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
      throw CoreGraphicsEventPosterError.eventCreationFailed
    }
    let event: CGEvent?
    switch prepared {
    case .keyboard(let virtualKey, let isDown, let flags):
      event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: isDown)
      event?.flags = CoreGraphicsMapping.cgEventFlags(for: flags)
    case .modifier(let virtualKey, let flags):
      event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
      event?.type = .flagsChanged
      event?.flags = CoreGraphicsMapping.cgEventFlags(for: flags)
    case .mouseButton(let button, let isDown, let location):
      guard let mouseButton = CGMouseButton(rawValue: button.rawValue) else {
        throw CoreGraphicsEventPosterError.eventCreationFailed
      }
      event = CGEvent(
        mouseEventSource: source,
        mouseType: CoreGraphicsMapping.eventType(for: button, isDown: isDown),
        mouseCursorPosition: location,
        mouseButton: mouseButton
      )
      event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    case .pointer(let location, let deltaX, let deltaY):
      event = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: location,
        mouseButton: .left
      )
      event?.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
      event?.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
    case .scroll(let deltaX, let deltaY):
      event = CGEvent(
        scrollWheelEvent2Source: source,
        units: .line,
        wheelCount: 2,
        wheel1: deltaY,
        wheel2: deltaX,
        wheel3: 0
      )
    }
    guard let event else { throw CoreGraphicsEventPosterError.eventCreationFailed }
    event.post(tap: .cghidEventTap)
  }
}

/// The translator from profile keys to macOS virtual keys.
struct MacVirtualKeyTranslator: CoreGraphicsKeyboardTranslating {
  // macOS exposes Help but no distinct Insert virtual key. Both symbolic
  // profile keys intentionally address the platform Help/Insert key at 0x72.
  /// Returns the virtual key of `key`; the Help and Insert keys both map to the Help key.
  func virtualKey(for key: RemappingKeyboardKey) -> CGKeyCode? {
    let value: Int
    switch key {
    case .a: value = kVK_ANSI_A
    case .b: value = kVK_ANSI_B
    case .c: value = kVK_ANSI_C
    case .d: value = kVK_ANSI_D
    case .e: value = kVK_ANSI_E
    case .f: value = kVK_ANSI_F
    case .g: value = kVK_ANSI_G
    case .h: value = kVK_ANSI_H
    case .i: value = kVK_ANSI_I
    case .j: value = kVK_ANSI_J
    case .k: value = kVK_ANSI_K
    case .l: value = kVK_ANSI_L
    case .m: value = kVK_ANSI_M
    case .n: value = kVK_ANSI_N
    case .o: value = kVK_ANSI_O
    case .p: value = kVK_ANSI_P
    case .q: value = kVK_ANSI_Q
    case .r: value = kVK_ANSI_R
    case .s: value = kVK_ANSI_S
    case .t: value = kVK_ANSI_T
    case .u: value = kVK_ANSI_U
    case .v: value = kVK_ANSI_V
    case .w: value = kVK_ANSI_W
    case .x: value = kVK_ANSI_X
    case .y: value = kVK_ANSI_Y
    case .z: value = kVK_ANSI_Z
    case .digit0: value = kVK_ANSI_0
    case .digit1: value = kVK_ANSI_1
    case .digit2: value = kVK_ANSI_2
    case .digit3: value = kVK_ANSI_3
    case .digit4: value = kVK_ANSI_4
    case .digit5: value = kVK_ANSI_5
    case .digit6: value = kVK_ANSI_6
    case .digit7: value = kVK_ANSI_7
    case .digit8: value = kVK_ANSI_8
    case .digit9: value = kVK_ANSI_9
    case .escape: value = kVK_Escape
    case .tab: value = kVK_Tab
    case .capsLock: value = kVK_CapsLock
    case .space: value = kVK_Space
    case .returnKey: value = kVK_Return
    case .deleteBackward: value = kVK_Delete
    case .deleteForward: value = kVK_ForwardDelete
    case .help, .insert: value = kVK_Help
    case .home: value = kVK_Home
    case .end: value = kVK_End
    case .pageUp: value = kVK_PageUp
    case .pageDown: value = kVK_PageDown
    case .arrowUp: value = kVK_UpArrow
    case .arrowDown: value = kVK_DownArrow
    case .arrowLeft: value = kVK_LeftArrow
    case .arrowRight: value = kVK_RightArrow
    case .minus: value = kVK_ANSI_Minus
    case .equal: value = kVK_ANSI_Equal
    case .leftBracket: value = kVK_ANSI_LeftBracket
    case .rightBracket: value = kVK_ANSI_RightBracket
    case .backslash: value = kVK_ANSI_Backslash
    case .semicolon: value = kVK_ANSI_Semicolon
    case .quote: value = kVK_ANSI_Quote
    case .comma: value = kVK_ANSI_Comma
    case .period: value = kVK_ANSI_Period
    case .slash: value = kVK_ANSI_Slash
    case .grave: value = kVK_ANSI_Grave
    case .section: value = kVK_ISO_Section
    case .f1: value = kVK_F1
    case .f2: value = kVK_F2
    case .f3: value = kVK_F3
    case .f4: value = kVK_F4
    case .f5: value = kVK_F5
    case .f6: value = kVK_F6
    case .f7: value = kVK_F7
    case .f8: value = kVK_F8
    case .f9: value = kVK_F9
    case .f10: value = kVK_F10
    case .f11: value = kVK_F11
    case .f12: value = kVK_F12
    case .f13: value = kVK_F13
    case .f14: value = kVK_F14
    case .f15: value = kVK_F15
    case .f16: value = kVK_F16
    case .f17: value = kVK_F17
    case .f18: value = kVK_F18
    case .f19: value = kVK_F19
    case .f20: value = kVK_F20
    case .keypad0: value = kVK_ANSI_Keypad0
    case .keypad1: value = kVK_ANSI_Keypad1
    case .keypad2: value = kVK_ANSI_Keypad2
    case .keypad3: value = kVK_ANSI_Keypad3
    case .keypad4: value = kVK_ANSI_Keypad4
    case .keypad5: value = kVK_ANSI_Keypad5
    case .keypad6: value = kVK_ANSI_Keypad6
    case .keypad7: value = kVK_ANSI_Keypad7
    case .keypad8: value = kVK_ANSI_Keypad8
    case .keypad9: value = kVK_ANSI_Keypad9
    case .keypadDecimal: value = kVK_ANSI_KeypadDecimal
    case .keypadMultiply: value = kVK_ANSI_KeypadMultiply
    case .keypadPlus: value = kVK_ANSI_KeypadPlus
    case .keypadClear: value = kVK_ANSI_KeypadClear
    case .keypadDivide: value = kVK_ANSI_KeypadDivide
    case .keypadEnter: value = kVK_ANSI_KeypadEnter
    case .keypadMinus: value = kVK_ANSI_KeypadMinus
    case .keypadEqual: value = kVK_ANSI_KeypadEquals
    }
    return CGKeyCode(value)
  }
}

/// CoreGraphics implementation of the remapping engine's system-input port.
public final class CoreGraphicsSystemInputSink: RemappingSystemInputSink, @unchecked Sendable {
  /// The points that a full pointer action moves the pointer.
  static let pointerPointsPerAction = 32.0
  /// The lines that a full scroll action scrolls.
  static let scrollLinesPerAction = 8.0

  /// The lock that serializes `send(_:)`.
  let lock = NSLock()
  /// The post-event access that `send(_:)` checks.
  let access: CoreGraphicsPostEventAccess
  /// The poster of the events.
  let poster: any CoreGraphicsEventPosting
  /// The translator from profile keys to virtual keys.
  let translator: any CoreGraphicsKeyboardTranslating
  /// The modifiers that are held down.
  var modifierFlags: CoreGraphicsModifierFlags = []
  /// The fraction of a line not yet scrolled horizontally.
  var scrollResidualX = 0.0
  /// The fraction of a line not yet scrolled vertically.
  var scrollResidualY = 0.0

  /// Creates the sink with the system post-event access.
  public convenience init() { self.init(access: CoreGraphicsPostEventAccess()) }

  /// Creates the sink with `access`.
  public init(access: CoreGraphicsPostEventAccess) {
    self.access = access
    poster = PlatformCoreGraphicsEventPoster()
    translator = MacVirtualKeyTranslator()
  }

  /// Creates the sink with the given access, poster and translator.
  init(
    access: CoreGraphicsPostEventAccess,
    poster: any CoreGraphicsEventPosting,
    translator: any CoreGraphicsKeyboardTranslating = MacVirtualKeyTranslator()
  ) {
    self.access = access
    self.poster = poster
    self.translator = translator
  }
}

/// The mapping from the engine's key, button and modifier values to CoreGraphics values.
enum CoreGraphicsMapping {
  /// Returns the CoreGraphics event flags of `flags`.
  static func cgEventFlags(for flags: CoreGraphicsModifierFlags) -> CGEventFlags {
    var result: CGEventFlags = []
    if flags.contains(.command) { result.insert(.maskCommand) }
    if flags.contains(.control) { result.insert(.maskControl) }
    if flags.contains(.option) { result.insert(.maskAlternate) }
    if flags.contains(.shift) { result.insert(.maskShift) }
    return result
  }

  /// Returns the modifier flag of `modifier`.
  static func coreGraphicsFlag(for modifier: RemappingKeyModifier) -> CoreGraphicsModifierFlags {
    switch modifier {
    case .meta: .command
    case .control: .control
    case .alt: .option
    case .shift: .shift
    }
  }

  /// Returns the virtual key of the modifier key `modifier`.
  static func virtualKey(for modifier: RemappingKeyModifier) -> CGKeyCode {
    switch modifier {
    case .meta: CGKeyCode(kVK_Command)
    case .control: CGKeyCode(kVK_Control)
    case .alt: CGKeyCode(kVK_Option)
    case .shift: CGKeyCode(kVK_Shift)
    }
  }

  /// Returns the CoreGraphics button of `button`.
  static func coreGraphicsButton(for button: RemappingMouseButton) -> CoreGraphicsMouseButton {
    switch button {
    case .left: .left
    case .right: .right
    case .middle: .middle
    case .back: .back
    case .forward: .forward
    }
  }

  /// Returns the event type of pressing or releasing `button`.
  static func eventType(for button: CoreGraphicsMouseButton, isDown: Bool) -> CGEventType {
    switch button {
    case .left: isDown ? .leftMouseDown : .leftMouseUp
    case .right: isDown ? .rightMouseDown : .rightMouseUp
    case .middle, .back, .forward: isDown ? .otherMouseDown : .otherMouseUp
    }
  }

  /// Returns `value` limited to the range from -1 to 1.
  static func clampedNormalized(_ value: Double) -> Double { min(1, max(-1, value)) }
}
