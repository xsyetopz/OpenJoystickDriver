import Foundation

extension HIDUsageMap {
  /// The `input.hidUsageMap` member of a record, the form ``ControllerRecordDocument/UsageMap``
  /// reads.
  var json: [String: Any] {
    var map: [String: Any] = ["usages": entries.map(\.json)]
    if let reportID { map["reportID"] = Int(reportID) }
    return map
  }
}

extension HIDUsageMap.Entry {
  /// The entry as a `usages` member of a record.
  fileprivate var json: [String: Any] {
    var entry: [String: Any] = ["page": usage.usagePage, "usage": usage.usage]
    switch binding {
    case .button(let control):
      entry["kind"] = "Button"
      entry["control"] = control.rawValue
    case .axis(let axis):
      entry["kind"] = "Axis"
      entry["control"] = axis.control.rawValue
      if axis.isInverted { entry["inverted"] = true }
      entry["range"] = axis.range.map(Self.rangeJSON)
      entry["deadZone"] = axis.deadZone.map { Double($0) }
    case .hat(let hat):
      entry["kind"] = "Hat"
      entry["range"] = hat.range.map(Self.rangeJSON)
    case .halfAxis(let axis):
      entry["kind"] = "HalfAxis"
      entry["half"] = axis.half.rawValue
      entry["control"] = axis.control.rawValue
      if axis.isInverted { entry["inverted"] = true }
    case .axisDpad(let half):
      entry["kind"] = "AxisDpad"
      entry.merge(Self.thresholdJSON(half)) { $1 }
    case .axisButton(let half):
      entry["kind"] = "AxisButton"
      entry.merge(Self.thresholdJSON(half)) { $1 }
    case .buttonTrigger(let control):
      entry["kind"] = "ButtonTrigger"
      entry["control"] = control.rawValue
    }
    return entry
  }

  /// A `range` member.
  private static func rangeJSON(_ range: ClosedRange<Int>) -> [String: Int] {
    ["min": range.lowerBound, "max": range.upperBound]
  }

  /// The `half`, `control` and `threshold` members of a threshold binding.
  private static func thresholdJSON(_ half: HIDUsageMap.HalfThreshold) -> [String: Any] {
    [
      "half": half.half.rawValue, "control": half.control.rawValue,
      "threshold": Double(half.threshold),
    ]
  }
}
