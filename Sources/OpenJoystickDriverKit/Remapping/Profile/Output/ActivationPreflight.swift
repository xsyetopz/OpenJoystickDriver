import Foundation

extension RemappingPermission {
  /// The name of the permission in the language of the user.
  public var localizedName: String {
    switch self {
    case .postEvent: Localization().string("platform.macos.term.postEventAccess")
    case .automation: Localization().string("platform.macos.term.automationAccess")
    }
  }
}

/// What a person sees before a profile activates: the permissions its actions need, the ones that
/// are missing, and the actions that need their confirmation.
public struct RemappingActivationPreflight: Equatable, Sendable {
  /// The permissions that the actions of the profile need.
  public let neededPermissions: [RemappingPermission]
  /// The needed permissions that are not granted.
  ///
  /// Only Post Event access can be read before an action runs; Automation access is decided per
  /// application when an Apple Event is sent.
  public let missingPermissions: [RemappingPermission]
  /// The actions that open an application or URL, run a shortcut or type text, one line each.
  public let launchedActions: [String]

  /// Creates the preflight of `profile`; a nil `postEventAccess` is an access that is not known,
  /// which is not reported as missing.
  public init(profile: RemappingProfile, postEventAccess: RemappingPostEventAccessState?) {
    neededPermissions = profile.neededPermissions
    missingPermissions = neededPermissions.filter {
      $0 == .postEvent && postEventAccess == .notAuthorized
    }
    launchedActions = profile.launchedActions
  }

  /// Whether the activation needs the confirmation of the person.
  public var needsConfirmation: Bool { !launchedActions.isEmpty }

  /// Whether there is anything to show before the activation.
  public var hasNotice: Bool { needsConfirmation || !missingPermissions.isEmpty }

  /// The localized names of the missing permissions, joined; nil when none is missing.
  public var missingPermissionsText: String? {
    guard !missingPermissions.isEmpty else { return nil }
    let names = missingPermissions.map(\.localizedName).joined(separator: ", ")
    return Localization().string("status.missingPermissions", names)
  }

  /// The message of the activation alert: the actions and the missing permissions.
  public var alertMessage: String {
    var parts: [String] = []
    if needsConfirmation {
      let lines = launchedActions.joined(separator: "\n")
      parts.append(Localization().string("ui.profiles.activationActions", lines))
    }
    if let missing = missingPermissionsText { parts.append(missing) }
    return parts.joined(separator: "\n\n")
  }
}
