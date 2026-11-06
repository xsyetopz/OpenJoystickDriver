import Foundation
import OpenJoystickDriverKit

/// The time limits of the steps of a virtual output transition.
struct VirtualOutputTransitionTimeouts: Sendable {
  /// The limits that the service uses.
  static let standard = Self(
    stageNanoseconds: 2_000_000_000,
    perControllerNanoseconds: 2_000_000_000,
    totalNanoseconds: 10_000_000_000,
    zeroControllerActivationNanoseconds: 2_000_000_000,
    feedbackNanoseconds: 2_000_000_000,
    candidateCloseNanoseconds: 2_000_000_000
  )

  /// The limit of one stage, in nanoseconds.
  let stageNanoseconds: UInt64
  /// The limit of the activation of one controller, in nanoseconds.
  let perControllerNanoseconds: UInt64
  /// The limit of the activation of all controllers, in nanoseconds.
  let totalNanoseconds: UInt64
  /// The limit of an activation that covers no controller, in nanoseconds.
  let zeroControllerActivationNanoseconds: UInt64
  /// The limit of neutralizing the feedback, in nanoseconds.
  let feedbackNanoseconds: UInt64
  /// The limit of closing a candidate backend, in nanoseconds.
  let candidateCloseNanoseconds: UInt64

  /// Creates the limits; the last three default to two seconds.
  init(
    stageNanoseconds: UInt64,
    perControllerNanoseconds: UInt64,
    totalNanoseconds: UInt64,
    zeroControllerActivationNanoseconds: UInt64 = 2_000_000_000,
    feedbackNanoseconds: UInt64 = 2_000_000_000,
    candidateCloseNanoseconds: UInt64 = 2_000_000_000
  ) {
    self.stageNanoseconds = stageNanoseconds
    self.perControllerNanoseconds = perControllerNanoseconds
    self.totalNanoseconds = totalNanoseconds
    self.zeroControllerActivationNanoseconds = zeroControllerActivationNanoseconds
    self.feedbackNanoseconds = feedbackNanoseconds
    self.candidateCloseNanoseconds = candidateCloseNanoseconds
  }

  /// Returns the limit for activating `count` controllers: the per-controller limit times `count`,
  /// capped at the total.
  func activationNanoseconds(for count: Int) -> UInt64 {
    guard count > 0 else { return zeroControllerActivationNanoseconds }
    let perController = perControllerNanoseconds.multipliedReportingOverflow(by: UInt64(count))
    return min(perController.overflow ? UInt64.max : perController.partialValue, totalNanoseconds)
  }
}

/// The time source and the sleep of a transition, replaceable so tests control time.
struct VirtualOutputTransitionClock: Sendable {
  /// The uptime clock and a dispatch timer.
  static let system = Self(
    now: { DispatchTime.now().uptimeNanoseconds },
    sleep: { nanoseconds in try await DeadlineTimer.dispatch.sleep(nanoseconds: nanoseconds) }
  )

  /// Returns the current uptime in nanoseconds.
  let now: @Sendable () -> UInt64
  /// Sleeps for the given nanoseconds, and throws when cancelled.
  let sleep: @Sendable (UInt64) async throws -> Void
}
