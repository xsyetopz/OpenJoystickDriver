import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
@MainActor
struct MainWindowAlertTests {
  @Test
  func profileDeleteConfirmationShowsAsSheet() throws {
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let window = try #require(controller.window)
    controller.navigation.requestArea(.profiles)
    window.layoutIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.2))

    controller.screens.profiles.activeAlert = .delete(UUID())
    RunLoop.main.run(until: .now.addingTimeInterval(0.5))

    #expect(window.attachedSheet != nil)
    window.attachedSheet.map { window.endSheet($0) }
  }
}
