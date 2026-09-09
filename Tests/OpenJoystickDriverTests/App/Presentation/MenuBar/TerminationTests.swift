import AppKit
import Testing

@testable import OpenJoystickDriver

@Suite @MainActor struct MenuBarTerminationTests {
  @Test func repeatedQuitWaitsForTeardownAndRepliesOnce() async {
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
}
