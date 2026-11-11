import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

final class AutomaticBackendProbe: VirtualOutputDispatching, ControllerLifecycleListener,
  @unchecked Sendable
{
  struct ActivationFailure: Error, Sendable {}

  let failsActivation: Bool
  private(set) var closed = false
  private(set) var activations: [[LogicalControllerID]] = []
  var suppressOutput = false
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }

  init(failsActivation: Bool = false) { self.failsActivation = failsActivation }

  func activate(for identifiers: [LogicalControllerID]) throws {
    activations.append(identifiers)
    if failsActivation { throw ActivationFailure() }
  }

  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {
  }
  func activateOutput(for _: LogicalControllerID) {}

  func controllerDidStop(_: LogicalControllerID) {}

  func close() { closed = true }
}

final class AutomaticBackendBox: @unchecked Sendable { var created: [AutomaticBackendProbe] = [] }

final class AutomaticProfileLog: @unchecked Sendable {
  private let lock = NSLock()
  private var built: [VirtualHIDProfileID] = []

  func record(_ profile: VirtualHIDProfileID) -> AutomaticBackendProbe {
    lock.withLock { built.append(profile) }
    return AutomaticBackendProbe()
  }

  func profiles() -> [VirtualHIDProfileID] { lock.withLock { built } }
}

final class ConcurrentBackendProbe: VirtualOutputDispatching, @unchecked Sendable {
  private let lock = NSLock()
  private var dispatchCount = 0
  private var closeCount = 0
  var suppressOutput = false
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }

  func activate(for _: [LogicalControllerID]) {}

  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {
    lock.withLock { dispatchCount += 1 }
  }

  func activateOutput(for _: LogicalControllerID) { lock.withLock { dispatchCount += 1 } }

  func controllerDidStop(_: LogicalControllerID) {}

  func close() { lock.withLock { closeCount += 1 } }

  func counts() -> (Int, Int) { lock.withLock { (dispatchCount, closeCount) } }
}

final class ConcurrentFactoryProbe: @unchecked Sendable {
  private let lock = NSLock()
  private let enteredSignal = DispatchSemaphore(value: 0)
  private(set) var created = 0
  private(set) var entered = 0
  private(set) var backends: [ConcurrentBackendProbe] = []
  var gate: DispatchSemaphore?

  func make() -> ConcurrentBackendProbe {
    lock.withLock { entered += 1 }
    enteredSignal.signal()
    gate?.wait()
    return lock.withLock {
      created += 1
      let backend = ConcurrentBackendProbe()
      backends.append(backend)
      return backend
    }
  }

  func snapshot() -> (Int, Int, [ConcurrentBackendProbe]) {
    lock.withLock { (created, entered, backends) }
  }

  func waitForEntered() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        self.enteredSignal.wait()
        continuation.resume()
      }
    }
  }
}
