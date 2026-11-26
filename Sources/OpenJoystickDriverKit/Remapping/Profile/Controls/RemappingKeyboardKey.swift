import Foundation

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
