import Foundation
import OpenJoystickDriverKit

/// The failure of a bounded step of a virtual output transition.
enum VirtualOutputTransitionError: Error, Sendable {
  /// A stage of the transition did not finish in time.
  case stageTimedOut
  /// The neutral feedback writes did not finish in time.
  case feedbackTimedOut
  /// Closing the candidate backend did not finish in time.
  case candidateCloseTimedOut
  /// Activating the backend did not finish in time.
  case activationTimedOut
}

/// Runs `operation` and returns its value, or throws `error` when `timeout` nanoseconds pass first.
///
/// The operation keeps running after a timeout; `onLateSuccess` receives its value then.
///
/// - Throws: `error` on timeout, `CancellationError` when the caller is cancelled first, or
///   the error of `operation`.
func withVirtualOutputTimeout<Value: Sendable>(
  _ timeout: UInt64,
  clock: VirtualOutputTransitionClock,
  error: VirtualOutputTransitionError,
  operation: @escaping @Sendable () async throws -> Value,
  onLateSuccess: @escaping @Sendable (Value) async -> Void = { _ in }
) async throws -> Value {
  guard timeout > 0 else { throw error }

  let stream = AsyncThrowingStream<Value, Error> { continuation in
    // Detached: on timeout the caller returns while the operation runs on to `onLateSuccess`.
    let operationTask = Task.detached {
      do {
        let result = try await operation()
        switch continuation.yield(result) {
        case .enqueued: continuation.finish()
        case .dropped, .terminated:
          await onLateSuccess(result)
          continuation.finish()
        @unknown default: continuation.finish()
        }
      } catch { continuation.finish(throwing: error) }
    }
    // Detached: a child task would make the caller wait for an operation that ignores cancellation.
    let timerTask = Task.detached {
      do {
        try await clock.sleep(timeout)
        continuation.finish(throwing: error)
      } catch {
        // Cancellation only stops the timer.
      }
    }
    continuation.onTermination = { _ in
      operationTask.cancel()
      timerTask.cancel()
    }
  }
  var iterator = stream.makeAsyncIterator()
  guard let result = try await iterator.next() else { throw CancellationError() }
  return result
}

/// A stop flag that the queued operations of a coordinator check.
final class VirtualOutputTransitionCancellation: Sendable {
  /// Whether the coordinator was stopped.
  private let stopped = Locked(false)

  /// Whether ``stop()`` was called.
  var isStopped: Bool { stopped.withLock { $0 } }
  /// Sets the flag.
  func stop() { stopped.withLock { $0 = true } }
}

/// Runs the operations of a virtual output transition one at a time, in the order they were queued.
actor VirtualOutputTransitionCoordinator {
  /// The last queued operation, which the next one waits for.
  private var tail: Task<Void, Never>?
  /// The flag that stops queued operations from starting.
  private let cancellation = VirtualOutputTransitionCancellation()
  /// Operations accepted since creation, counted when queued, before they start.
  private(set) var queuedOperationCount = 0

  /// Runs `operation` after every earlier operation; false when the coordinator stops first.
  func enqueue(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
    await enqueueResult(operation) ?? false
  }

  /// Runs `operation` after every earlier operation; nil when the coordinator stops first.
  func enqueueResult<Value: Sendable>(
    _ operation: @escaping @Sendable () async -> Value
  ) async -> Value? {
    guard !cancellation.isStopped else { return nil }
    queuedOperationCount += 1
    let previous = tail
    let cancellation = self.cancellation
    let next = Task<Value?, Never> {
      await previous?.value
      guard !Task.isCancelled, !cancellation.isStopped else { return nil }
      return await operation()
    }
    tail = Task {
      await withTaskCancellationHandler {
        _ = await next.value
      } onCancel: {
        next.cancel()
      }
    }
    return await next.value
  }

  /// Stops the queue: cancels the queued operations and refuses further ones.
  func stop() {
    cancellation.stop()
    tail?.cancel()
    tail = nil
  }
}

/// Admits the feedback of the virtual gamepad to the physical controllers, and quiesces it during a
/// transition.
final class VirtualOutputFeedbackGate: Sendable {
  /// Sends a feedback command to the physical controller.
  typealias SendFeedback = @Sendable (LogicalControllerID, ControllerOutputCommand) async -> Void

  /// The admission state, guarded by a lock.
  private struct Admission {
    /// Whether feedback is accepted.
    var accepting = true
    /// Advances each time the whole gate closes or reopens, so earlier feedback is dropped.
    var generation: UInt64 = 0
    /// The cancel action of each feedback in flight, with its controller.
    var cancellationHandlers:
      [UUID: (identifier: LogicalControllerID, cancel: @Sendable () -> Void)] =
        [:]
    /// Controllers whose own feedback is quiesced while the rest keep flowing.
    var quiescedControllers: [LogicalControllerID: Int] = [:]
    /// Advances each time one controller is quiesced, so its earlier feedback is dropped.
    var controllerGenerations: [LogicalControllerID: UInt64] = [:]

    /// Whether feedback admitted under `generation` for `identifier` may still be sent.
    func isCurrent(_ identifier: LogicalControllerID, generation: Generation) -> Bool {
      accepting && self.generation == generation.gate && quiescedControllers[identifier] == nil
        && controllerGenerations[identifier, default: 0] == generation.controller
    }
  }

  /// The gate and controller generations that a feedback was admitted under.
  private struct Generation {
    /// The gate generation.
    var gate: UInt64
    /// The controller generation.
    var controller: UInt64
  }

  /// Sends feedback to the physical controller.
  private let sendFeedback: SendFeedback
  /// The admission state.
  private let admission = Locked(Admission())

  /// Creates a gate that sends the physical feedback of a command to a connected controller of
  /// `deviceManager`.
  init(deviceManager: DeviceManager) {
    sendFeedback = { identifier, command in
      guard let command = Self.physicalFeedback(for: command) else { return }
      _ = await deviceManager.sendControllerOutput(command, toConnected: identifier)
    }
  }

  /// Creates a gate that sends feedback with `sendFeedback`.
  init(sendFeedback: @escaping SendFeedback) { self.sendFeedback = sendFeedback }

  /// The physical command for consumer feedback: a bounded set-rumble, with its main motors
  /// mirrored onto the Steam trackpad haptics, or stop-rumble.
  ///
  /// Other consumer commands, such as a DualSense lightbar, and held rumble do not reach the
  /// physical controller.
  static func physicalFeedback(for command: ControllerOutputCommand) -> ControllerOutputCommand? {
    switch command {
    case .setRumble(let intensities, .milliseconds(let durationMs)):
      .setRumble(intensities.mirroringMainOntoHaptics(), duration: .milliseconds(durationMs))
    case .stopRumble: .stopRumble
    default: nil
    }
  }

  /// Sends `command` for `identifier` unless the gate or the controller is quiesced.
  func submit(identifier: LogicalControllerID, command: ControllerOutputCommand) {
    let token = UUID()
    let currentGeneration = admission.withLock { admission -> Generation? in
      guard admission.accepting, admission.quiescedControllers[identifier] == nil else {
        return nil
      }
      return Generation(
        gate: admission.generation,
        controller: admission.controllerGenerations[identifier, default: 0]
      )
    }
    guard let currentGeneration else { return }
    let task = Task { [weak self] in
      guard let self, self.isCurrent(identifier, generation: currentGeneration) else {
        self?.finish(token)
        return
      }
      await self.sendFeedback(identifier, command)
      self.finish(token)
    }
    let shouldCancel = admission.withLock { admission -> Bool in
      admission.cancellationHandlers[token] = (identifier, { task.cancel() })
      return !admission.isCurrent(identifier, generation: currentGeneration)
    }
    if shouldCancel { task.cancel() }
  }

  /// Closes feedback admission, cancels in-flight feedback, and queues one neutral write per
  /// controller.
  ///
  /// With `resumeWhenComplete` only `identifiers` are quiesced, and admission for each reopens
  /// afterwards, so other controllers' feedback is untouched; otherwise the whole gate closes and
  /// stays closed until `resume()`.
  func quiesceAndNeutralize(
    _ identifiers: [LogicalControllerID],
    timeout: UInt64 = VirtualOutputTransitionTimeouts.standard.feedbackNanoseconds,
    clock: VirtualOutputTransitionClock = .system,
    resumeWhenComplete: Bool = false
  ) async -> Bool {
    let cancellations = admission.withLock { admission in
      var cancellations: [@Sendable () -> Void] = []
      if resumeWhenComplete {
        for identifier in identifiers {
          admission.quiescedControllers[identifier, default: 0] += 1
          admission.controllerGenerations[identifier, default: 0] &+= 1
        }
        for (token, handler) in admission.cancellationHandlers
        where identifiers.contains(handler.identifier) {
          cancellations.append(handler.cancel)
          admission.cancellationHandlers.removeValue(forKey: token)
        }
      } else {
        admission.accepting = false
        admission.generation &+= 1
        cancellations = admission.cancellationHandlers.values.map(\.cancel)
        admission.cancellationHandlers.removeAll()
      }
      return cancellations
    }
    for cancel in cancellations { cancel() }

    // A canceled HID/USB write is not required to cooperate with Swift task cancellation. Once
    // admission advances to a new generation, quarantine those writes instead of waiting for
    // their completion. Queue one neutral write per controller behind any late operation and
    // bound only how long this transition waits for the neutralization attempt.
    do {
      try await withVirtualOutputTimeout(timeout, clock: clock, error: .feedbackTimedOut) {
        await withTaskGroup(of: Void.self) { group in
          for identifier in identifiers {
            group.addTask { await self.sendFeedback(identifier, .stopRumble) }
          }
          await group.waitForAll()
        }
      }
    } catch {
      // The queued neutral writes remain owned by their transport workers. Their late completion
      // cannot re-open feedback admission or mutate the virtual output publication.
    }
    if resumeWhenComplete {
      admission.withLock { admission in
        for identifier in identifiers {
          admission.controllerGenerations[identifier, default: 0] &+= 1
          let remaining = admission.quiescedControllers[identifier, default: 1] - 1
          admission.quiescedControllers[identifier] = remaining > 0 ? remaining : nil
        }
      }
    }
    return true
  }

  /// Reopens feedback admission after
  /// ``quiesceAndNeutralize(_:timeout:clock:resumeWhenComplete:)``.
  func resume() {
    admission.withLock { admission in
      admission.generation &+= 1
      admission.accepting = true
    }
  }

  /// Whether feedback admitted under `generation` may still be sent.
  private func isCurrent(_ identifier: LogicalControllerID, generation: Generation) -> Bool {
    admission.withLock { $0.isCurrent(identifier, generation: generation) }
  }

  /// Forgets the in-flight feedback `token`.
  private func finish(_ token: UUID) {
    _ = admission.withLock { $0.cancellationHandlers.removeValue(forKey: token) }
  }
}

/// Closes a virtual output backend once, however many callers ask.
final class VirtualOutputBackendCloseSlot: Sendable {
  /// The backend to close.
  let backend: any VirtualOutputDispatching
  /// The close task, created by the first caller.
  private let closeTask = Locked<Task<Void, Never>?>(nil)

  /// Creates a slot for `backend`.
  init(_ backend: any VirtualOutputDispatching) { self.backend = backend }

  /// Closes the backend and returns true, or returns false when `timeout` nanoseconds pass first.
  func close(timeout: UInt64, clock: VirtualOutputTransitionClock) async -> Bool {
    let backend = self.backend
    let task = closeTask.withLock { closeTask -> Task<Void, Never> in
      if let closeTask { return closeTask }
      // Detached: the close outlives a timed-out caller, and later callers await the same task.
      let task = Task.detached { await backend.close() }
      closeTask = task
      return task
    }
    do {
      try await withVirtualOutputTimeout(timeout, clock: clock, error: .candidateCloseTimedOut) {
        await task.value
      }
      return true
    } catch { return false }
  }
}
