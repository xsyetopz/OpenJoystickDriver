import AppKit
import Testing

/// Keeps AppKit's game controller navigation session alive for the rest of the test process.
///
/// Each window AppKit loads from a nib, such as an `NSAlert` panel or a SwiftUI alert sheet, gets
/// a focus controller that resumes one shared navigation session, and releasing the last such
/// window ends the session. With a controller connected, the session activates its GameController
/// device session asynchronously, which can take tens of milliseconds while the whole suite runs.
/// A test that creates and releases an alert faster than that makes AppKit invalidate the device
/// session before activation finishes, and GameController raises
/// "A session may not be invalidated prior to activation", which aborts the test process. The app
/// releases an alert only after a person answers it, long after activation.
///
/// One alert window, held from the first test that needs it, keeps the session resumed, so no test
/// ends it.
struct HoldingControllerNavigationSession: SuiteTrait, TestScoping {
  /// The alert whose window keeps the session resumed.
  @MainActor
  private static var holder: NSAlert?

  var isRecursive: Bool { false }

  func provideScope(
    for _: Test,
    testCase _: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    await Self.hold()
    try await function()
  }

  /// Creates the held alert and loads its window, once.
  @MainActor
  private static func hold() {
    guard holder == nil else { return }
    let alert = NSAlert()
    _ = alert.window
    holder = alert
  }
}

extension Trait where Self == HoldingControllerNavigationSession {
  /// Keeps AppKit's game controller navigation session alive while the suite's alerts come and go.
  static var holdingControllerNavigationSession: Self { Self() }
}
