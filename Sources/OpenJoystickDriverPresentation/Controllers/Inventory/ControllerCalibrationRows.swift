import Foundation
import OpenJoystickDriverKit

/// One stick or trigger of the calibration view: its value as the controller reports it, its value
/// after tuning, and the dead zone that applies to it.
struct ControllerCalibrationRow: Equatable, Identifiable {
  /// The controls the view shows.
  enum Control: String, CaseIterable, Sendable {
    /// The left stick.
    case leftStick
    /// The right stick.
    case rightStick
    /// The left trigger.
    case leftTrigger
    /// The right trigger.
    case rightTrigger
  }

  /// The control.
  let control: Control
  /// The deflection or pull the controller reports, `0...1`; for a stick, the distance from the
  /// center.
  let raw: Double
  /// The value of the virtual gamepad after tuning, `0...1`; nil when no virtual gamepad publishes
  /// the controller.
  let tuned: Double?
  /// The stick dead zone, `0..<1`; nil for a trigger and while no layer sets one.
  let deadZone: Double?

  /// The control, which names the row.
  var id: Control { control }
}

/// The rows of the calibration view, from the two values the service reports.
enum ControllerCalibrationRows {
  /// Returns a row for each stick and trigger.
  ///
  /// - Parameters:
  ///   - input: The input the controller reports, before tuning.
  ///   - output: The values the virtual gamepad last reported, or nil when none publishes the
  ///     controller.
  ///   - deadZone: The stick dead zone of the controller's model, or nil while none is set.
  /// - Returns: A row for each stick and trigger, in the order of `Control.allCases`.
  static func rows(
    input: ControllerState,
    output: ApplicationServiceVirtualOutputState?,
    deadZone: Double?
  ) -> [ControllerCalibrationRow] {
    ControllerCalibrationRow.Control.allCases.map { control in
      switch control {
      case .leftStick:
        return ControllerCalibrationRow(
          control: control,
          raw: distance(input.leftStick.x.rawValue, input.leftStick.y.rawValue),
          tuned: output.map { distance($0.leftStickX, $0.leftStickY) },
          deadZone: deadZone
        )
      case .rightStick:
        return ControllerCalibrationRow(
          control: control,
          raw: distance(input.rightStick.x.rawValue, input.rightStick.y.rawValue),
          tuned: output.map { distance($0.rightStickX, $0.rightStickY) },
          deadZone: deadZone
        )
      case .leftTrigger:
        return ControllerCalibrationRow(
          control: control,
          raw: Double(input.leftTrigger.normalized),
          tuned: output.map { pull($0.leftTrigger) },
          deadZone: nil
        )
      case .rightTrigger:
        return ControllerCalibrationRow(
          control: control,
          raw: Double(input.rightTrigger.normalized),
          tuned: output.map { pull($0.rightTrigger) },
          deadZone: nil
        )
      }
    }
  }

  /// Returns the distance of a stick from the center, `0...1`.
  private static func distance(_ x: Int16, _ y: Int16) -> Double {
    min(hypot(Double(x), Double(y)) / Double(Int16.max), 1)
  }

  /// Returns a trigger value of the virtual gamepad as `0...1`.
  private static func pull(_ value: Int16) -> Double {
    min(max(Double(value) / Double(Int16.max), 0), 1)
  }
}
