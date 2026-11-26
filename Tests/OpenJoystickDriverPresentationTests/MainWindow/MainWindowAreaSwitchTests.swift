import AppKit
import OpenJoystickDriverTestSupport
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
  func detailShowsAreaChosenAfterAnother() async throws {
    // Arrange
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let window = try #require(controller.window)
    let detail = controller.splitViewController.splitViewItems[2].viewController.view
    controller.navigation.requestArea(.activity)
    window.layoutIfNeeded()
    #expect(spinners(in: detail) == 0)

    // Act
    controller.navigation.requestArea(.controllers)
    await waitUntil("Controllers shows its loading spinner in the detail", deadline: 10) {
      spinners(in: detail) > 0
    }

    // Assert
    #expect(spinners(in: detail) > 0)
  }
}
