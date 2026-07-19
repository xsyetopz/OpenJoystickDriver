import Testing

@testable import OpenJoystickDriver

struct UpdateChannelTests {
  @Test @MainActor func changingChannelClearsPreviousResult() {
    let model = AppModel()
    model.updateCheckState = .upToDate("v0.4.1")

    model.includePrereleaseUpdates.toggle()

    #expect(model.updateCheckState == .idle)
  }
}
