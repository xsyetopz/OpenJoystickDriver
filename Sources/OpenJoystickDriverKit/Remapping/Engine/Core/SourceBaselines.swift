import Foundation

/// One input change the engine applies, found by diffing a source's snapshot against its baseline.
///
/// Axes are in the remapping frame: Y points down.
enum RemappingInputChange: Equatable {
  /// A button was pressed or released.
  case button(Control, isPressed: Bool)
  /// The hat direction changed.
  case dpad(HatDirection)
  /// The left stick moved.
  case leftStick(x: Float, y: Float)
  /// The right stick moved.
  case rightStick(x: Float, y: Float)
  /// The pointer moved.
  case pointer(x: Float, y: Float)
  /// The left trigger value changed.
  case leftTrigger(Float)
  /// The right trigger value changed.
  case rightTrigger(Float)
  /// A motion sample arrived.
  case motion(ControllerMotionSample)
  /// A touch frame arrived.
  case touch(ControllerTouchSample)
}

extension RemappingEngineState {
  /// Diffs `event` against the last snapshot `source` delivered and applies the changes to
  /// `target`.
  ///
  /// Each source keeps its own baseline, so two sources feeding one target (a Joy-Con pair) never
  /// release each other's controls.
  mutating func process(
    _ event: ControllerEvent,
    from source: LogicalControllerID,
    into target: LogicalControllerID,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingEngineAction] {
    let baseline = sourceBaselines[source] ?? .neutral
    sourceBaselines[source] = event.state
    let changes =
      Self.changes(from: baseline, to: event.state)
      + event.motion.map(RemappingInputChange.motion)
      + event.touchFrames.map(RemappingInputChange.touch)
    return process(changes: changes, from: target, profile: profile, at: uptimeNanoseconds)
  }

  /// Returns the changes from one snapshot to another.
  ///
  /// Every button release comes before any button press, so a report that swaps one held button for
  /// another never shows both held. Releases and presses each follow ``controlOrder``. The hat,
  /// left stick, right stick, pointer, left trigger and right trigger follow.
  static func changes(
    from old: ControllerState,
    to new: ControllerState
  ) -> [RemappingInputChange] {
    var changes: [RemappingInputChange] = []
    for isPressed in [false, true] {
      for control in controlOrder {
        guard old.pressed.contains(control) != new.pressed.contains(control),
          new.pressed.contains(control) == isPressed
        else { continue }
        changes.append(.button(control, isPressed: isPressed))
      }
    }
    if old.hat != new.hat { changes.append(.dpad(new.hat)) }
    if old.leftStick != new.leftStick {
      changes.append(.leftStick(x: new.leftStick.x.normalized, y: new.leftStick.y.normalized))
    }
    if old.rightStick != new.rightStick {
      changes.append(.rightStick(x: new.rightStick.x.normalized, y: new.rightStick.y.normalized))
    }
    if old.pointer != new.pointer {
      changes.append(.pointer(x: new.pointer.x.normalized, y: new.pointer.y.normalized))
    }
    if old.leftTrigger != new.leftTrigger {
      changes.append(.leftTrigger(new.leftTrigger.normalized))
    }
    if old.rightTrigger != new.rightTrigger {
      changes.append(.rightTrigger(new.rightTrigger.normalized))
    }
    return changes
  }

  /// Digital controls in the one order that releases and presses are each delivered in, the same
  /// for every controller.
  static let controlOrder: [Control] =
    [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder, .leftStickClick,
      .rightStickClick, .start, .back, .guide, .leftTrigger, .rightTrigger, .capture,
      .touchpadClick, .microphone,
      .leftPaddle2, .rightPaddle2, .leftTrackpadClick, .rightTrackpadClick, .auxiliary3,
      .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary1, .auxiliary2, .leftPaddle1,
      .rightPaddle1,
    ]
}
