import Foundation
import OpenJoystickDriverKit

/// Admits the feedback of the virtual gamepad to the physical controllers, and quiesces it during a
/// transition.
///
/// Each controller's feedback is sent one command at a time, in arrival order, so a stop never
/// overtakes the set before it (#72).
final class VirtualOutputFeedbackGate: Sendable {
  /// Sends a feedback command to the physical controller.
  typealias SendFeedback = @Sendable (LogicalControllerID, ControllerOutputCommand) async -> Void

  /// The longest a stop waits after its set was sent, so that rumble a busy write delayed still
  /// lasts as long as the host held it.
  ///
  /// The bound covers the short cues a write delay can swallow; a longer rumble is felt anyway.
  static let longestRestoredPulse: Duration = .milliseconds(250)

  /// The task that sends one controller's queued feedback.
  private struct Sender {
    /// Tells this sender apart from a later one for the same controller.
    var token: UUID
    /// Cancels the task; nil until the task exists.
    var cancel: (@Sendable () -> Void)?
  }

  /// The admission state, guarded by a lock.
  private struct Admission {
    /// Whether feedback is accepted.
    var accepting = true
    /// Advances each time the whole gate closes or reopens, so earlier feedback is dropped.
    var generation: UInt64 = 0
    /// The sender of each controller with queued or in-flight feedback.
    var senders: [LogicalControllerID: Sender] = [:]
    /// The feedback each controller's sender has yet to send.
    var queues: [LogicalControllerID: VirtualOutputFeedbackQueue] = [:]
    /// Controllers whose own feedback is quiesced while the rest keep flowing.
    var quiescedControllers: [LogicalControllerID: Int] = [:]
    /// Advances each time one controller is quiesced, so its earlier feedback is dropped.
    var controllerGenerations: [LogicalControllerID: UInt64] = [:]

    /// Whether feedback admitted under `generation` for `identifier` may still be sent.
    func isCurrent(
      _ identifier: LogicalControllerID,
      generation: VirtualOutputFeedbackGeneration
    ) -> Bool {
      accepting && self.generation == generation.gate && quiescedControllers[identifier] == nil
        && controllerGenerations[identifier, default: 0] == generation.controller
    }

    /// Drops the queue and sender of `identifier` and returns the sender's cancel action.
    mutating func removeSender(for identifier: LogicalControllerID) -> (@Sendable () -> Void)? {
      queues[identifier] = nil
      return senders.removeValue(forKey: identifier)?.cancel
    }
  }

  /// Sends feedback to the physical controller.
  private let sendFeedback: SendFeedback
  /// The admission state.
  private let admission = Locked(Admission())

  /// Creates a gate that sends the physical feedback of a command to a connected controller of
  /// `deviceManager`.
  init(deviceManager: DeviceManager) {
    sendFeedback = { identifier, command in
      guard let physical = Self.physicalFeedback(for: command) else { return }
      _ = await deviceManager.sendControllerOutput(physical, toConnected: identifier)
    }
  }

  /// Creates a gate that sends feedback with `sendFeedback`.
  init(sendFeedback: @escaping SendFeedback) { self.sendFeedback = sendFeedback }

  /// The physical command for consumer feedback: a bounded set-rumble, with its main motors
  /// mirrored onto the Steam trackpad haptics, or stop-rumble.
  ///
  /// Held rumble, which a DualShock 4 output report requests, runs until the next command and at
  /// most `maxRumbleDurationMs`, so a game that quits mid-rumble cannot leave the motors running.
  /// Other consumer commands, such as a DualShock 4 lightbar color, do not reach the physical
  /// controller.
  static func physicalFeedback(for command: ControllerOutputCommand) -> ControllerOutputCommand? {
    switch command {
    case .setRumble(let intensities, let duration):
      .setRumble(intensities.mirroringMainOntoHaptics(), duration: bounded(duration))
    case .stopRumble: .stopRumble
    default: nil
    }
  }

  /// `duration` with held rumble replaced by the longest bounded duration.
  private static func bounded(_ duration: RumbleDuration) -> RumbleDuration {
    switch duration {
    case .milliseconds: duration
    case .held: .milliseconds(maxRumbleDurationMs)
    }
  }

  /// Queues `command` for `identifier` unless the gate or the controller is quiesced.
  func submit(identifier: LogicalControllerID, command: ControllerOutputCommand) {
    let arrival = ContinuousClock.now
    let token = UUID()
    let startsSender = admission.withLock { admission -> Bool in
      guard admission.accepting, admission.quiescedControllers[identifier] == nil else {
        return false
      }
      let generation = VirtualOutputFeedbackGeneration(
        gate: admission.generation,
        controller: admission.controllerGenerations[identifier, default: 0]
      )
      admission.queues[identifier, default: VirtualOutputFeedbackQueue()]
        .append(.init(command: command, generation: generation, arrival: arrival))
      guard admission.senders[identifier] == nil else { return false }
      admission.senders[identifier] = Sender(token: token)
      return true
    }
    guard startsSender else { return }
    let task = Task { [weak self] in await self?.drain(identifier, token: token) }
    let cancelNow = admission.withLock { admission -> Bool in
      guard admission.senders[identifier]?.token == token else { return true }
      admission.senders[identifier]?.cancel = { task.cancel() }
      return false
    }
    // The controller was quiesced before the task existed.
    if cancelNow { task.cancel() }
  }

  /// Sends the queued feedback of `identifier` until the queue is empty or the sender is cancelled.
  private func drain(_ identifier: LogicalControllerID, token: UUID) async {
    // The arrival and send start of the set-rumble last sent, while no stop has followed it.
    var lastSet: (arrival: ContinuousClock.Instant, sent: ContinuousClock.Instant)?
    while !Task.isCancelled, let entry = next(for: identifier, token: token) {
      guard isCurrent(identifier, generation: entry.generation) else { continue }
      if entry.command == .stopRumble, let lastSet {
        let held = min(entry.arrival - lastSet.arrival, Self.longestRestoredPulse)
        try? await Task.sleep(until: lastSet.sent + held, clock: .continuous)
        guard !Task.isCancelled, isCurrent(identifier, generation: entry.generation) else {
          continue
        }
      }
      let sent = ContinuousClock.now
      await sendFeedback(identifier, entry.command)
      switch entry.command {
      case .setRumble: lastSet = (entry.arrival, sent)
      case .stopRumble: lastSet = nil
      default: break
      }
    }
    admission.withLock { admission in
      guard admission.senders[identifier]?.token == token else { return }
      _ = admission.removeSender(for: identifier)
    }
  }

  /// The next queued command of `identifier`, or nil when the queue is empty or another sender
  /// replaced `token`; an empty queue retires the sender.
  private func next(
    for identifier: LogicalControllerID,
    token: UUID
  ) -> VirtualOutputFeedbackQueue.Entry? {
    admission.withLock { admission in
      guard admission.senders[identifier]?.token == token else { return nil }
      if let entry = admission.queues[identifier]?.popFirst() { return entry }
      _ = admission.removeSender(for: identifier)
      return nil
    }
  }

  /// Closes feedback admission, cancels queued and in-flight feedback, and queues one at-rest write
  /// per controller.
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
      let quiesced: [LogicalControllerID]
      if resumeWhenComplete {
        for identifier in identifiers {
          admission.quiescedControllers[identifier, default: 0] += 1
          admission.controllerGenerations[identifier, default: 0] &+= 1
        }
        quiesced = identifiers
      } else {
        admission.accepting = false
        admission.generation &+= 1
        quiesced = Array(admission.senders.keys)
      }
      return quiesced.compactMap { admission.removeSender(for: $0) }
    }
    for cancel in cancellations { cancel() }

    // A canceled HID/USB write is not required to cooperate with Swift task cancellation. Once
    // admission advances to a new generation, quarantine those writes instead of waiting for
    // their completion. Queue one at-rest write per controller behind any late operation and
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
      // The queued at-rest writes remain owned by their transport workers. Their late completion
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
  private func isCurrent(
    _ identifier: LogicalControllerID,
    generation: VirtualOutputFeedbackGeneration
  ) -> Bool {
    admission.withLock { $0.isCurrent(identifier, generation: generation) }
  }
}
