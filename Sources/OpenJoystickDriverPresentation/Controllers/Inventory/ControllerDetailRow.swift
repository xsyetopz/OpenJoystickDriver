/// The rows of the controller detail, with the audit IDs C05 to C16 and C30 to C32.
enum ControllerDetailRow: InterfaceRow {
  /// C05: the name and the connection.
  case header
  /// C06 (Simple part), C15: the active profile, the input health and the suspended session.
  case state
  /// C06 (Advanced part): Publication, Serving route and Protocol.
  case servingFacts
  /// C06 (Advanced part), C16: the serial number.
  case serialNumber
  /// C07: Open Input Test, the button of a working controller's state.
  case inputTest
  /// C08: Handled by.
  case servedBy
  /// C09, C10: the virtual gamepad kind and its scope.
  case virtualGamepadKind
  /// C30: the held by Apple's driver section with its Claim button.
  case appleDriverHold
  /// C31: the Export Mapping and Launch rows.
  case mappingActions
  /// C11, C32: the stick dead zone and the calibration readouts of the sticks and triggers.
  case stickDeadzone
  /// C12: the Tuning disclosure.
  case tuning
  /// C13: the Advanced disclosure with the identifiers.
  case identifiers
  /// C14: Capture Packets, Draft Record and Draft Record from SDL.
  case developerActions

  var auditIDs: [String] {
    switch self {
    case .header: return ["C05"]
    case .state: return ["C06", "C15"]
    case .servingFacts: return ["C06"]
    case .serialNumber: return ["C06", "C16"]
    case .inputTest: return ["C07"]
    case .servedBy: return ["C08"]
    case .virtualGamepadKind: return ["C09", "C10"]
    case .appleDriverHold: return ["C30"]
    case .mappingActions: return ["C31"]
    case .stickDeadzone: return ["C11", "C32"]
    case .tuning: return ["C12"]
    case .identifiers: return ["C13"]
    case .developerActions: return ["C14"]
    }
  }

  var rowLevel: InterfaceRowLevel {
    switch self {
    case .header, .state, .inputTest: return .simple
    case .servingFacts, .serialNumber, .servedBy, .virtualGamepadKind, .stickDeadzone, .tuning,
      .identifiers, .appleDriverHold, .mappingActions:
      return .advanced
    case .developerActions: return .developer
    }
  }
}
