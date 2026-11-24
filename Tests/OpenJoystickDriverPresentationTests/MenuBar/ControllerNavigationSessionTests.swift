import AppKit
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerNavigationSessionTests {
  @Test
  func holdKeepsOneLoadedAlertWindowAcrossCalls() throws {
    // Arrange
    ControllerNavigationSession.hold()
    let first = try #require(ControllerNavigationSession.holder)

    // Act
    ControllerNavigationSession.hold()

    // Assert
    #expect(ControllerNavigationSession.holder === first)
    #expect(first.window.contentView != nil)
  }
}
