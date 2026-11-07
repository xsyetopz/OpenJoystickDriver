import Foundation
import OpenJoystickDriverKit

/// One region source as the region sheet edits it, with the numbers as text.
struct ProfileRegionDraft {
  /// What kind of region the draft describes.
  enum Kind: CaseIterable {
    /// A ring, and optionally a sector, of a stick.
    case stick
    /// A pressure band of a trigger.
    case trigger
    /// A rectangle of a touch surface.
    case touch
  }

  /// A live reading of the input that the region watches, each part from 0 to 1 unless noted.
  enum Reading: Equatable {
    /// A stick after its dead zone: the deflection and the angle in degrees clockwise from up.
    case stick(x: Double, y: Double, deflection: Double, degrees: Double)
    /// A trigger pull.
    case trigger(Double)
    /// The first active contact of the surface.
    case touch(x: Double, y: Double)
    /// A touch surface without an active contact.
    case noContact
  }

  /// The kind of region.
  var kind: Kind = .stick
  /// The stick of a stick region.
  var stick: RemappingStickSource = .left
  /// The trigger of a trigger band.
  var trigger: RemappingTriggerSource = .left
  /// The surface of a touch area.
  var surface: RemappingTouchSurface = .primary
  /// The inner radius of a stick ring.
  var innerRadius = "0.8"
  /// The outer radius of a stick ring.
  var outerRadius = "1"
  /// The start of the stick sector in degrees; empty with an empty ``toDegrees`` for the circle.
  var fromDegrees = ""
  /// The end of the stick sector in degrees.
  var toDegrees = ""
  /// The start of a trigger band.
  var from = "0.5"
  /// The end of a trigger band.
  var to = "1"
  /// The hysteresis of a stick ring or trigger band.
  var hysteresis = String(RemappingStickRegionSource.defaultHysteresis)
  /// The left edge of a touch area.
  var x = "0"
  /// The top edge of a touch area.
  var y = "0"
  /// The width of a touch area.
  var width = "0.5"
  /// The height of a touch area.
  var height = "0.5"

  /// Returns the source that the draft describes; the profile validates the ranges when the
  /// binding is added.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The source that the draft describes.
  /// - Throws: The validation error of the kind when a number cannot be read.
  func source(decimalSeparator: String = ".") throws -> RemappingSource {
    func number(_ raw: String, _ error: RemappingValidationError) throws -> Double {
      guard let value = ProfileMotionDraft.numericValue(raw, decimalSeparator: decimalSeparator)
      else { throw error }
      return value
    }
    switch kind {
    case .stick:
      let error = RemappingValidationError.invalidStickRegion
      let sector = [fromDegrees, toDegrees].map {
        $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0
      }
      return .stickRegion(
        RemappingStickRegionSource(
          stick: stick,
          innerRadius: try number(innerRadius, error),
          outerRadius: try number(outerRadius, error),
          fromDegrees: try sector[0].map { try number($0, error) },
          toDegrees: try sector[1].map { try number($0, error) },
          hysteresis: try number(hysteresis, error)
        )
      )
    case .trigger:
      let error = RemappingValidationError.invalidTriggerBand
      return .triggerBand(
        RemappingTriggerBandSource(
          trigger: trigger,
          from: try number(from, error),
          to: try number(to, error),
          hysteresis: try number(hysteresis, error)
        )
      )
    case .touch:
      let error = RemappingValidationError.invalidTouchArea
      return .touchArea(
        RemappingTouchAreaSource(
          surface: surface,
          x: try number(x, error),
          y: try number(y, error),
          width: try number(width, error),
          height: try number(height, error)
        )
      )
    }
  }

  /// Returns the live reading of the watched input in `state`.
  ///
  /// - Parameters:
  ///   - state: The latest input state of the controller.
  ///   - tuning: The tuning of the stick mapping, whose dead zone the engine applies.
  /// - Returns: The live reading of the watched input.
  func reading(of state: ControllerState, tuning: RemappingStickTuning) -> Reading {
    switch kind {
    case .stick:
      let position = stick == .left ? state.leftStick : state.rightStick
      let calibrated =
        RemappingStickTransform.value(
          x: Double(position.x.rawValue) / Double(BipolarValue.max.rawValue),
          y: Double(position.y.rawValue) / Double(BipolarValue.max.rawValue),
          tuning: tuning
        ) ?? .zero
      let degrees = atan2(calibrated.x, -calibrated.y) * 180 / .pi
      return .stick(
        x: calibrated.x,
        y: calibrated.y,
        deflection: min(1, hypot(calibrated.x, calibrated.y)),
        degrees: degrees < 0 ? degrees + 360 : degrees
      )
    case .trigger:
      let value = trigger == .left ? state.leftTrigger : state.rightTrigger
      return .trigger(Double(value.rawValue) / Double(UnipolarValue.max.rawValue))
    case .touch:
      let contact = state.touch.first { RemappingTouchSurface($0.surface) == surface }?
        .contacts.first { $0.isActive }
      guard let contact else { return .noContact }
      return .touch(
        x: Double(contact.x) / Double(UInt16.max),
        y: Double(contact.y) / Double(UInt16.max)
      )
    }
  }
}
