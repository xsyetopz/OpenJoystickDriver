import Foundation
import OpenJoystickDriverKit

struct ProfileTouchDraft {
  let id: UUID
  let surface: RemappingTouchSurface
  var enabled: Bool
  var mode: RemappingTouchMode
  var pointerSensitivity: String
  var stickRadius: String
  var deadzone: String

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
      mapping.deadzone.isFinite,
      RemappingTouchMapping.deadzoneRange.contains(mapping.deadzone)
    else { throw RemappingValidationError.invalidTouchMapping(surface) }
    return mapping
  }
}
