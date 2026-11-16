import Testing

@testable import OpenJoystickDriverService

struct PublicationFailureTextTests {
  private struct SilentError: Error, CustomStringConvertible {
    let description: String
  }

  private struct NamedError: Error, CustomStringConvertible {
    var description: String { "send failed" }
  }

  @Test
  func describedErrorKeepsItsDescription() {
    #expect(PublicationFailureText.text(for: NamedError()) == "send failed")
  }

  @Test(arguments: ["", " ", "\n\t"])
  func errorWithoutDescriptionIsNamedByTypeDomainAndCode(description: String) {
    let text = PublicationFailureText.text(for: SilentError(description: description))

    #expect(!text.isEmpty)
    #expect(text.contains("SilentError"))
  }
}
