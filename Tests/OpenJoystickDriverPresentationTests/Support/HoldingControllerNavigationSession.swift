import Testing

@testable import OpenJoystickDriverPresentation

/// Holds AppKit's game controller navigation session for the rest of the test process, as the app
/// does from launch through `ControllerNavigationSession.hold()`.
///
/// The suites create and release alert windows directly, without the app's `run()`. Without the
/// held window, releasing one before the session's GameController activation completes aborts the
/// test process with "A session may not be invalidated prior to activation".
struct HoldingControllerNavigationSession: SuiteTrait, TestScoping {
  var isRecursive: Bool { false }

  func provideScope(
    for _: Test,
    testCase _: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    await ControllerNavigationSession.hold()
    try await function()
  }
}

extension Trait where Self == HoldingControllerNavigationSession {
  /// Holds the navigation session while the suite's alerts come and go.
  static var holdingControllerNavigationSession: Self { Self() }
}
