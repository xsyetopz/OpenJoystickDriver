import AppKit
import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.holdingControllerNavigationSession)
@MainActor
struct MainWindowAlertTests {
  @Test
  func profileDeleteConfirmationShowsAsSheet() async throws {
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let window = try #require(controller.window)
    controller.navigation.requestArea(.profiles)
    window.layoutIfNeeded()

    controller.screens.profiles.activeAlert = .delete(UUID())
    await waitUntil("the delete confirmation attaches as a sheet") { window.attachedSheet != nil }

    #expect(window.attachedSheet != nil)
    window.attachedSheet.map { window.endSheet($0) }
  }
}
