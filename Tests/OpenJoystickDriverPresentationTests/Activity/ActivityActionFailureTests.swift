import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityActionFailureTests {
  @Test
  func theTextJoinsTheTitleAndTheMessage() {
    #expect(
      ActivityActionFailure(title: "Save failed", message: "Disk full").text
        == "Save failed Disk full"
    )
    #expect(ActivityActionFailure(title: "Save failed", message: nil).text == "Save failed")
  }
}
