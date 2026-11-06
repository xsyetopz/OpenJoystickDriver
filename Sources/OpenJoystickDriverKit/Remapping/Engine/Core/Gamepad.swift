import Foundation

/// Normalized gamepad output owned by one exact remapping session.
public struct RemappingGamepadState: Equatable, Sendable {
  /// Buttons that are down, limited to those a virtual gamepad supports.
  public let buttons: Set<Control>
  /// D-pad directions that are down; opposite directions cancel each other.
  public let dpad: Set<RemappingDpadDirection>
  /// Nonzero axis values: sticks from -1 to 1 and triggers from 0 to 1.
  public let axes: [RemappingAxis: Double]

  /// Creates a state from buttons, d-pad directions and axis values.
  ///
  /// Unsupported buttons are dropped. Opposite d-pad directions cancel. Axis values that are not
  /// finite or are zero are dropped, and the others are clamped to their range.
  public init(
    buttons: Set<Control> = [],
    dpad: Set<RemappingDpadDirection> = [],
    axes: [RemappingAxis: Double] = [:]
  ) {
    self.buttons = buttons.filter(\.supportsVirtualOutput)
    var directions = dpad
    if directions.contains(.up), directions.contains(.down) { directions.subtract([.up, .down]) }
    if directions.contains(.left), directions.contains(.right) {
      directions.subtract([.left, .right])
    }
    self.dpad = directions
    self.axes = axes.reduce(into: [:]) { result, entry in
      let (axis, value) = entry
      guard value.isFinite else { return }
      let minimum = Self.isTrigger(axis) ? 0.0 : -1.0
      let normalized = min(1, max(minimum, value))
      if normalized != 0 { result[axis] = normalized }
    }
  }

  /// State with nothing pressed.
  public static let neutral = Self()

  /// Returns the value of an axis, or 0 when the state has none for it.
  public func value(for axis: RemappingAxis) -> Double { axes[axis, default: 0] }

  /// Whether an axis is one of the triggers.
  static func isTrigger(_ axis: RemappingAxis) -> Bool {
    axis == .leftTrigger || axis == .rightTrigger
  }
}

/// Keeps the contribution of each owner apart, so releasing one cannot release another.
///
/// Stick axes add up across owners and trigger axes take the largest value.
struct RemappingGamepadAccumulator: Sendable {
  /// Contribution of each owner.
  private var contributions: [UUID: RemappingGamepadState] = [:]
  /// Aggregate of all contributions.
  private(set) var state = RemappingGamepadState.neutral

  /// Sets the contribution of an owner and returns the aggregate when it changed.
  ///
  /// A neutral contribution removes the owner. Returns `nil` when the aggregate did not change.
  mutating func update(
    _ contribution: RemappingGamepadState,
    for bindingID: UUID
  ) -> RemappingGamepadState? {
    if contribution == .neutral {
      contributions.removeValue(forKey: bindingID)
    } else {
      contributions[bindingID] = contribution
    }
    return recompute()
  }

  /// Removes the contribution of an owner and returns the aggregate when it changed.
  mutating func release(_ bindingID: UUID) -> RemappingGamepadState? {
    update(.neutral, for: bindingID)
  }

  /// Removes all contributions and returns the aggregate when it changed.
  mutating func drain() -> RemappingGamepadState? {
    contributions.removeAll()
    return recompute()
  }

  /// Recomputes the aggregate and returns it when it changed.
  ///
  /// A stable owner order makes floating-point sums independent of insertion order.
  private mutating func recompute() -> RemappingGamepadState? {
    var buttons: Set<Control> = []
    var dpad: Set<RemappingDpadDirection> = []
    var axes: [RemappingAxis: Double] = [:]
    // A stable order makes floating-point aggregation independent of dictionary insertion order.
    for id in contributions.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      guard let contribution = contributions[id] else { continue }
      buttons.formUnion(contribution.buttons)
      dpad.formUnion(contribution.dpad)
      for (axis, value) in contribution.axes {
        if RemappingGamepadState.isTrigger(axis) {
          axes[axis] = max(axes[axis, default: 0], value)
        } else {
          axes[axis, default: 0] += value
        }
      }
    }
    let next = RemappingGamepadState(buttons: buttons, dpad: dpad, axes: axes)
    guard next != state else { return nil }
    state = next
    return next
  }
}

extension RemappingGamepadState {
  /// The hat direction the held d-pad directions form; opposite directions cancel.
  var dpadDirection: HatDirection {
    let horizontal = (dpad.contains(.right) ? 1 : 0) - (dpad.contains(.left) ? 1 : 0)
    let vertical = (dpad.contains(.up) ? 1 : 0) - (dpad.contains(.down) ? 1 : 0)
    switch (horizontal, vertical) {
    case (0, 1): return .north
    case (1, 1): return .northEast
    case (1, 0): return .east
    case (1, -1): return .southEast
    case (0, -1): return .south
    case (-1, -1): return .southWest
    case (-1, 0): return .west
    case (-1, 1): return .northWest
    default: return .neutral
    }
  }
}
