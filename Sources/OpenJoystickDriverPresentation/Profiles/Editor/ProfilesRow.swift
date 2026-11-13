/// The rows of the Profiles area.
///
/// The audit puts creating and editing a profile in Simple, and the tuning in Advanced. The app
/// chooser is a Simple row: the "One application" target needs it at every level.
enum ProfilesRow: InterfaceRow {
  /// The profile list and the editor.
  case list
  /// The app chooser of the "One application" target.
  case appChooser
  /// The New profile and Duplicate profile sheets.
  case creationSheets
  /// The profile details, binding behavior and macro editor sheets.
  case editingSheets
  /// The capture, chord, sequence and layer sheets.
  case bindingSheets
  /// The Pair Joy-Cons sheet.
  case joyConPair
  /// The virtual output and exclusive input pickers.
  case outputPolicy
  /// The Adjust button of an axis assignment and its dead zone, gain and threshold sheet.
  case axisAdjustment
  /// The stick, trigger and touch modes.
  case analogModes
  /// The pointer speed.
  case pointerSpeed
  /// The motion tuning.
  case motion
  /// The regions.
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
