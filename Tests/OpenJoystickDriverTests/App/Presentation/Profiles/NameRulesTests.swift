import Testing

@testable import OpenJoystickDriver

@Suite struct NameRulesTests {
  @Test func trimsOuterWhitespaceBeforeCreating() {
    #expect(ProfileNameValidation.trimmedName("  Arcade  ") == "Arcade")
    #expect(ProfileNameValidation.canCreate(name: "  Arcade  ", hasSelectedDevice: true))
  }

  @Test func rejectsWhitespaceOnlyNamesEvenWhenADeviceIsSelected() {
    #expect(ProfileNameValidation.trimmedName(" \n\t ").isEmpty)
    #expect(!ProfileNameValidation.canCreate(name: " \n\t ", hasSelectedDevice: true))
  }

  @Test func requiresASelectedDevice() {
    #expect(!ProfileNameValidation.canCreate(name: "Arcade", hasSelectedDevice: false))
  }
}
