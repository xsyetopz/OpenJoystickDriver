/// The rows of the Library area, with the audit IDs C21 to C23 and S04; the audit puts each in
/// Advanced (records and patches).
enum LibraryRow: InterfaceRow {
  /// C21: the list of records and mods.
  case list
  /// C22: the Installed and Built-in switch.
  case scopeSwitch
  /// C23: the detail of the selected record or mod.
  case detail
  /// S04: the confirmation sheet, which only the Advanced toolbar items open.
  case confirmation

  var auditIDs: [String] {
    switch self {
    case .list: return ["C21"]
    case .scopeSwitch: return ["C22"]
    case .detail: return ["C23"]
    case .confirmation: return ["S04"]
    }
  }

  var rowLevel: InterfaceRowLevel { .advanced }
}
