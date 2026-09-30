import Foundation
import OpenJoystickDriverKit

enum VirtualOutputTransitionError: Error, Sendable {
  case stageTimedOut
  case feedbackTimedOut
  case candidateCloseTimedOut
  case activationTimedOut
}

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

final class VirtualOutputTransitionCancellation: Sendable {
  private let stopped = Locked(false)

  var isStopped: Bool { stopped.withLock { $0 } }
  func stop() { stopped.withLock { $0 = true } }
}

actor VirtualOutputTransitionCoordinator {
  private var tail: Task<Void, Never>?
  private let cancellation = VirtualOutputTransitionCancellation()

  func enqueue(_ operation: @escaping @Sendable () async -> Bool) async -> Bool {
    await enqueueResult(operation) ?? false
  }

  /// Runs `operation` after every earlier operation; nil when the coordinator stops first.
  func enqueueResult<Value: Sendable>(
    _ operation: @escaping @Sendable () async -> Value
  ) async -> Value? {
    guard !cancellation.isStopped else { return nil }
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

  func stop() {
    cancellation.stop()
    tail?.cancel()
    tail = nil
  }
}

final class VirtualOutputFeedbackGate: Sendable {
  typealias SendFeedback = @Sendable (DeviceIdentifier, ControllerOutputCommand) async -> Void

  private struct Admission {
    var accepting = true
    var generation: UInt64 = 0
    var cancellationHandlers: [UUID: (identifier: DeviceIdentifier, cancel: @Sendable () -> Void)] =
      [:]
    /// Controllers whose own feedback is quiesced while the rest keep flowing.
    var quiescedControllers: [DeviceIdentifier: Int] = [:]
    var controllerGenerations: [DeviceIdentifier: UInt64] = [:]

    func isCurrent(_ identifier: DeviceIdentifier, generation: Generation) -> Bool {
      accepting && self.generation == generation.gate && quiescedControllers[identifier] == nil
        && controllerGenerations[identifier, default: 0] == generation.controller
    }
  }

  private struct Generation {
    var gate: UInt64
    var controller: UInt64
  }

  private let sendFeedback: SendFeedback
  private let admission = Locked(Admission())

  init(deviceManager: DeviceManager) {
    sendFeedback = { identifier, command in
      guard let command = Self.physicalFeedback(for: command) else { return }
      // The exact runtime identifier: the model alone is ambiguous when two controllers match.
      _ = await deviceManager.sendControllerOutput(
        command,
        for: identifier,
        runtimeIdentifier: identifier.runtimeIdentifier
      )
    }
  }

  init(sendFeedback: @escaping SendFeedback) { self.sendFeedback = sendFeedback }

  /// The physical command for consumer feedback: a bounded set-rumble, with its main motors
  /// mirrored onto the Steam trackpad haptics, or stop-rumble. Other consumer commands, such as a
  /// DualSense lightbar, and held rumble do not reach the physical controller.
  static func physicalFeedback(for command: ControllerOutputCommand) -> ControllerOutputCommand? {
    switch command {
    case .setRumble(let intensities, .milliseconds(let durationMs)):
      .setRumble(intensities.mirroringMainOntoHaptics(), duration: .milliseconds(durationMs))
    case .stopRumble: .stopRumble
    default: nil
    }
  }

  func submit(identifier: DeviceIdentifier, command: ControllerOutputCommand) {
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
  /// controller. With `resumeWhenComplete` only `identifiers` are quiesced, and admission for
  /// each reopens afterwards, so other controllers' feedback is untouched; otherwise the whole
  /// gate closes and stays closed until `resume()`.
  func quiesceAndNeutralize(
    _ identifiers: [DeviceIdentifier],
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
    cancellations.forEach { $0() }

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

  func resume() {
    admission.withLock { admission in
      admission.generation &+= 1
      admission.accepting = true
    }
  }

  private func isCurrent(_ identifier: DeviceIdentifier, generation: Generation) -> Bool {
    admission.withLock { $0.isCurrent(identifier, generation: generation) }
  }

  private func finish(_ token: UUID) {
    _ = admission.withLock { $0.cancellationHandlers.removeValue(forKey: token) }
  }
}

final class VirtualOutputBackendCloseSlot: Sendable {
  let backend: any VirtualOutputDispatching
  private let closeTask = Locked<Task<Void, Never>?>(nil)

  init(_ backend: any VirtualOutputDispatching) { self.backend = backend }

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
