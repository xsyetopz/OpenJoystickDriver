import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

actor InstallationGate {
  private var entered = false
  private var cancelled = false
  private var released = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspend() async {
    entered = true
    for waiter in entryWaiters { waiter.resume() }
    entryWaiters.removeAll()
    await withTaskCancellationHandler {
      if !released { await withCheckedContinuation { waiters.append($0) } }
    } onCancel: {
      Task { await self.markCancelled() }
    }
  }

  func waitForEntry() async {
    if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
  }

  func waitForCancellation() async {
    if !cancelled { await withCheckedContinuation { cancellationWaiters.append($0) } }
  }

  private func markCancelled() {
    cancelled = true
    for waiter in cancellationWaiters { waiter.resume() }
    cancellationWaiters.removeAll()
  }

  func release() {
    released = true
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }
}

final class AutomaticBuildCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }
}

final class InstallationBackend: VirtualOutputDispatching, @unchecked Sendable {
  enum Stage: Sendable { case none, activation, suppression, retirement }
  let stage: Stage
  let gate: InstallationGate
  let failsActivation: Bool
  private let lock = NSLock()
  private var suppressed = false
  private var closes = 0
  private var activations = 0
  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }

  init(stage: Stage, gate: InstallationGate, failsActivation: Bool = false) {
    self.stage = stage
    self.gate = gate
    self.failsActivation = failsActivation
  }

  func activate(for _: [LogicalControllerID]) async throws {
    lock.withLock { activations += 1 }
    if stage == .activation { await gate.suspend() }
    if failsActivation { throw UserSpaceOutputDispatcher.CreationError.createFailed }
  }

  func setOutputSuppressed(_ value: Bool) async {
    if stage == .suppression { await gate.suspend() }
    suppressOutput = value
  }

  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {
  }
  func activateOutput(for _: LogicalControllerID) {}

  func close() async {
    if stage == .retirement { await gate.suspend() }
    lock.withLock { closes += 1 }
  }

  func counts() -> (activations: Int, closes: Int) { lock.withLock { (activations, closes) } }
}
