import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityActionFailureTests {
  @Test
  func textJoinsTitleAndMessage() {
    #expect(
      ActivityActionFailure(title: "Save failed", message: "Disk full").text
        == "Save failed Disk full"
    )
    #expect(ActivityActionFailure(title: "Save failed", message: nil).text == "Save failed")
  }
}

@MainActor
@Suite
struct ActivityCheckFixFailureTests {
  private func model(failing reason: String?) -> ActivityModel {
    ActivityModel(
      log: ActivityLogModel(),
      diagnostics: ActivityDiagnosticsModel { [] }
    ) { _ in reason }
  }

  @Test
  func failedFixShowsOnItsCheckRowAndNotInAreaRow() {
    let model = model(failing: "Could not request access")

    model.perform(.requestInputRead, forCheck: "input-read")

    #expect(model.fixFailures["input-read"] == "Could not request access")
    #expect(model.failure == nil)
  }

  @Test
  func fixWorksClearsFailureOfItsCheckRow() {
    let model = model(failing: nil)
    model.fixFailures["input-read"] = "Could not request access"

    model.perform(.requestInputRead, forCheck: "input-read")

    #expect(model.fixFailures["input-read"] == nil)
  }
}
