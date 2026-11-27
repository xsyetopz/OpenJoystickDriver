import Carbon.HIToolbox
import CoreGraphics
public import Foundation
public import OpenJoystickDriverKit

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
    let localized = Localization()
    return switch self {
    case .postEventAccessNotGranted:
      localized.string("platform.macos.systemInput.postEventAccessNotGranted")
    case .unsupportedKeyboardKey(let key):
      localized.string("platform.macos.systemInput.unsupportedKeyboardKey", key.rawValue)
    case .eventPreparationFailed:
      localized.string("platform.macos.systemInput.eventPreparationFailed")
    case .eventPostingFailed: localized.string("platform.macos.systemInput.eventPostingFailed")
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
  /// Returns the bounds of the main display in the coordinates of pointer events.
  func mainDisplayBounds() throws -> CGRect
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

  /// Returns the bounds of the main display.
  func mainDisplayBounds() -> CGRect { CGDisplayBounds(CGMainDisplayID()) }

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
  // profile keys address the platform Help/Insert key at 0x72.
  /// Returns the virtual key of `key`; the Help and Insert keys both map to the Help key.
  func virtualKey(for key: RemappingKeyboardKey) -> CGKeyCode? {
    Self.virtualKeys[key].map(CGKeyCode.init)
  }

  /// The virtual key of each profile key; `MacVirtualKeyTranslatorTests` checks that every key
  /// has one.
  private static let virtualKeys: [RemappingKeyboardKey: Int] = [
    .a: kVK_ANSI_A,
    .b: kVK_ANSI_B,
    .c: kVK_ANSI_C,
    .d: kVK_ANSI_D,
    .e: kVK_ANSI_E,
    .f: kVK_ANSI_F,
    .g: kVK_ANSI_G,
    .h: kVK_ANSI_H,
    .i: kVK_ANSI_I,
    .j: kVK_ANSI_J,
    .k: kVK_ANSI_K,
    .l: kVK_ANSI_L,
    .m: kVK_ANSI_M,
    .n: kVK_ANSI_N,
    .o: kVK_ANSI_O,
    .p: kVK_ANSI_P,
    .q: kVK_ANSI_Q,
    .r: kVK_ANSI_R,
    .s: kVK_ANSI_S,
    .t: kVK_ANSI_T,
    .u: kVK_ANSI_U,
    .v: kVK_ANSI_V,
    .w: kVK_ANSI_W,
    .x: kVK_ANSI_X,
    .y: kVK_ANSI_Y,
    .z: kVK_ANSI_Z,
    .digit0: kVK_ANSI_0,
    .digit1: kVK_ANSI_1,
    .digit2: kVK_ANSI_2,
    .digit3: kVK_ANSI_3,
    .digit4: kVK_ANSI_4,
    .digit5: kVK_ANSI_5,
    .digit6: kVK_ANSI_6,
    .digit7: kVK_ANSI_7,
    .digit8: kVK_ANSI_8,
    .digit9: kVK_ANSI_9,
    .escape: kVK_Escape,
    .tab: kVK_Tab,
    .capsLock: kVK_CapsLock,
    .space: kVK_Space,
    .returnKey: kVK_Return,
    .deleteBackward: kVK_Delete,
    .deleteForward: kVK_ForwardDelete,
    .help: kVK_Help,
    .insert: kVK_Help,
    .home: kVK_Home,
    .end: kVK_End,
    .pageUp: kVK_PageUp,
    .pageDown: kVK_PageDown,
    .arrowUp: kVK_UpArrow,
    .arrowDown: kVK_DownArrow,
    .arrowLeft: kVK_LeftArrow,
    .arrowRight: kVK_RightArrow,
    .minus: kVK_ANSI_Minus,
    .equal: kVK_ANSI_Equal,
    .leftBracket: kVK_ANSI_LeftBracket,
    .rightBracket: kVK_ANSI_RightBracket,
    .backslash: kVK_ANSI_Backslash,
    .semicolon: kVK_ANSI_Semicolon,
    .quote: kVK_ANSI_Quote,
    .comma: kVK_ANSI_Comma,
    .period: kVK_ANSI_Period,
    .slash: kVK_ANSI_Slash,
    .grave: kVK_ANSI_Grave,
    .section: kVK_ISO_Section,
    .f1: kVK_F1,
    .f2: kVK_F2,
    .f3: kVK_F3,
    .f4: kVK_F4,
    .f5: kVK_F5,
    .f6: kVK_F6,
    .f7: kVK_F7,
    .f8: kVK_F8,
    .f9: kVK_F9,
    .f10: kVK_F10,
    .f11: kVK_F11,
    .f12: kVK_F12,
    .f13: kVK_F13,
    .f14: kVK_F14,
    .f15: kVK_F15,
    .f16: kVK_F16,
    .f17: kVK_F17,
    .f18: kVK_F18,
    .f19: kVK_F19,
    .f20: kVK_F20,
    .keypad0: kVK_ANSI_Keypad0,
    .keypad1: kVK_ANSI_Keypad1,
    .keypad2: kVK_ANSI_Keypad2,
    .keypad3: kVK_ANSI_Keypad3,
    .keypad4: kVK_ANSI_Keypad4,
    .keypad5: kVK_ANSI_Keypad5,
    .keypad6: kVK_ANSI_Keypad6,
    .keypad7: kVK_ANSI_Keypad7,
    .keypad8: kVK_ANSI_Keypad8,
    .keypad9: kVK_ANSI_Keypad9,
    .keypadDecimal: kVK_ANSI_KeypadDecimal,
    .keypadMultiply: kVK_ANSI_KeypadMultiply,
    .keypadPlus: kVK_ANSI_KeypadPlus,
    .keypadClear: kVK_ANSI_KeypadClear,
    .keypadDivide: kVK_ANSI_KeypadDivide,
    .keypadEnter: kVK_ANSI_KeypadEnter,
    .keypadMinus: kVK_ANSI_KeypadMinus,
    .keypadEqual: kVK_ANSI_KeypadEquals,
  ]
}

/// CoreGraphics implementation of the remapping engine's system-input port.
public final class CoreGraphicsSystemInputSink: RemappingSystemInputSink, @unchecked Sendable {
  /// The points that a full pointer action moves the pointer.
  static let pointerPointsPerAction = 32.0
  /// The lines that a full scroll action scrolls.
  static let scrollLinesPerAction = 8.0

  /// The lock that lets one `send(_:)` run at a time.
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
