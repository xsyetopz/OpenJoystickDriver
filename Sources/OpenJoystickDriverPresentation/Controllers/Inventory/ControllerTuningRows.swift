import Foundation
import OpenJoystickDriverKit

/// One effective tuning value of a controller and the layer it comes from.
struct ControllerTuningRow: Equatable, Identifiable {
  /// The key as the record file names it, such as `stickDeadzone`.
  let name: String
  /// The value, or "Not set" while no layer sets one.
  let value: String
  /// The layer that sets the value, such as `user`; nil while only the driver default applies.
  let layer: String?

  /// The key, which names the row.
  var id: String { name }

  /// The value and its layer as the row shows them, such as `0.1 (user)`.
  var text: String { layer.map { "\(value) (\($0))" } ?? value }
}

/// The Tuning section of the Controllers detail, from the same layered record and active profile
/// as `ojd config show --controller`.
enum ControllerTuningRows {
  /// Returns every tuning key of `record` in record-file order, then the inner deadzone of each
  /// stick mapping of the active profile, keyed as `profile get` names it.
  ///
  /// - Parameters:
  ///   - record: The effective record of the controller's model.
  ///   - activeProfile: The profile that is active for the controller, or nil.
  /// - Returns: Every tuning key of `record` in record-file order, then the inner deadzone of each
  ///   stick mapping of the active profile, keyed as `profile get` names it.
  static func rows(
    for record: ControllerRecord,
    activeProfile: RemappingProfile?
  ) -> [ControllerTuningRow] {
    let keys = record.tuningValues.map { entry in
      ControllerTuningRow(
        name: entry.key.rawValue,
        value: entry.value.map(number)
          ?? OJDLocalized.string(
            entry.key.hasDriverValue ? "status.driverDefault" : "status.notSet"
          ),
        layer: entry.value == nil ? nil : CommandLineName.kebab(entry.layer.rawValue)
      )
    }
    let profile = (activeProfile?.stickMappings ?? []).enumerated().map { index, mapping in
      ControllerTuningRow(
        name: "stickMappings.\(index).tuning.innerDeadzone",
        value: number(mapping.tuning.innerDeadzone),
        layer: CommandLineName.kebab(ControllerRecordLayer.profile.rawValue)
      )
    }
    return keys + profile
  }

  /// Returns the number without a fraction when it is whole.
  ///
  /// - Parameter value: The number.
  /// - Returns: The number without a fraction when it is whole.
  private static func number(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
  }
}
