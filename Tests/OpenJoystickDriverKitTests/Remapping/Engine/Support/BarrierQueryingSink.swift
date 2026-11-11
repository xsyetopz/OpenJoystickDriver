import Foundation

@testable import OpenJoystickDriverKit

final class BarrierQueryingSink: RemappingSystemInputSink, @unchecked Sendable {
  private let lock = NSLock()
  private var recordedActions: [RemappingSystemInputAction] = []
  var barrier: RemappingEmissionBarrier?

  var actions: [RemappingSystemInputAction] { lock.withLock { recordedActions } }

  func send(_ action: RemappingSystemInputAction) {
    _ = barrier?.currentPermit()
    _ = barrier?.isTerminated
    lock.withLock { recordedActions.append(action) }
  }
}
