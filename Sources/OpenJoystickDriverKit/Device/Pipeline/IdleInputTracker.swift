import Foundation

/// When a controller's input state last changed, on a monotonic clock the caller supplies.
///
/// A report that repeats the state before it does not count as a change.
struct IdleInputTracker: Sendable {
  private var lastState: ControllerState = .neutral
  private var lastChangeNanoseconds: UInt64

  /// Starts the idle time at `now`.
  init(now: UInt64) { lastChangeNanoseconds = now }

  /// Records `state` as seen at `now` and restarts the idle time when it differs from the last.
  mutating func observe(_ state: ControllerState, at now: UInt64) {
    guard state != lastState else { return }
    lastState = state
    lastChangeNanoseconds = now
  }

  /// Restarts the idle time at `now` without changing the last state.
  mutating func restart(at now: UInt64) { lastChangeNanoseconds = now }

  /// How long the state has been unchanged at `now`.
  func idleNanoseconds(at now: UInt64) -> UInt64 {
    now >= lastChangeNanoseconds ? now - lastChangeNanoseconds : 0
  }
}

/// Which links the idle disconnect applies to.
enum IdleDisconnectPolicy {
  /// Whether a controller on `transport` that was idle for `idleNanoseconds` is due for the idle
  /// disconnect after `minutes`; a cable, a receiver and an unknown link never are.
  static func isDue(
    transport: PhysicalTransport?,
    idleNanoseconds: UInt64,
    afterMinutes minutes: Int
  ) -> Bool {
    switch transport {
    case .bluetoothClassic, .bluetoothLE:
      idleNanoseconds >= UInt64(minutes) * 60 * 1_000_000_000
    case .usb, .proprietaryRadioReceiver, nil: false
    }
  }
}
