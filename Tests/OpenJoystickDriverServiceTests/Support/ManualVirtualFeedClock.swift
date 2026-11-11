import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// A ``VirtualFeedClock`` whose time moves only when a test calls ``advance(by:)``.
///
/// `advance` resumes every sleeper that is due before it returns, so a test can tell exactly
/// which waits it released. ``waitForSleepers(_:)`` suspends until the registry has parked that
/// many waits, which is how a test knows the registry has reacted to the last step.
final class ManualVirtualFeedClock: @unchecked Sendable {
  private struct Sleeper {
    let id: UInt64
    let due: TimeInterval
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var time: TimeInterval = 0
  private var nextID: UInt64 = 0
  private var sleepers: [Sleeper] = []
  private var cancelledEarly: Set<UInt64> = []
  private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

  var clock: VirtualFeedClock {
    VirtualFeedClock(now: { self.now }, sleep: { try await self.sleep(until: $0) })
  }

  var now: TimeInterval { lock.withLock { time } }

  var sleeperCount: Int { lock.withLock { sleepers.count } }

  /// Moves time forward and resumes every sleeper whose time has come.
  func advance(by seconds: TimeInterval) {
    let due = lock.withLock { () -> [Sleeper] in
      time += seconds
      let due = sleepers.filter { $0.due <= time }
      sleepers.removeAll { $0.due <= time }
      return due
    }
    for sleeper in due { sleeper.continuation.resume() }
  }

  /// Suspends until at least `count` waits are parked on the clock.
  func waitForSleepers(_ count: Int) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let ready = lock.withLock { () -> Bool in
        if sleepers.count >= count { return true }
        watchers.append((count, continuation))
        return false
      }
      if ready { continuation.resume() }
    }
  }

  /// Suspends until a wait that ends at exactly `due` is parked on the clock.
  ///
  /// Unlike ``waitForSleepers(_:)`` this names the wait, so a test cannot be released by a
  /// different wait that happens to be parked.
  func waitForSleeper(due: TimeInterval) async {
    await waitUntil("a wait ends at \(due)") {
      lock.withLock { sleepers.contains { $0.due == due } }
    }
  }

  private func sleep(until due: TimeInterval) async throws {
    let id = lock.withLock { () -> UInt64 in
      nextID += 1
      return nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        enum Arrival {
          case due, cancelled
          case parked([CheckedContinuation<Void, Never>])
        }
        let arrival = lock.withLock { () -> Arrival in
          if cancelledEarly.remove(id) != nil { return .cancelled }
          if due <= time { return .due }
          sleepers.append(Sleeper(id: id, due: due, continuation: continuation))
          let ready = watchers.filter { sleepers.count >= $0.count }
          watchers.removeAll { sleepers.count >= $0.count }
          return .parked(ready.map(\.continuation))
        }
        switch arrival {
        case .due: continuation.resume()
        case .cancelled: continuation.resume(throwing: CancellationError())
        case .parked(let ready): for watcher in ready { watcher.resume() }
        }
      }
    } onCancel: {
      let sleeper = lock.withLock { () -> Sleeper? in
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
          cancelledEarly.insert(id)
          return nil
        }
        return sleepers.remove(at: index)
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }
}
