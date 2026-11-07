import Foundation
import OpenJoystickDriverKit

/// The pointer speed of a profile as the pointer speed sheet edits it, with the scales as text.
struct ProfilePointerSpeedDraft {
  /// Whether the profile scales the pointer.
  var enabled: Bool
  /// The kind of control that drives the scale.
  var driverType: RemappingPointerSpeedDriver.Kind
  /// The stick or trigger side that drives the scale.
  var side: RemappingStickSource
  /// The scale at driver value 0.
  var minScale: String
  /// The scale at driver value 1.
  var maxScale: String
  /// The curve between the two scales.
  var curve: RemappingResponseCurve

  /// Creates the draft of `speed`, or the defaults when the profile has none.
  init(speed: RemappingPointerSpeed?) {
    let value =
      speed
      ?? RemappingPointerSpeed(
        driver: RemappingPointerSpeedDriver(type: .trigger, side: .left),
        minScale: 1,
        maxScale: 0.5
      )
    enabled = speed != nil
    driverType = value.driver.type
    side = value.driver.side
    minScale = String(value.minScale)
    maxScale = String(value.maxScale)
    curve = value.curve
  }

  /// Returns the pointer speed that the draft describes, or nil when it is off.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The pointer speed that the draft describes, or nil when it is off.
  /// - Throws: ``RemappingValidationError/invalidPointerSpeed`` when a scale cannot be read. The
  ///   profile validation checks the range.
  func validatedSpeed(decimalSeparator: String = ".") throws -> RemappingPointerSpeed? {
    guard enabled else { return nil }
    func number(_ raw: String) throws -> Double {
      guard let value = ProfileMotionDraft.numericValue(raw, decimalSeparator: decimalSeparator)
      else { throw RemappingValidationError.invalidPointerSpeed }
      return value
    }
    return RemappingPointerSpeed(
      driver: RemappingPointerSpeedDriver(type: driverType, side: side),
      minScale: try number(minScale),
      maxScale: try number(maxScale),
      curve: curve
    )
  }
}
