import Foundation

@testable import OpenJoystickDriverKit

/// One change a test applies to a controller's previous snapshot.
///
/// Stick Y is positive down, as in the controller state and the engine.
enum InputChange: Equatable {
  case press(Control)
  case release(Control)
  case hat(HatDirection)
  case leftStick(x: Float, y: Float)
  case rightStick(x: Float, y: Float)
  case leftTrigger(Float)
  case rightTrigger(Float)
  case motion(ControllerMotionSample)
  case touch(ControllerTouchSample)
}

extension ControllerState {
  /// This state with `changes` applied in order.
  func applying(_ changes: [InputChange]) -> ControllerState {
    var next = self
    for change in changes {
      switch change {
      case .press(let control): next.pressed.insert(control)
      case .release(let control): next.pressed.remove(control)
      case .hat(let hat): next.hat = hat
      case .leftStick(let x, let y):
        next.leftStick = StickPosition(
          x: BipolarValue(normalized: x),
          y: BipolarValue(normalized: y)
        )
      case .rightStick(let x, let y):
        next.rightStick = StickPosition(
          x: BipolarValue(normalized: x),
          y: BipolarValue(normalized: y)
        )
      case .leftTrigger(let value): next.leftTrigger = UnipolarValue(normalized: value)
      case .rightTrigger(let value): next.rightTrigger = UnipolarValue(normalized: value)
      case .motion: break
      case .touch(let sample): next.recordTouch([sample])
      }
    }
    return next
  }
}

extension ControllerEvent {
  /// `base` with `changes` applied, carrying the changes' samples.
  init(_ changes: [InputChange], after base: ControllerState = .neutral, at nanoseconds: UInt64 = 0)
  {
    self.init(
      timestamp: MonotonicTimestamp(nanoseconds: nanoseconds),
      state: base.applying(changes),
      motion: changes.compactMap {
        if case .motion(let sample) = $0 { return sample }
        return nil
      },
      touchFrames: changes.compactMap {
        if case .touch(let sample) = $0 { return sample }
        return nil
      }
    )
  }
}

/// The snapshot each controller last received through one test object, so a test can script changes
/// the way the pipeline turns reports into snapshots.
///
/// The `changes:`/`inputs:` helpers below treat a scripted change list as a sequence of reports,
/// one change each; pins that need several changes in one report build the event themselves.
final class InputScript: @unchecked Sendable {
  private static let registryLock = NSLock()
  nonisolated(unsafe) private static var registry:
    [ObjectIdentifier: (owner: Weak, script: InputScript)] = [:]  // Guarded by registryLock.

  private final class Weak {
    weak var object: AnyObject?
    init(_ object: AnyObject) { self.object = object }
  }

  private let lock = NSLock()
  private var states: [LogicalControllerID: ControllerState] = [:]

  /// The script bound to `owner` for as long as it lives.
  static func of(_ owner: AnyObject) -> InputScript {
    registryLock.withLock {
      let key = ObjectIdentifier(owner)
      if let entry = registry[key], entry.owner.object === owner { return entry.script }
      let script = InputScript()
      registry[key] = (Weak(owner), script)
      return script
    }
  }

  /// The snapshot `identifier` last received.
  func state(for identifier: LogicalControllerID) -> ControllerState {
    lock.withLock { states[identifier] ?? .neutral }
  }

  /// The next snapshot of `identifier`: its last one with `changes` applied.
  func event(_ changes: [InputChange], for identifier: LogicalControllerID) -> ControllerEvent {
    lock.withLock {
      let event = ControllerEvent(changes, after: states[identifier] ?? .neutral)
      states[identifier] = event.state
      return event
    }
  }

  /// Forgets `identifier`, as a pipeline does once its controller stops.
  func reset(_ identifier: LogicalControllerID) {
    lock.withLock { _ = states.removeValue(forKey: identifier) }
  }
}

/// Each change of a scripted sequence as its own report; an empty sequence is one unchanged report.
///
/// A press of a control `base` already holds is a fresh physical press: a release report first.
func reports(_ changes: [InputChange], after base: ControllerState) -> [[InputChange]] {
  guard !changes.isEmpty else { return [[]] }
  var state = base
  var reports: [[InputChange]] = []
  for change in changes {
    if case .press(let control) = change, state.pressed.contains(control) {
      reports.append([.release(control)])
    }
    reports.append([change])
    state = state.applying([change])
  }
  return reports
}

extension OutputDispatcher {
  /// Dispatches one scripted snapshot of `identifier` per change, in order.
  func dispatch(
    changes: [InputChange],
    from identifier: LogicalControllerID
  ) async {
    let script = InputScript.of(self)
    for report in reports(changes, after: script.state(for: identifier)) {
      await dispatch(script.event(report, for: identifier), from: identifier)
    }
  }
}

extension RemappingEventEngine {
  /// Processes one snapshot per change, each applied to the snapshot `source` last delivered.
  func process(
    inputs changes: [InputChange],
    from source: LogicalControllerID,
    using profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) async throws {
    for report in reports(changes, after: state.sourceBaselines[source] ?? .neutral) {
      let base = state.sourceBaselines[source] ?? .neutral
      try await process(
        ControllerEvent(report, after: base, at: uptimeNanoseconds),
        from: source,
        using: profile,
        at: uptimeNanoseconds
      )
    }
  }

  func process(
    inputs changes: [InputChange],
    from source: LogicalControllerID,
    using profile: RemappingProfile,
    at uptimeNanoseconds: UInt64,
    requiring permit: RemappingEmissionPermit
  ) async throws {
    for report in reports(changes, after: state.sourceBaselines[source] ?? .neutral) {
      let base = state.sourceBaselines[source] ?? .neutral
      try await process(
        ControllerEvent(report, after: base, at: uptimeNanoseconds),
        from: source,
        using: profile,
        at: uptimeNanoseconds,
        requiring: permit
      )
    }
  }
}

extension RemappingEngineState {
  /// Applies `changes` to the snapshot `source` last delivered, through the snapshot diff.
  mutating func process(
    inputs changes: [InputChange],
    from source: LogicalControllerID,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    reports(changes, after: sourceBaselines[source] ?? .neutral).flatMap { report in
      let base = sourceBaselines[source] ?? .neutral
      return process(
        ControllerEvent(report, after: base, at: uptimeNanoseconds),
        from: source,
        into: source,
        profile: profile,
        at: uptimeNanoseconds
      )
    }
  }
}

extension ControllerEvent {
  /// Whether this snapshot holds the value that `change` sets.
  ///
  /// The value is a pressed or released control, the hat, or a stick or trigger position; a sample
  /// is carried by the event.
  func holds(_ change: InputChange) -> Bool {
    switch change {
    case .press(let control): state.pressed.contains(control)
    case .release(let control): !state.pressed.contains(control)
    case .hat(let hat): state.hat == hat
    case .leftStick, .rightStick, .leftTrigger, .rightTrigger:
      ControllerState.neutral.applying([change]).matches(change, in: state)
    case .motion(let sample): motion.contains(sample)
    case .touch(let sample): touchFrames.contains(sample)
    }
  }
}

extension ControllerState {
  func matches(_ change: InputChange, in other: ControllerState) -> Bool {
    switch change {
    case .leftStick: leftStick == other.leftStick
    case .rightStick: rightStick == other.rightStick
    case .leftTrigger: leftTrigger == other.leftTrigger
    case .rightTrigger: rightTrigger == other.rightTrigger
    default: false
    }
  }
}

extension PhysicalProtocolDriver {
  /// Parses one report received at `nanoseconds`.
  func parseReport(_ report: Data, at nanoseconds: UInt64 = 0) throws -> ControllerEvent? {
    try parse(report: report, receivedAt: MonotonicTimestamp(nanoseconds: nanoseconds))
  }
}

extension ControllerEvent? {
  /// Whether a parsed snapshot exists and holds the value that `change` sets.
  func contains(_ change: InputChange) -> Bool { self?.holds(change) ?? false }
}

/// The neutral state with `changes` applied.
func snapshot(_ changes: InputChange...) -> ControllerState {
  ControllerState.neutral.applying(changes)
}

/// A driver double's running state: each scripted report applies its changes to the last one.
struct ScriptedState {
  private(set) var state = ControllerState.neutral

  mutating func event(_ changes: [InputChange], at timestamp: MonotonicTimestamp) -> ControllerEvent
  {
    let event = ControllerEvent(changes, after: state, at: timestamp.nanoseconds)
    state = event.state
    return event
  }
}

extension RemappingEngineState {
  /// Processes one parsed snapshot as its own source; a frame without input changes nothing.
  mutating func process(
    parsed event: ControllerEvent?,
    from source: LogicalControllerID,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    guard let event else { return [] }
    return process(
      event,
      from: source,
      into: source,
      profile: profile,
      at: uptimeNanoseconds
    )
  }
}

extension ControllerEvent? {
  /// The left stick in the remapping frame (Y down); nil without a snapshot.
  var leftStickPosition: (x: Float, y: Float)? {
    self.map { ($0.state.leftStick.x.normalized, $0.state.leftStick.y.normalized) }
  }

  /// The right stick in the remapping frame (Y down); nil without a snapshot.
  var rightStickPosition: (x: Float, y: Float)? {
    self.map { ($0.state.rightStick.x.normalized, $0.state.rightStick.y.normalized) }
  }
}

/// A stick value as the engine receives it after 16-bit quantization.
func quantizedStick(_ value: Float) -> Double { Double(BipolarValue(normalized: value).normalized) }

/// A trigger value as the engine receives it after 16-bit quantization.
func quantizedTrigger(_ value: Float) -> Double {
  Double(UnipolarValue(normalized: value).normalized)
}
