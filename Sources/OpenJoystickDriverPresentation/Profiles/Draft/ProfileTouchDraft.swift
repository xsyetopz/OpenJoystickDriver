import Foundation
import OpenJoystickDriverKit

/// One touch surface mapping as the touch sheet edits it, with the numbers as text.
struct ProfileTouchDraft {
  /// The identifier of the mapping.
  let id: UUID
  /// The touch surface.
  let surface: RemappingTouchSurface
  /// Whether the surface has a mapping.
  var enabled: Bool
  /// The mode of the mapping.
  var mode: RemappingTouchMode
  /// The pointer sensitivity.
  var pointerSensitivity: String
  /// The stick radius.
  var stickRadius: String
  /// The dead zone.
  var deadzone: String

  /// Creates the draft of `surface` from its mapping, or the defaults when it has none.
  init(surface: RemappingTouchSurface, mapping: RemappingTouchMapping?) {
    let value = mapping ?? RemappingTouchMapping(surface: surface, mode: .pointer)
    id = value.id
    self.surface = surface
    enabled = mapping != nil
    mode = value.mode
    pointerSensitivity = String(value.pointerSensitivity)
    stickRadius = String(value.stickRadius)
    deadzone = String(value.deadzone)
  }

  /// Returns the mapping that the draft describes, or nil when the surface has none.
  ///
  /// - Parameter decimalSeparator: The separator the person types in the numbers.
  /// - Returns: The mapping that the draft describes, or nil when the surface has none.
  /// - Throws: ``RemappingValidationError`` when a number cannot be read or is out of range.
  func validatedMapping(decimalSeparator: String = ".") throws -> RemappingTouchMapping? {
    guard enabled else { return nil }
    func number(_ raw: String) throws -> Double {
      guard let value = ProfileMotionDraft.numericValue(raw, decimalSeparator: decimalSeparator)
      else { throw RemappingValidationError.invalidTouchMapping(surface) }
      return value
    }
    let mapping = RemappingTouchMapping(
      id: id,
      surface: surface,
      mode: mode,
      pointerSensitivity: try number(pointerSensitivity),
      stickRadius: try number(stickRadius),
      deadzone: try number(deadzone)
    )
    guard mapping.pointerSensitivity.isFinite,
      RemappingTouchMapping.pointerSensitivityRange.contains(mapping.pointerSensitivity),
      mapping.stickRadius.isFinite,
      RemappingTouchMapping.stickRadiusRange.contains(mapping.stickRadius),
      mapping.deadzone.isFinite, RemappingTouchMapping.deadzoneRange.contains(mapping.deadzone)
    else { throw RemappingValidationError.invalidTouchMapping(surface) }
    return mapping
  }
}
