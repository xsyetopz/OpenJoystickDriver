/// The rows of the Profiles area, with the audit IDs C18 to C20 and S08 to S24.
///
/// The audit puts creating and editing a profile in Simple, and the tuning in Advanced. The app
/// chooser (C20) is a Simple row: the "One application" target needs it at every level.
enum ProfilesRow: InterfaceRow {
  /// C18: the profile list and the editor.
  case list
  /// C20: the app chooser of the "One application" target.
  case appChooser
  /// S08, S09: the New profile and Duplicate profile sheets.
  case creationSheets
  /// S10, S11, S12: the profile details, binding behavior and macro editor sheets.
  case editingSheets
  /// S14, S15, S16, S17: the capture, chord, sequence and layer sheets.
  case bindingSheets
  /// S24: the Pair Joy-Cons sheet.
  case joyConPair
  /// C19: the virtual output and exclusive input pickers.
  case outputPolicy
  /// S13: the Adjust button of an axis assignment and its dead zone, gain and threshold sheet.
  case axisAdjustment
  /// S18, S19, S20: the stick, trigger and touch modes.
  case analogModes
  /// S21: the pointer speed.
  case pointerSpeed
  /// S22: the motion tuning.
  case motion
  /// S23: the regions.
  case regions

  var auditIDs: [String] {
    switch self {
    case .list: return ["C18"]
    case .appChooser: return ["C20"]
    case .creationSheets: return ["S08", "S09"]
    case .editingSheets: return ["S10", "S11", "S12"]
    case .bindingSheets: return ["S14", "S15", "S16", "S17"]
    case .joyConPair: return ["S24"]
    case .outputPolicy: return ["C19"]
    case .axisAdjustment: return ["S13"]
    case .analogModes: return ["S18", "S19", "S20"]
    case .pointerSpeed: return ["S21"]
    case .motion: return ["S22"]
    case .regions: return ["S23"]
    }
  }

  var rowLevel: InterfaceRowLevel {
    switch self {
    case .list, .appChooser, .creationSheets, .editingSheets, .bindingSheets, .joyConPair:
      return .simple
    case .outputPolicy, .axisAdjustment, .analogModes, .pointerSpeed, .motion, .regions:
      return .advanced
    }
  }
}
