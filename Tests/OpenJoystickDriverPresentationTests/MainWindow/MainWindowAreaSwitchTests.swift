import AppKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
@MainActor
struct MainWindowAreaSwitchTests {
  private func buttons(in view: NSView) -> Int {
    view.subviews.reduce(0) { count, subview in
      count + (subview is NSButton ? 1 : 0) + buttons(in: subview)
    }
  }

  /// At Simple, Activity shows a "Show All Controls" button and Controllers with no controller
  /// shows only text, so a button left in the detail is Activity drawn under Controllers.
  @Test
  func detailShowsAreaChosenAfterAnother() throws {
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let detail = controller.splitViewController.splitViewItems[2].viewController.view
    controller.navigation.requestArea(.activity)
    RunLoop.main.run(until: .now.addingTimeInterval(0.3))
    #expect(buttons(in: detail) > 0)

    controller.navigation.requestArea(.controllers)
    RunLoop.main.run(until: .now.addingTimeInterval(0.3))
    #expect(buttons(in: detail) == 0)
  }
}
