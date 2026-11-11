import Foundation

/// How one permission reads in the Access area: its text, its tone and whether it can be acted on.
struct AccessReadinessStatus: Equatable {
  /// The text that the row shows, such as Allowed or Needs attention.
  let value: String
  /// The color role of the text.
  let tone: SemanticTone
  /// Whether the row offers a button for it.
  let isActionable: Bool
}

extension AccessReadinessStatus {
  /// Whether the permission is missing or needs a change in System Settings.
  ///
  /// A permission that is allowed, not needed or still being checked has nothing to act on.
  var isMissing: Bool { isActionable && tone == .caution }
}

/// One permission row of the Access form.
struct AccessPermissionRow: Equatable, Identifiable {
  /// The permission that a row stands for.
  enum Kind: String, CaseIterable {
    /// Reading input from controllers.
    case inputRead
    /// Injecting input into the Mac.
    case inputInject
    /// Posting keyboard and pointer events.
    case postEvent
    /// Posting notifications.
    case notification

    /// The localization key of the permission's name.
    var titleKey: String {
      switch self {
      case .inputRead: return "platform.macos.term.inputRead"
      case .inputInject: return "platform.macos.term.inputInject"
      case .postEvent: return "term.keyboardPointer"
      case .notification: return "ui.settings.notifications.notifications"
      }
    }
  }

  /// The permission.
  let kind: Kind
  /// How the permission reads.
  let status: AccessReadinessStatus
  /// Whether macOS has not been asked yet, so the button asks instead of opening System Settings.
  var needsRequest = false

  /// The row's identity, which is its kind.
  var id: String { kind.rawValue }

  /// The localization key of the row's title.
  var titleKey: String { kind.titleKey }

  /// The button of a missing permission; nil while nothing is missing.
  var actionTitleKey: String? {
    guard status.isMissing else { return nil }
    return needsRequest ? "action.request" : "platform.macos.ui.setup.openSystemSettings"
  }
}

/// The macOS permissions the app and its service need, as the Access area shows them.
struct AccessReadiness {
  /// The app's own reading of the permissions.
  let permissionState: RuntimePermissionLoadState
  /// The service status, which holds the permissions as the service sees them.
  let statusState: RuntimeStatusState
  /// Whether the app may post notifications.
  let notificationState: RuntimeNotificationAuthorizationState
  /// The alert style and sound setting of the notifications.
  let notificationSettings: RuntimeNotificationSettings

  /// How the Input Read permission reads.
  var inputRead: AccessReadinessStatus { permissionStatus(for: permissionSummary?.inputRead) }

  /// How the Input Inject permission reads.
  var inputInject: AccessReadinessStatus { permissionStatus(for: permissionSummary?.inputInject) }

  /// How the Post Event permission reads: not needed when the active profile does not require it.
  var postEvent: AccessReadinessStatus {
    guard case .available(let status) = statusState,
      let requiresPostEventAccess = status.requiresPostEventAccess
    else { return Self.checking(isActionable: true) }
    guard requiresPostEventAccess else {
      return AccessReadinessStatus(
        value: OJDLocalized.string("status.notNeeded"),
        tone: .neutral,
        isActionable: false
      )
    }
    switch status.postEventAccess {
    case .granted: return Self.allowed
    case .notAuthorized: return Self.needsAttention
    case nil: return Self.checking(isActionable: true)
    }
  }

  /// How the notification permission reads.
  ///
  /// Notifications that are allowed but without banners or sounds need attention.
  var notification: AccessReadinessStatus {
    switch notificationState {
    case .checking: return Self.checking(isActionable: false)
    case .allowed:
      if notificationSettings.alertStyle == .none {
        return AccessReadinessStatus(
          value: OJDLocalized.string("ui.settings.notifications.notificationBannersOff"),
          tone: .caution,
          isActionable: true
        )
      }
      if notificationSettings.soundsEnabled == false {
        return AccessReadinessStatus(
          value: OJDLocalized.string("ui.settings.notifications.notificationSoundOff"),
          tone: .caution,
          isActionable: true
        )
      }
      return Self.allowed
    case .notDetermined:
      return AccessReadinessStatus(
        value: OJDLocalized.string("status.notRequested"),
        tone: .caution,
        isActionable: true
      )
    case .denied: return Self.needsAttention
    }
  }

  /// The rows to show, in order.
  ///
  /// A permission the app does not need is left out.
  var rows: [AccessPermissionRow] {
    var rows = [
      AccessPermissionRow(kind: .inputRead, status: inputRead),
      AccessPermissionRow(kind: .inputInject, status: inputInject),
    ]
    if !postEventIsNotNeeded {
      rows.append(AccessPermissionRow(kind: .postEvent, status: postEvent))
    }
    rows.append(
      AccessPermissionRow(
        kind: .notification,
        status: notification,
        needsRequest: notificationState == .notDetermined
      )
    )
    return rows
  }

  /// Whether the service reports that the active profile needs no Post Event access.
  private var postEventIsNotNeeded: Bool {
    guard case .available(let status) = statusState else { return false }
    return status.requiresPostEventAccess == false
  }

  /// Whether Post Event access must still be requested: the active profile requires it and the
  /// service has not reported it granted.
  static func postEventAccessNeedsRequest(in status: RuntimeStatusPresentation) -> Bool {
    status.requiresPostEventAccess == true && status.postEventAccess != .granted
  }

  /// The permissions the service needs that are missing: those of the Input Read, Input Inject and
  /// Post Event cards that read Needs attention. The rule is the cards' own, so the status item,
  /// the problem banner and the Access area agree:
  /// - Permissions being read or requested, or not read yet, show Checking and are not missing.
  /// - A permission denied or never requested is missing.
  /// - Post Event access counts only when the active profile requires it and it is not
  ///   authorized.
  /// - A failed permission read shows Needs attention, so the user can retry by granting.
  /// A notification setting never counts.
  static func missingPermissions(
    permissionState: RuntimePermissionLoadState,
    statusState: RuntimeStatusState
  ) -> [AccessPermissionRow.Kind] {
    let readiness = Self(
      permissionState: permissionState,
      statusState: statusState,
      notificationState: .checking,
      notificationSettings: .authorizationOnly(.checking)
    )
    let cards: [(AccessPermissionRow.Kind, AccessReadinessStatus)] = [
      (.inputRead, readiness.inputRead), (.inputInject, readiness.inputInject),
      (.postEvent, readiness.postEvent),
    ]
    return cards.filter { $0.1.tone == .caution }.map(\.0)
  }

  /// Whether a permission the service needs is missing.
  static func hasMissingPermission(
    permissionState: RuntimePermissionLoadState,
    statusState: RuntimeStatusState
  ) -> Bool {
    !missingPermissions(permissionState: permissionState, statusState: statusState).isEmpty
  }

  /// The four values in row order, for the accessibility value of the group.
  var summaryValue: String {
    [inputRead.value, inputInject.value, postEvent.value, notification.value].joined(
      separator: ", "
    )
  }

  /// Input permissions take effect in a new process, so the app offers a restart while one is
  /// missing.
  var needsRestart: Bool {
    guard let permissionSummary else { return false }
    return permissionSummary.inputRead != .granted || permissionSummary.inputInject != .granted
  }

  /// The permissions as read: the app's own reading, or the service status when the app has not
  /// read them.
  ///
  /// While a read or request is running, or after it failed, the status holds a placeholder, so
  /// there is no reading.
  private var permissionSummary: RuntimePermissionSummary? {
    switch permissionState {
    case .available(let permissions): return permissions
    case .unavailable:
      if case .available(let status) = statusState { return status.permissions }
      return nil
    case .loading, .requesting, .error: return nil
    }
  }

  /// Returns how a permission state reads, or Checking while the permission is being read.
  private func permissionStatus(for state: RuntimePermissionState?) -> AccessReadinessStatus {
    switch state {
    case .granted: return Self.allowed
    case .denied, .unknown: return Self.needsAttention
    case nil:
      switch permissionState {
      case .loading, .requesting, .unavailable: return Self.checking(isActionable: true)
      case .available, .error: return Self.needsAttention
      }
    }
  }

  /// The status of an allowed permission.
  private static var allowed: AccessReadinessStatus {
    AccessReadinessStatus(
      value: OJDLocalized.string("status.allowed"),
      tone: .positive,
      isActionable: false
    )
  }

  /// The status of a permission that needs attention.
  private static var needsAttention: AccessReadinessStatus {
    AccessReadinessStatus(
      value: OJDLocalized.string("status.needsAttention"),
      tone: .caution,
      isActionable: true
    )
  }

  /// The status of a permission that is being checked.
  private static func checking(isActionable: Bool) -> AccessReadinessStatus {
    AccessReadinessStatus(
      value: OJDLocalized.string("status.checking"),
      tone: .neutral,
      isActionable: isActionable
    )
  }
}
