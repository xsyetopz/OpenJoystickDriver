import AppKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
@MainActor
struct MainWindowAreaSwitchTests {
  private func spinners(in view: NSView) -> Int {
    view.subviews.reduce(0) { count, subview in
      count + (subview is NSProgressIndicator ? 1 : 0) + spinners(in: subview)
    }
  }

  /// Controllers replaces Activity in the detail after a switch.
  ///
  /// The stub service never answers, so Controllers shows its loading spinner; Activity at Simple
  /// shows only its placeholder. Activity left in the detail after a switch has no spinner.
  @Test
  func detailShowsAreaChosenAfterAnother() throws {
    // Arrange
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let detail = controller.splitViewController.splitViewItems[2].viewController.view
    controller.navigation.requestArea(.activity)
    RunLoop.main.run(until: .now.addingTimeInterval(0.3))
    #expect(spinners(in: detail) == 0)

    // Act
    controller.navigation.requestArea(.controllers)
    RunLoop.main.run(until: .now.addingTimeInterval(0.3))

    // Assert
    #expect(spinners(in: detail) > 0)
  }
}
