#if canImport(SwiftUI)

  import OpenJoystickDriverKit

  /// Why the profile editor ignores edits.
  enum ProfileEditingBlock: Equatable {
    /// A save of this profile runs.
    case saving
    /// Another change of the profile library runs.
    case changeRunning
    /// The list holds the editor while a change or a damaged profile needs attention.
    case onHold

    /// The reason in words.
    var message: String {
      switch self {
      case .saving: return OJDLocalized.string("ui.profiles.editBlockedSaving")
      case .changeRunning: return OJDLocalized.string("ui.profiles.editBlockedChange")
      case .onHold: return OJDLocalized.string("ui.profiles.editBlockedHold")
      }
    }
  }

#endif
