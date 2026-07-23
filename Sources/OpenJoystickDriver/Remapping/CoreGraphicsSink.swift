import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OpenJoystickDriverKit

public enum CoreGraphicsSystemInputSinkError: Error, Equatable, LocalizedError, Sendable {
  case postEventAccessNotGranted
  case unsupportedKeyboardKey(RemappingKeyboardKey)
  case eventPreparationFailed
  case eventPostingFailed

  public var errorDescription: String? {
    switch self {
    case .postEventAccessNotGranted:
      "Keyboard and pointer posting access is not granted."
    case .unsupportedKeyboardKey(let key):
      "The keyboard key '\(key.rawValue)' is not supported on macOS."
    case .eventPreparationFailed:
      "CoreGraphics could not prepare a system-input event."
    case .eventPostingFailed:
      "CoreGraphics could not post a system-input event."
    }
  }
}

struct CoreGraphicsModifierFlags: OptionSet, Equatable, Sendable {
  let rawValue: UInt64

  static let command = Self(rawValue: 1 << 0)
  static let control = Self(rawValue: 1 << 1)
  static let option = Self(rawValue: 1 << 2)
  static let shift = Self(rawValue: 1 << 3)
}

enum CoreGraphicsMouseButton: UInt32, Equatable, Sendable {
  case left = 0
  case right = 1
  case middle = 2
  case back = 3
  case forward = 4
}

enum CoreGraphicsPreparedEvent: Equatable, Sendable {
  case keyboard(virtualKey: CGKeyCode, isDown: Bool, flags: CoreGraphicsModifierFlags)
  case modifier(virtualKey: CGKeyCode, flags: CoreGraphicsModifierFlags)
  case mouseButton(button: CoreGraphicsMouseButton, isDown: Bool, location: CGPoint)
  case pointer(location: CGPoint, deltaX: Double, deltaY: Double)
  case scroll(deltaX: Int32, deltaY: Int32)
}

enum CoreGraphicsEventPosterError: Error {
  case eventCreationFailed
}

protocol CoreGraphicsEventPosting: Sendable {
  func currentPointerLocation() throws -> CGPoint
  func post(_ event: CoreGraphicsPreparedEvent) throws
}

protocol CoreGraphicsKeyboardTranslating: Sendable {
  func virtualKey(for key: RemappingKeyboardKey) -> CGKeyCode?
}

private struct PlatformCoreGraphicsEventPoster: CoreGraphicsEventPosting {
  func currentPointerLocation() throws -> CGPoint {
    guard let event = CGEvent(source: nil) else {
      throw CoreGraphicsEventPosterError.eventCreationFailed
    }
    return event.location
  }

  func post(_ prepared: CoreGraphicsPreparedEvent) throws {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
      throw CoreGraphicsEventPosterError.eventCreationFailed
    }
    let event: CGEvent?
    switch prepared {
    case .keyboard(let virtualKey, let isDown, let flags):
      event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: isDown)
      event?.flags = flags.cgEventFlags
    case .modifier(let virtualKey, let flags):
      event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
      event?.type = .flagsChanged
      event?.flags = flags.cgEventFlags
    case .mouseButton(let button, let isDown, let location):
      guard let mouseButton = CGMouseButton(rawValue: button.rawValue) else {
        throw CoreGraphicsEventPosterError.eventCreationFailed
      }
      event = CGEvent(
        mouseEventSource: source,
        mouseType: button.eventType(isDown: isDown),
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
    guard let event else {
      throw CoreGraphicsEventPosterError.eventCreationFailed
    }
    event.post(tap: .cghidEventTap)
  }
}

struct MacVirtualKeyTranslator: CoreGraphicsKeyboardTranslating {
  // macOS exposes Help but no distinct Insert virtual key. Both symbolic
  // profile keys intentionally address the platform Help/Insert key at 0x72.
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
  static let pointerPointsPerAction = 32.0
  static let scrollLinesPerAction = 8.0

  private let lock = NSLock()
  private let access: CoreGraphicsPostEventAccess
  private let poster: any CoreGraphicsEventPosting
  private let translator: any CoreGraphicsKeyboardTranslating
  private var modifierFlags: CoreGraphicsModifierFlags = []
  private var scrollResidualX = 0.0
  private var scrollResidualY = 0.0

  public convenience init() {
    self.init(access: CoreGraphicsPostEventAccess())
  }

  public init(access: CoreGraphicsPostEventAccess) {
    self.access = access
    poster = PlatformCoreGraphicsEventPoster()
    translator = MacVirtualKeyTranslator()
  }

  init(
    access: CoreGraphicsPostEventAccess,
    poster: any CoreGraphicsEventPosting,
    translator: any CoreGraphicsKeyboardTranslating = MacVirtualKeyTranslator()
  ) {
    self.access = access
    self.poster = poster
    self.translator = translator
  }

  public func send(_ action: RemappingSystemInputAction) throws {
    lock.lock()
    defer { lock.unlock() }
    guard access.currentState() == .granted else {
      throw CoreGraphicsSystemInputSinkError.postEventAccessNotGranted
    }
    do {
      try sendAuthorized(action)
    } catch let error as CoreGraphicsSystemInputSinkError {
      throw error
    } catch CoreGraphicsEventPosterError.eventCreationFailed {
      throw CoreGraphicsSystemInputSinkError.eventPreparationFailed
    } catch {
      throw CoreGraphicsSystemInputSinkError.eventPostingFailed
    }
  }

  private func sendAuthorized(_ action: RemappingSystemInputAction) throws {
    switch action {
    case .modifierDown(let modifier):
      try postModifier(modifier, isDown: true)
    case .modifierUp(let modifier):
      try postModifier(modifier, isDown: false)
    case .keyDown(let key):
      try postKey(key, isDown: true)
    case .keyUp(let key):
      try postKey(key, isDown: false)
    case .mouseButtonDown(let button):
      try postMouseButton(button, isDown: true)
    case .mouseButtonUp(let button):
      try postMouseButton(button, isDown: false)
    case .mouseMoved(let axis, let amount):
      try postPointer(axis: axis, amount: amount)
    case .scrolled(let axis, let amount):
      try postScroll(axis: axis, amount: amount)
    }
  }

  private func postModifier(_ modifier: RemappingKeyModifier, isDown: Bool) throws {
    let flag = modifier.coreGraphicsFlag
    var candidate = modifierFlags
    if isDown { candidate.insert(flag) } else { candidate.remove(flag) }
    try poster.post(.modifier(virtualKey: modifier.virtualKey, flags: candidate))
    modifierFlags = candidate
  }

  private func postKey(_ key: RemappingKeyboardKey, isDown: Bool) throws {
    guard let virtualKey = translator.virtualKey(for: key) else {
      throw CoreGraphicsSystemInputSinkError.unsupportedKeyboardKey(key)
    }
    try poster.post(.keyboard(virtualKey: virtualKey, isDown: isDown, flags: modifierFlags))
  }

  private func postMouseButton(_ button: RemappingMouseButton, isDown: Bool) throws {
    let location = try poster.currentPointerLocation()
    try poster.post(.mouseButton(
      button: button.coreGraphicsButton,
      isDown: isDown,
      location: location
    ))
  }

  private func postPointer(axis: RemappingPointerAxis, amount: Double) throws {
    guard amount.isFinite else { throw CoreGraphicsSystemInputSinkError.eventPreparationFailed }
    if amount == 0 { return }
    let delta = amount.clampedNormalized * Self.pointerPointsPerAction
    // Read every action so physical mouse movement between remapping ticks is
    // never overwritten by a stale synthetic-cursor cache.
    let origin = try poster.currentPointerLocation()
    let deltaX = axis == .x ? delta : 0
    let deltaY = axis == .y ? delta : 0
    let destination = CGPoint(x: origin.x + deltaX, y: origin.y + deltaY)
    try poster.post(.pointer(location: destination, deltaX: deltaX, deltaY: deltaY))
  }

  private func postScroll(axis: RemappingPointerAxis, amount: Double) throws {
    guard amount.isFinite else { throw CoreGraphicsSystemInputSinkError.eventPreparationFailed }
    if amount == 0 {
      if axis == .x { scrollResidualX = 0 } else { scrollResidualY = 0 }
      return
    }
    var candidateX = scrollResidualX
    var candidateY = scrollResidualY
    if axis == .x {
      candidateX += amount.clampedNormalized * Self.scrollLinesPerAction
    } else {
      candidateY += amount.clampedNormalized * Self.scrollLinesPerAction
    }
    let deltaX = Int32(candidateX.rounded(.towardZero))
    let deltaY = Int32(candidateY.rounded(.towardZero))
    candidateX -= Double(deltaX)
    candidateY -= Double(deltaY)
    if deltaX != 0 || deltaY != 0 {
      try poster.post(.scroll(deltaX: deltaX, deltaY: deltaY))
    }
    scrollResidualX = candidateX
    scrollResidualY = candidateY
  }
}

private extension CoreGraphicsModifierFlags {
  var cgEventFlags: CGEventFlags {
    var flags: CGEventFlags = []
    if contains(.command) { flags.insert(.maskCommand) }
    if contains(.control) { flags.insert(.maskControl) }
    if contains(.option) { flags.insert(.maskAlternate) }
    if contains(.shift) { flags.insert(.maskShift) }
    return flags
  }
}

private extension RemappingKeyModifier {
  var coreGraphicsFlag: CoreGraphicsModifierFlags {
    switch self {
    case .command: .command
    case .control: .control
    case .option: .option
    case .shift: .shift
    }
  }

  var virtualKey: CGKeyCode {
    switch self {
    case .command: CGKeyCode(kVK_Command)
    case .control: CGKeyCode(kVK_Control)
    case .option: CGKeyCode(kVK_Option)
    case .shift: CGKeyCode(kVK_Shift)
    }
  }
}

private extension RemappingMouseButton {
  var coreGraphicsButton: CoreGraphicsMouseButton {
    switch self {
    case .left: .left
    case .right: .right
    case .middle: .middle
    case .back: .back
    case .forward: .forward
    }
  }
}

private extension CoreGraphicsMouseButton {
  func eventType(isDown: Bool) -> CGEventType {
    switch self {
    case .left: isDown ? .leftMouseDown : .leftMouseUp
    case .right: isDown ? .rightMouseDown : .rightMouseUp
    case .middle, .back, .forward: isDown ? .otherMouseDown : .otherMouseUp
    }
  }
}

private extension Double {
  var clampedNormalized: Double {
    min(1, max(-1, self))
  }
}
