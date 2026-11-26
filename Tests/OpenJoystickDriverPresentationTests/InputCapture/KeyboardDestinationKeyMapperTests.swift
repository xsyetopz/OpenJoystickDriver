import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct KeyboardDestinationKeyMapperTests {
  @Test(arguments: [
    (UInt16(36), RemappingKeyboardKey.returnKey),
    (10, .section),
    (110, .insert),
    (114, .help),
    (122, .f1),
    (90, .f20),
    (82, .keypad0),
    (81, .keypadEqual),
  ])
  func hardwareKeyCodeNamesItsKey(_ keyCode: UInt16, _ key: RemappingKeyboardKey) {
    #expect(KeyboardDestinationKeyMapper.key(keyCode: keyCode, character: nil) == key)
  }

  @Test
  func hardwareKeyCodeWinsOverTheCharacter() {
    #expect(KeyboardDestinationKeyMapper.key(keyCode: 49, character: "q") == .space)
  }

  @Test(arguments: [
    (Character("a"), RemappingKeyboardKey.a),
    ("z", .z),
    ("0", .digit0),
    ("9", .digit9),
    (" ", .space),
    ("\\", .backslash),
    ("'", .quote),
    ("`", .grave),
  ])
  func characterNamesItsKeyWhenTheCodeHasNone(_ character: Character, _ key: RemappingKeyboardKey) {
    #expect(KeyboardDestinationKeyMapper.key(keyCode: 0xFFFF, character: character) == key)
  }

  @Test
  func unknownCodeAndCharacterNameNoKey() {
    #expect(KeyboardDestinationKeyMapper.key(keyCode: 0xFFFF, character: nil) == nil)
    #expect(KeyboardDestinationKeyMapper.key(keyCode: 0xFFFF, character: "é") == nil)
  }
}
