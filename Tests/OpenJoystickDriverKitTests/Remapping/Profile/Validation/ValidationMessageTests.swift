import Testing

@testable import OpenJoystickDriverKit

struct ValidationMessageTests {
  private let english = Localization(preferredLanguages: ["en-US"])

  @Test
  func bindingLimitMessageAgreesWithItsCount() {
    let key = "ui.profileValidation.tooManyBindings"

    let one = english.plural(key, count: 1)
    let many = english.plural(key, count: 513)

    #expect(one == "A profile cannot contain 1 binding. Remove some; the limit is 512.")
    #expect(many == "A profile cannot contain 513 bindings. Remove some; the limit is 512.")
  }

  @Test
  func positionKeepsItsDigitsUngrouped() throws {
    let message = try #require(
      RemappingValidationError.invalidMacroStepDestination(index: 1234, step: 5678).errorDescription
    )

    #expect(message.contains("1234"))
    #expect(message.contains("5678"))
  }
}
