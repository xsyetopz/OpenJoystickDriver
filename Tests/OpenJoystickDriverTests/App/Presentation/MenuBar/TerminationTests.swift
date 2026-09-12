import AppKit
import Testing

@testable import OpenJoystickDriver

@Suite
@MainActor
struct MenuBarTerminationTests {
  @Test
  func repeatedQuitWaitsForTeardownAndRepliesOnce() async {
    let termination = MenuBarTermination()
    let entered = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()
    let replied = AsyncStream<Void>.makeStream()
    var stops = 0
    var replies = 0
    let first = termination.request {
      stops += 1
      entered.continuation.yield(())
      for await _ in release.stream { break }
    } reply: {
      replies += 1
      replied.continuation.yield(())
    }
    #expect(first == .terminateLater)
    for await _ in entered.stream { break }
    let repeated = termination.request {
      Issue.record("Repeated quit started another teardown")
    } reply: {
      Issue.record("Repeated quit registered another reply")
    }
    #expect(repeated == .terminateLater)
    #expect(stops == 1)
    #expect(replies == 0)
    release.continuation.yield(())
    for await _ in replied.stream { break }
    #expect(replies == 1)
    let completed = termination.request {
      Issue.record("Completed quit restarted teardown")
    } reply: {
      Issue.record("Completed quit replied again")
    }
    #expect(completed == .terminateNow)
  }

  @Test
  func explicitRestartRelaunchesOnlyAfterTeardown() async {
    let termination = MenuBarTermination()
    var events: [String] = []
    termination.requestRelaunch { events.append("terminate") }
    termination.requestRelaunch { Issue.record("Duplicate restart requested termination again") }

    let replied = AsyncStream<Void>.makeStream()
    let result = termination.request {
      events.append("stop")
    } relaunch: {
      events.append("relaunch")
    } reply: {
      events.append("reply")
      replied.continuation.yield(())
    }

    #expect(result == .terminateLater)
    for await _ in replied.stream { break }
    #expect(events == ["terminate", "stop", "relaunch", "reply"])
  }

  @Test
  func systemOwnedQuitAndReopenDoesNotScheduleAnotherRelaunch() async {
    let termination = MenuBarTermination()
    let replied = AsyncStream<Void>.makeStream()
    var relaunches = 0

    _ = termination.request {
    } relaunch: {
      relaunches += 1
    } reply: {
      replied.continuation.yield(())
    }

    for await _ in replied.stream { break }
    #expect(relaunches == 0)
  }
}
