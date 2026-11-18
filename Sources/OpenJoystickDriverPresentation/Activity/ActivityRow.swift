/// The rows of the Activity area, with the audit IDs C28, C29 and S05; the audit puts each in
/// Advanced.
enum ActivityRow: InterfaceRow {
  /// C28: the activity log.
  case log
  /// C29: the diagnostics.
  case diagnostics
  /// S05: the Explain Error Code sheet.
  case explainErrorCode

  var auditIDs: [String] {
    switch self {
    case .log: return ["C28"]
    case .diagnostics: return ["C29"]
    case .explainErrorCode: return ["S05"]
    }
  }

  var rowLevel: InterfaceRowLevel { .advanced }
}
