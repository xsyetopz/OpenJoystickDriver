import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct OJDValueTests {
  @Test
  func missingValueIsSpokenAsItIsShown() {
    let value = OJDValue(nil)

    #expect(value.spokenText == value.displayText)
    #expect(value.accessibilityKey.map { OJDLocalized.string($0) } == value.displayText)
  }
}
