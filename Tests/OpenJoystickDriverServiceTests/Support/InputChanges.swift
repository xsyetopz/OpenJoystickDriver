import Foundation

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

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
      case .leftStick(let x, let y): next.leftStick = StickPosition(x: x, y: y)
      case .rightStick(let x, let y): next.rightStick = StickPosition(x: x, y: y)
      case .leftTrigger(let value): next.leftTrigger = UnipolarValue(normalized: value)
      case .rightTrigger(let value): next.rightTrigger = UnipolarValue(normalized: value)
      case .motion: break
      case .touch(let sample): next.recordTouch([sample])
      }
    }
    return next
  }
}

/// The neutral state with `changes` applied.
func snapshot(_ changes: InputChange...) -> ControllerState {
  ControllerState.neutral.applying(changes)
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

/// The snapshot each controller last received through one test object, so a test can script
/// changes the way a pipeline turns reports into snapshots.
final class InputScript: @unchecked Sendable {
  private static let registryLock = NSLock()
  // Guarded by registryLock.
  nonisolated(unsafe) private static var registry: [ObjectIdentifier: (Weak, InputScript)] = [:]

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
      if let entry = unsafe registry[key], entry.0.object === owner { return entry.1 }
      let script = InputScript()
      unsafe registry[key] = (Weak(owner), script)
      return script
    }
  }

  /// Forgets `identifier`, as its pipeline does once the controller stops.
  func reset(_ identifier: LogicalControllerID) {
    lock.withLock { _ = states.removeValue(forKey: identifier) }
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

extension RemappingOutputRouter {
  /// Routes one scripted snapshot of `identifier` per change, in order.
  func dispatchCausally(
    changes: [InputChange],
    from identifier: LogicalControllerID
  ) async throws {
    let script = InputScript.of(self)
    for report in reports(changes, after: script.state(for: identifier)) {
      try await dispatchCausally(
        .input(script.event(report, for: identifier)),
        from: identifier
      )
    }
  }
}

/// A stick value as the engine receives it after 16-bit quantization.
func quantizedStick(_ value: Float) -> Double { Double(BipolarValue(normalized: value).normalized) }
