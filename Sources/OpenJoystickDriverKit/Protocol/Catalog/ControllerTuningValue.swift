import Foundation

/// One tuning key with its effective value and the layer that set it. `value` is nil while only
/// the driver default applies, which the driver picks itself.
public struct ControllerTuningValue: Equatable, Sendable {
  /// The tuning key.
  ///
  /// The tuning key. The value of the key; nil when no layer sets it.
  public let key: ControllerTuning.Key
  /// The layer that sets the value.
  ///
  /// The value of the key; nil when no layer sets it.
  public let value: Double?
  /// Creates a value of a tuning key from the layer that sets it.
  ///
  /// The layer that sets the value.
  public let layer: ControllerRecordLayer

  /// Creates a value of a tuning key from the layer that sets it.
  public init(key: ControllerTuning.Key, value: Double?, layer: ControllerRecordLayer) {
    self.key = key
    self.value = value
    self.layer = layer
  }

  /// Every key with its value in `tuning` and its entry in `layers`, by the key's JSON name; a
  /// key no layer names is the driver's.
  static func values(
    of tuning: ControllerTuning,
    layers: [String: ControllerRecordLayer]
  ) -> [Self] {
    ControllerTuning.Key.allCases.map { key in
      Self(
        key: key,
        value: tuning.text(of: key).flatMap(Double.init),
        layer: layers[key.rawValue] ?? .driver
      )
    }
  }
}

extension ControllerRecord {
  /// The source `ojd controller show` names for `server` when no record matches the model.
  public static let defaultServerSource = "Default"

  /// The source `ojd controller show` names for `server` when the system cannot serve the
  /// controller, so its serving route belongs to OJD whatever the record says.
  public static let routeServerSource = "Route"

  /// The record layer that sets `server`: `Bundled`, `Package` or `User`; `Default` when no layer
  /// sets it. `all.patch.json` holds only tuning, so `Global` never sets it.
  public var serverSource: String {
    fieldLayers["server"]?.rawValue ?? Self.defaultServerSource
  }

  /// Every tuning key with its effective value and the layer it comes from.
  public var tuningValues: [ControllerTuningValue] {
    ControllerTuningValue.values(of: tuning, layers: tuningLayers)
  }
}

extension ControllerRecordSet {
  /// Every tuning key with the value `all.patch.json` gives it, or the driver default.
  public var defaultTuningValues: [ControllerTuningValue] {
    let tuning = defaults?.tuning ?? .none
    let layers = Dictionary(
      uniqueKeysWithValues: tuning.setKeys.map { ($0.rawValue, ControllerRecordLayer.global) }
    )
    return ControllerTuningValue.values(of: tuning, layers: layers)
  }
}
