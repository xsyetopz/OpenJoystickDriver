import Foundation
import OpenJoystickDriverKit

/// The stick dead zone of a controller model as the detail's setting row shows and changes it.
///
/// The driver keeps no default dead zone, so a model with no layer that sets one has none. A change
/// writes the user's controller record, as `ojd config set stickDeadzone` does.
struct StickDeadzoneSetting: Equatable {
  /// The step of one press of the setting's stepper.
  static let step = 0.01
  /// The values the stepper writes: a record accepts a dead zone above 0 and below 1.
  static let range = 0.01...0.99

  /// The effective value; nil while no layer sets one.
  let value: Double?
  /// The layer that sets the value; `driver` while none does.
  let layer: ControllerRecordLayer

  /// Creates the setting from the stick dead zone of `record`.
  ///
  /// - Parameter record: The effective record of the controller's model.
  init(record: ControllerRecord) {
    let entry = record.tuningValues.first { $0.key == .stickDeadzone }
    value = entry?.value
    layer = entry?.layer ?? .driver
  }

  /// The value as the row shows it, or "Not set" while no layer sets one.
  var text: String {
    value.map { String($0) } ?? OJDLocalized.string("status.notSet")
  }

  /// Whether the user's record sets the value, so removing it changes the effective value.
  var canReset: Bool { value != nil && layer == .user }

  /// The value one step above the current one; with no value set, the lowest value the stepper
  /// writes.
  ///
  /// Nil when the step would not end above the current value inside `range`.
  var increased: Double? {
    guard let value else { return Self.range.lowerBound }
    let next = min(Self.rounded(value + Self.step), Self.range.upperBound)
    return next > value ? next : nil
  }

  /// The value one step below the current one.
  ///
  /// Nil while no layer sets a value, and when the step would not end below the current value
  /// inside `range`.
  var decreased: Double? {
    guard let value else { return nil }
    let next = max(Self.rounded(value - Self.step), Self.range.lowerBound)
    return next < value ? next : nil
  }

  /// Whether a step down removes the user's value, because none is left below the user's value
  /// inside `range`.
  var decrementClears: Bool { canReset && decreased == nil }

  /// Returns `value` without the binary noise of a sum, such as `0.07 + 0.01`.
  ///
  /// - Parameter value: The number to round.
  /// - Returns: `value` without the binary noise of a sum, such as `0.07 + 0.01`.
  private static func rounded(_ value: Double) -> Double { (value * 1e9).rounded() / 1e9 }
}
