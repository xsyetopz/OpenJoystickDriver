import Foundation

/// Nanoseconds in a millisecond.
let nanosecondsPerMillisecond: Double = 1_000_000

/// Nanoseconds in a second.
private let nanosecondsPerSecond: Double = 1_000_000_000

/// Repeat cycle of one held destination.
struct RemappingTurboOutput {
  /// Destination that repeats.
  let destination: RemappingDestination
  /// Repeat rate and duty cycle.
  let configuration: RemappingTurbo
  /// Uptime at which the repeat started, in nanoseconds.
  let startedAt: UInt64
  /// Whether the destination is currently down.
  var outputIsDown: Bool

  /// Whether the destination is down at an uptime.
  ///
  /// The press is the first period. The first repeat starts after the initial delay, or after one
  /// period when that is longer, and each repeat is down for the first part of its period, set by
  /// the duty cycle. After the repeat cap the destination stays up. Before the start it keeps its
  /// current state.
  func isDown(at uptimeNanoseconds: UInt64) -> Bool {
    guard uptimeNanoseconds >= startedAt else { return outputIsDown }
    let elapsed = uptimeNanoseconds - startedAt
    guard elapsed >= periodNanoseconds else { return elapsed < onDurationNanoseconds }
    guard elapsed >= firstRepeatNanoseconds else { return false }
    let sinceRepeats = elapsed - firstRepeatNanoseconds
    if let cap = configuration.maxRepeats, sinceRepeats / periodNanoseconds >= UInt64(cap) {
      return false
    }
    return sinceRepeats % periodNanoseconds < onDurationNanoseconds
  }

  /// Returns the uptime at which the destination next changes between down and up, or the largest
  /// value when it changes no more.
  ///
  /// Returns the given uptime when the destination is already out of step with the cycle.
  func nextTransition(after uptimeNanoseconds: UInt64) -> UInt64 {
    guard uptimeNanoseconds >= startedAt else {
      return Self.saturatingAdd(startedAt, onDurationNanoseconds)
    }
    guard isDown(at: uptimeNanoseconds) == outputIsDown else { return uptimeNanoseconds }

    let elapsed = uptimeNanoseconds - startedAt
    let next: UInt64
    if elapsed < periodNanoseconds {
      next = outputIsDown ? onDurationNanoseconds : firstRepeatNanoseconds
    } else if elapsed < firstRepeatNanoseconds {
      next = firstRepeatNanoseconds
    } else {
      let repeatIndex = (elapsed - firstRepeatNanoseconds) / periodNanoseconds
      if let cap = configuration.maxRepeats, repeatIndex >= UInt64(cap) { return .max }
      let repeatStart = firstRepeatNanoseconds + repeatIndex * periodNanoseconds
      if outputIsDown {
        next = repeatStart + onDurationNanoseconds
      } else if let cap = configuration.maxRepeats, repeatIndex + 1 >= UInt64(cap) {
        return .max
      } else {
        next = repeatStart + periodNanoseconds
      }
    }
    return Self.saturatingAdd(startedAt, next)
  }

  /// Offset of the first repeat from the start in nanoseconds.
  private var firstRepeatNanoseconds: UInt64 {
    max(periodNanoseconds, UInt64(configuration.initialDelayMs * nanosecondsPerMillisecond))
  }

  /// Length of one repeat period in nanoseconds, at least 1.
  private var periodNanoseconds: UInt64 {
    max(1, UInt64((nanosecondsPerSecond / configuration.repeatRateHz).rounded()))
  }

  /// Time the destination is down in each period in nanoseconds, at least 1.
  private var onDurationNanoseconds: UInt64 {
    max(1, UInt64((Double(periodNanoseconds) * configuration.dutyCycle).rounded()))
  }

  /// Adds two values and stops at the largest value instead of overflowing.
  static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (sum, overflowed) = lhs.addingReportingOverflow(rhs)
    return overflowed ? .max : sum
  }
}

/// Pointer or scroll movement held by one owner.
struct RemappingContinuousOutput {
  /// Axis that moves.
  let destination: RemappingContinuousDestination
  /// Movement amount passed to the system input action.
  let amount: Double
}

/// One pointer or scroll axis that continuous output drives.
enum RemappingContinuousDestination: CaseIterable, Hashable {
  /// Horizontal pointer movement.
  case mouseX
  /// Vertical pointer movement.
  case mouseY
  /// Horizontal scrolling.
  case scrollX
  /// Vertical scrolling.
  case scrollY

  /// Creates the axis of a continuous destination, or `nil` for any other destination.
  init?(_ destination: RemappingDestination) {
    switch destination {
    case .mouseMovement(.x): self = .mouseX
    case .mouseMovement(.y): self = .mouseY
    case .scroll(.x): self = .scrollX
    case .scroll(.y): self = .scrollY
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .gamepadAxis, .physical, .macro,
      .profileSwitch, .layerSet, .pause, .systemKey, .systemAction, .openApplication, .openURL,
      .runShortcut, .typeText, .speak:
      return nil
    }
  }

  /// Returns the system input action that moves this axis by an amount.
  func action(amount: Double) -> RemappingSystemInputAction {
    switch self {
    case .mouseX: .mouseMoved(axis: .x, amount: amount)
    case .mouseY: .mouseMoved(axis: .y, amount: amount)
    case .scrollX: .scrolled(axis: .x, amount: amount)
    case .scrollY: .scrolled(axis: .y, amount: amount)
    }
  }
}

/// A keyboard or pointer output that is held down.
enum RemappingHeldOutput: Hashable {
  /// A key.
  case key(RemappingKeyboardKey)
  /// A modifier key.
  case modifier(RemappingKeyModifier)
  /// A pointer button.
  case mouseButton(RemappingMouseButton)

  /// System input action that releases the output.
  var releaseAction: RemappingSystemInputAction {
    switch self {
    case .key(let key): .keyUp(key)
    case .modifier(let modifier): .modifierUp(modifier)
    case .mouseButton(let button): .mouseButtonUp(button)
    }
  }

  /// Position in the release order: keys, then pointer buttons, then modifiers.
  var releaseOrder: Int {
    switch self {
    case .key: 0
    case .mouseButton: 1
    case .modifier: 2
    }
  }

  /// Name that orders held outputs of one kind in a stable way.
  var stableName: String {
    switch self {
    case .key(let key): "key:\(key.rawValue)"
    case .modifier(let modifier): "modifier:\(modifier.rawValue)"
    case .mouseButton(let button): "mouse:\(button.rawValue)"
    }
  }
}
