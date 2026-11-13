import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct LockedTests {
  private struct Failure: Error, Equatable {}

  @Test
  func concurrentIncrementsAreNotLost() {
    let counter = Locked(0)
    DispatchQueue.concurrentPerform(iterations: 1_000) { _ in counter.withLock { $0 += 1 } }
    #expect(counter.withLock { $0 } == 1_000)
  }

  @Test
  func withLockReturnsBodyResult() {
    let names = Locked(["a"])
    let count = names.withLock { names -> Int in
      names.append("b")
      return names.count
    }
    #expect(count == 2)
    #expect(names.withLock { $0 } == ["a", "b"])
  }

  @Test
  func withLockRethrowsAndKeepsEarlierMutations() {
    let value = Locked(1)
    #expect(throws: Failure()) {
      try value.withLock { value in
        value = 2
        throw Failure()
      }
    }
    #expect(value.withLock { $0 } == 2)
    value.withLock { $0 = 3 }
    #expect(value.withLock { $0 } == 3)
  }
}
