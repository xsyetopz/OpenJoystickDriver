/// The rows of Test Input, with the audit IDs I01 to I07; the audit puts each in Simple.
enum InputTestRow: InterfaceRow {
  /// I01: the status row.
  case status
  /// I02: the control diagram.
  case controlDiagram
  /// I03: the Refresh button.
  case refresh
  /// I04, I05: the rumble section.
  case rumble
  /// I06, I07: the player indicator, color and brightness.
  case lighting

  var auditIDs: [String] {
    switch self {
    case .status: return ["I01"]
    case .controlDiagram: return ["I02"]
    case .refresh: return ["I03"]
    case .rumble: return ["I04", "I05"]
    case .lighting: return ["I06", "I07"]
    }
  }

  var rowLevel: InterfaceRowLevel { .simple }
}
