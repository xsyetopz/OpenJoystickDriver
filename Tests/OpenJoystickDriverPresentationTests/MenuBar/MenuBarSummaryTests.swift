import Testing

@testable import OpenJoystickDriverPresentation

struct MenuBarSummaryTests {
  @Test
  @MainActor
  func menuBarPublishesASemanticSignal() {
    let runtime = RuntimeViewModel(gateway: GatewayStub())
    let menuBar = MenuBarViewModel(runtime: runtime)

    #expect(menuBar.summarySemanticState == .loading)
  }
}
