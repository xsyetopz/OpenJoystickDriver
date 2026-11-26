import AppKit
import Testing

@testable import OpenJoystickDriverMacOSPlatform

struct HIDRunLoopModeTests {
  /// Controller input keeps arriving while a menu is open.
  ///
  /// An open menu runs the main run loop in the event-tracking mode. A source scheduled in the
  /// stream's mode must still fire there, or each controller reads as stale and posts a
  /// "needs attention" notification on every menu click.
  @Test
  @MainActor
  func streamModeRunsWhileAMenuTracksEvents() {
    // Arrange
    var fired = false
    let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 0, 0, 0) { _ in
      fired = true
    }
    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, HIDDeviceStream.runLoopMode)
    defer { CFRunLoopTimerInvalidate(timer) }
    let eventTracking = CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString)
    // A running NSApplication adds the event-tracking mode to the common modes; a test has none.
    CFRunLoopAddCommonMode(CFRunLoopGetMain(), eventTracking)

    // Act
    // Other main-queue work also runs in common modes, so one pass can end on its source first.
    let limit = ProcessInfo.processInfo.systemUptime + 2
    while !fired, ProcessInfo.processInfo.systemUptime < limit {
      _ = CFRunLoopRunInMode(eventTracking, 0.1, true)
    }

    // Assert
    #expect(fired)
  }
}
