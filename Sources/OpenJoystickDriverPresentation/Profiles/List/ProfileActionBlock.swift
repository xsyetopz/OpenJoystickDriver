#if canImport(SwiftUI)

  import OpenJoystickDriverKit

  /// Why the Profiles screen refuses creating, importing, deleting and the like.
  enum ProfileActionBlock: Equatable {
    /// A profile change runs, or the editor owns one.
    case changeRunning
    /// A repair of the library runs.
    case recoveryRunning
    /// The library lists damaged profiles or is unusable.
    case needsRecovery

    /// The reason in words.
    var message: String {
      switch self {
      case .changeRunning: return OJDLocalized.string("ui.profiles.actionBlockedChange")
      case .recoveryRunning: return OJDLocalized.string("ui.profiles.actionBlockedRecovery")
      case .needsRecovery: return OJDLocalized.string("ui.profiles.actionBlockedDamaged")
      }
    }
  }

#endif
