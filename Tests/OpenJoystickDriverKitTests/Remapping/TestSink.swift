import Foundation

@testable import OpenJoystickDriverKit

final class RemappingTestSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private var recordedActions: [RemappingSystemInputAction] = []
  private var sendCount = 0
  private var failingCalls: Set<Int>

  init(failingCalls: Set<Int> = []) { self.failingCalls = failingCalls }

  func send(_ action: RemappingSystemInputAction) throws {
    lock.lock()
    defer { lock.unlock() }
    sendCount += 1
    if failingCalls.remove(sendCount) != nil { throw TestSinkError.rejected }
    recordedActions.append(action)
  }

  func actions() -> [RemappingSystemInputAction] {
    lock.lock()
    defer { lock.unlock() }
    return recordedActions
  }

  func removeActions() -> [RemappingSystemInputAction] {
    lock.lock()
    defer { lock.unlock() }
    let actions = recordedActions
    recordedActions.removeAll()
    return actions
  }

  private enum TestSinkError: Error { case rejected }
}
