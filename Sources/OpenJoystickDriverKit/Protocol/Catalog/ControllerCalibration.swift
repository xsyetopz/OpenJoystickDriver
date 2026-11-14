import Foundation

/// Stored stick centres, stick ranges, and trigger ends of one controller, applied to each input
/// state before profile mapping.
///
/// Every value is in the normalized units of the state: a centre is `-1...1`, a stick range is the
/// deflection from the centre that reads as full, and a trigger end is `0...1`. A key that is not
/// set leaves its control as the controller reports it.
public struct ControllerCalibration: Codable, Equatable, Sendable {
  /// The calibration that sets no key.
  public static let none = Self(values: [:])

  /// The tuning keys the calibration is stored under.
  public static let keys: Set<ControllerTuning.Key> = [
    .leftStickCenterX, .leftStickCenterY, .rightStickCenterX, .rightStickCenterY,
    .leftStickRange, .rightStickRange, .leftTriggerRest, .leftTriggerFull, .rightTriggerRest,
    .rightTriggerFull,
  ]

  /// The stick deflection or trigger travel below which a capture counts the control as not moved.
  public static let movementThreshold = 0.1
  /// The highest trigger rest a capture stores, so that a trigger held through the rest step keeps
  /// a usable span.
  static let restCeiling = 0.9

  /// The stored values by key.
  public var values: [ControllerTuning.Key: Double]

  /// Creates a calibration from its stored values.
  public init(values: [ControllerTuning.Key: Double]) { self.values = values }

  /// Decodes the stored values from a JSON object of tuning key names.
  public init(from decoder: any Decoder) throws {
    let named = try decoder.singleValueContainer().decode([String: Double].self)
    values = Dictionary(
      uniqueKeysWithValues: named.compactMap { name, value in
        ControllerTuning.Key(rawValue: name).map { ($0, value) }
      }
    )
  }

  /// Encodes the stored values as a JSON object of tuning key names.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(
      Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    )
  }

  /// One step of the recalibration, each captured from raw input samples.
  public enum Step: String, CaseIterable, Sendable {
    /// Sticks and triggers released: stores the stick centres and the trigger rests.
    case rest
    /// Each stick moved through its full circle: stores the stick ranges.
    case circle
    /// Each trigger pressed fully: stores the trigger ends.
    case triggers

    /// The controls a step measures.
    public var controls: [Control] {
      switch self {
      case .rest: Control.stickAxes + [.leftTrigger, .rightTrigger]
      case .circle: Control.stickAxes
      case .triggers: [.leftTrigger, .rightTrigger]
      }
    }
  }

  /// What a step measured.
  public struct Outcome: Equatable, Sendable {
    /// The values the step measured; a key it measured nothing for is absent.
    public var values: [ControllerTuning.Key: Double]
    /// The controls that did not move enough to measure, whose stored values stay.
    public var unmoved: [Control]
  }

  /// This calibration applied to `state`; a stick or trigger with no key set is unchanged.
  public func applying(to state: ControllerState) -> ControllerState {
    var state = state
    state.leftStick = stick(
      state.leftStick,
      centerX: .leftStickCenterX,
      centerY: .leftStickCenterY,
      range: .leftStickRange
    )
    state.rightStick = stick(
      state.rightStick,
      centerX: .rightStickCenterX,
      centerY: .rightStickCenterY,
      range: .rightStickRange
    )
    state.leftTrigger = trigger(state.leftTrigger, rest: .leftTriggerRest, full: .leftTriggerFull)
    state.rightTrigger = trigger(
      state.rightTrigger,
      rest: .rightTriggerRest,
      full: .rightTriggerFull
    )
    return state
  }

  private func stick(
    _ position: StickPosition,
    centerX: ControllerTuning.Key,
    centerY: ControllerTuning.Key,
    range: ControllerTuning.Key
  ) -> StickPosition {
    guard [centerX, centerY, range].contains(where: { values[$0] != nil }) else { return position }
    let scale = values[range] ?? 1
    let x = (Double(position.x.normalized) - (values[centerX] ?? 0)) / scale
    let y = (Double(position.y.normalized) - (values[centerY] ?? 0)) / scale
    return StickPosition(x: Float(x), y: Float(y))
  }

  private func trigger(
    _ value: UnipolarValue,
    rest: ControllerTuning.Key,
    full: ControllerTuning.Key
  ) -> UnipolarValue {
    guard values[rest] != nil || values[full] != nil else { return value }
    let low = values[rest] ?? 0
    let span = (values[full] ?? 1) - low
    // Two layers may set the ends, so a rest at or above the full press is possible here.
    guard span > 0 else { return value }
    return UnipolarValue(normalized: Float((Double(value.normalized) - low) / span))
  }

  /// What `step` measures from the raw `samples`, with `stored` giving the centres and rests a
  /// later step measures from.
  public static func capture(
    _ step: Step,
    samples: [ControllerState],
    stored: Self
  ) -> Outcome {
    guard !samples.isEmpty else { return Outcome(values: [:], unmoved: step.controls) }
    switch step {
    case .rest: return rest(of: samples)
    case .circle: return circle(of: samples, stored: stored)
    case .triggers: return triggers(of: samples, stored: stored)
    }
  }

  private static func mean(
    _ samples: [ControllerState],
    _ read: (ControllerState) -> Double
  )
    -> Double
  { samples.map(read).reduce(0, +) / Double(samples.count) }

  private static func rest(of samples: [ControllerState]) -> Outcome {
    let measured: [ControllerTuning.Key: Double] = [
      .leftStickCenterX: mean(samples) { Double($0.leftStick.x.normalized) },
      .leftStickCenterY: mean(samples) { Double($0.leftStick.y.normalized) },
      .rightStickCenterX: mean(samples) { Double($0.rightStick.x.normalized) },
      .rightStickCenterY: mean(samples) { Double($0.rightStick.y.normalized) },
      .leftTriggerRest: min(mean(samples) { Double($0.leftTrigger.normalized) }, restCeiling),
      .rightTriggerRest: min(mean(samples) { Double($0.rightTrigger.normalized) }, restCeiling),
    ]
    return Outcome(values: measured, unmoved: [])
  }

  private static func circle(of samples: [ControllerState], stored: Self) -> Outcome {
    var outcome = Outcome(values: [:], unmoved: [])
    let sticks:
      [(
        ControllerTuning.Key, ControllerTuning.Key, ControllerTuning.Key, [Control],
        (ControllerState) -> StickPosition
      )] = [
        (
          .leftStickCenterX, .leftStickCenterY, .leftStickRange, [.leftStickX, .leftStickY],
          \.leftStick
        ),
        (
          .rightStickCenterX, .rightStickCenterY, .rightStickRange, [.rightStickX, .rightStickY],
          \.rightStick
        ),
      ]
    for (centerX, centerY, range, controls, read) in sticks {
      let cx = stored.values[centerX] ?? 0
      let cy = stored.values[centerY] ?? 0
      let reach =
        samples.map {
          let position = read($0)
          return hypot(Double(position.x.normalized) - cx, Double(position.y.normalized) - cy)
        }.max() ?? 0
      if reach < movementThreshold {
        outcome.unmoved += controls
      } else {
        outcome.values[range] = min(reach, 2)
      }
    }
    return outcome
  }

  private static func triggers(of samples: [ControllerState], stored: Self) -> Outcome {
    var outcome = Outcome(values: [:], unmoved: [])
    let triggers:
      [(ControllerTuning.Key, ControllerTuning.Key, Control, (ControllerState) -> UnipolarValue)] =
        [
          (.leftTriggerRest, .leftTriggerFull, .leftTrigger, \.leftTrigger),
          (.rightTriggerRest, .rightTriggerFull, .rightTrigger, \.rightTrigger),
        ]
    for (rest, full, control, read) in triggers {
      let peak = samples.map { Double(read($0).normalized) }.max() ?? 0
      if peak - (stored.values[rest] ?? 0) < movementThreshold {
        outcome.unmoved.append(control)
      } else {
        outcome.values[full] = peak
      }
    }
    return outcome
  }
}
