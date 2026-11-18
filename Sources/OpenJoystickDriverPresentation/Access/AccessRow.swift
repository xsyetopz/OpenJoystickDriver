/// The rows of the Access area, with the audit IDs C24 to C27 and S01 to S03.
enum AccessRow: InterfaceRow {
  /// C24: the macOS permission rows.
  case permissions
  /// C25: the local endpoint and WebSocket switches.
  case endpoint
  /// C26: the port field.
  case port
  /// C27: the clients and tokens lists.
  case lists
  /// S01 to S03: the token form, the confirmation and the issued token. Only the Developer rows
  /// above and the Developer toolbar items open them.
  case sheets

  var auditIDs: [String] {
    switch self {
    case .permissions: return ["C24"]
    case .endpoint: return ["C25"]
    case .port: return ["C26"]
    case .lists: return ["C27"]
    case .sheets: return ["S01", "S02", "S03"]
    }
  }

  var rowLevel: InterfaceRowLevel {
    switch self {
    case .permissions: return .simple
    case .endpoint, .port, .lists, .sheets: return .developer
    }
  }
}
