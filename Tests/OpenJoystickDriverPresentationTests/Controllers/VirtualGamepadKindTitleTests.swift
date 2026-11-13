import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// The option titles of the virtual gamepad kind picker: the phrase in Simple, and the phrase with
/// the identifier in Advanced.
@MainActor
struct VirtualGamepadKindTitleTests {
  private static let phrases: [(VirtualHIDProfileID, String)] = [
    (.sdlCompatible, "For Steam and SDL games"),
    (.gameControllerCompatible, "For Apple Game Controller games"),
    (.generic, "Generic HID gamepad"),
  ]

  @Test
  func simpleShowsPhraseAlone() {
    for (kind, phrase) in Self.phrases {
      #expect(VirtualHIDProfileKinds.optionTitle(for: kind, level: .simple) == phrase)
    }
  }

  @Test
  func advancedShowsPhraseWithIdentifier() {
    for (kind, phrase) in Self.phrases {
      #expect(
        VirtualHIDProfileKinds.optionTitle(for: kind, level: .advanced)
          == "\(phrase) (\(kind.rawValue))"
      )
    }
  }

  @Test
  func everyKindHasPhrase() {
    #expect(Set(Self.phrases.map(\.0)) == Set(VirtualHIDProfileID.allCases))
  }
}
