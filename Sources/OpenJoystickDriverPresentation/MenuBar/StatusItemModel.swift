import Foundation
import OpenJoystickDriverKit

/// What one status-item entry does when chosen.
///
/// AppKit renders entries; the coordinator performs actions.
enum StatusItemAction: Equatable {
  /// Suspends the controller with the session token.
  case suspendController(sessionToken: String)
  /// Resumes the controller with the session token.
  case resumeController(sessionToken: String)
  /// Opens the Input Test window for the controller with the session token.
  case testInput(sessionToken: String)
  /// Disconnects the wireless link of the controller with the session token.
  case disconnectWireless(sessionToken: String)
  /// Shows the controller with the session token in the main window.
  case showController(sessionToken: String)
  /// Activates the profile.
  case activateProfile(UUID)
  /// Deactivates the profile.
  case deactivateProfile(UUID)
  /// Opens the main window on the area.
  case showArea(MainWindowArea)
  /// Opens the Access area at the row of the missing permission.
  case showPermission(AccessPermissionRow.Kind)
  /// Starts the service's request listener again and reads the status.
  case startService
  /// Opens the main window on the area it last showed.
  case openWindow
  /// Opens the Settings window.
  case showSettings
  /// Quits the app.
  case quit
}

/// An entry title: a localization key, or text that comes from data such as a profile name.
indirect enum StatusItemTitle: Equatable {
  /// A localization key.
  case key(String)
  /// Text that is shown as is.
  case verbatim(String)
  /// A localization key whose one `%@` takes the text of the title.
  case formatted(String, Self)
}

/// Something that needs the user's action; the menu shows one row for each.
enum StatusItemProblem: Equatable {
  /// The app cannot reach the service.
  case serviceNotRunning
  /// A permission the service needs is missing.
  case missingPermission(AccessPermissionRow.Kind)

  /// The row's title: it names the problem.
  var title: StatusItemTitle {
    switch self {
    case .serviceNotRunning: return .key("ui.extra.problemServiceNotRunning")
    case .missingPermission(let kind):
      return .formatted(
        "ui.extra.problemPermission",
        .key(kind.titleKey)
      )
    }
  }
}

/// One row of the status menu.
///
/// Controller and profile rows are disabled when they do not apply.
struct StatusItemEntry: Equatable {
  /// The entry's identifier, which the UI scripts find the menu item by.
  let id: String
  /// The entry's title.
  let title: StatusItemTitle
  /// Whether the entry can be chosen.
  let isEnabled: Bool
  /// Whether the entry shows a checkmark.
  let isChecked: Bool
  /// Nil for rows that open a submenu, for unavailable rows and for separators.
  let action: StatusItemAction?
  /// The entries of the submenu, or nil when the entry opens none.
  let submenu: [Self]?
  /// Whether the entry is a separator line.
  let isSeparator: Bool
  /// What the entry adds to its title: battery level, profile name, state.
  let details: [StatusItemTitle]

  /// Creates an entry that is enabled and unchecked unless given otherwise.
  init(
    id: String,
    title: StatusItemTitle,
    isEnabled: Bool = true,
    isChecked: Bool = false,
    action: StatusItemAction? = nil,
    submenu: [Self]? = nil,
    details: [StatusItemTitle] = []
  ) {
    self.id = id
    self.title = title
    self.isEnabled = isEnabled
    self.isChecked = isChecked
    self.action = action
    self.submenu = submenu
    self.isSeparator = false
    self.details = details
  }

  /// Creates a separator with the identifier.
  private init(separatorID: String) {
    self.id = separatorID
    self.title = .verbatim("")
    self.isEnabled = false
    self.isChecked = false
    self.action = nil
    self.submenu = nil
    self.isSeparator = true
    self.details = []
  }

  /// Returns a separator with the identifier.
  static func separator(_ id: String) -> Self { Self(separatorID: id) }
}

/// What the status menu needs to know about the service state.
struct StatusItemState: Equatable {
  /// A connected controller in the status menu.
  struct Controller: Equatable {
    /// The session token of the attachment.
    let id: String
    /// The controller's display name.
    let name: String
    /// Whether the controller is suspended, which turns Pause into Resume.
    let isSuspended: Bool
    /// Whether the controller is linked over Bluetooth, from the typed transport.
    let isWireless: Bool
    /// Whether a `Pause` assignment has the controller pass through unmapped.
    var isPaused = false
    /// The battery level as the service reports it, or nil when the controller reports none.
    var battery: String?
    /// The name of the profile in force as the service reports it; nil when it reports none.
    var profileInForce: String?
    /// The name of the app in front that selected the profile in force; nil when none did.
    var profileSelectedBy: String?
    /// The profiles that apply to this controller (same model, and its unit when a profile names
    /// one). ``Profile/isActive`` tells whether the profile is the one active for it.
    var profiles: [Profile] = []
  }

  /// A profile in the status menu.
  struct Profile: Equatable {
    /// The profile's identifier.
    let id: UUID
    /// The profile's name.
    let name: String
    /// Whether the profile is active.
    let isActive: Bool
  }

  /// The problems that need the user's action, most blocking first.
  var problems: [StatusItemProblem]
  /// Connected controllers in inventory order.
  var controllers: [Controller]
  /// Whether the service reported the profile list.
  ///
  /// An empty list claims that no profile exists only when it was reported.
  var profileListRead: Bool
}

/// The fixed status-item layout as data.
enum StatusItemModel {
  /// The address of the page that starts a problem report.
  static let problemReport = "https://github.com/xsyetopz/OpenJoystickDriver/issues/new"
  /// The most profiles one controller's list shows before "More Profiles".
  static let profileListLimit = 10

  /// Returns the entries of the status menu for `state`, from the first controller to Quit.
  static func entries(for state: StatusItemState) -> [StatusItemEntry] {
    let problemRows = state.problems.map { problem -> StatusItemEntry in
      switch problem {
      case .serviceNotRunning:
        return StatusItemEntry(id: "problem.service", title: problem.title, action: .startService)
      case .missingPermission(let kind):
        return StatusItemEntry(
          id: "problem.\(kind.rawValue)",
          title: problem.title,
          action: .showPermission(kind)
        )
      }
    }
    return problemRows + controllerRows(state) + [
      .separator("separator.controllers"),
      StatusItemEntry(
        id: "openWindow",
        title: .key("ui.extra.openWindow"),
        action: .openWindow
      ),
      StatusItemEntry(
        id: "settings",
        title: .key("ui.menu.app.settings"),
        action: .showSettings
      ),
      .separator("separator.window"),
      StatusItemEntry(id: "quit", title: .key("ui.menu.app.quit"), action: .quit),
    ]
  }

  // A state with no controller connected is not a problem, so it keeps the controller symbol.
  static func symbolName(for state: StatusItemState) -> String {
    state.problems.isEmpty ? "gamecontroller" : "exclamationmark.triangle"
  }

  /// The accessibility label of the item: the first problem, else whether a controller is
  /// connected.
  static func accessibilityTitle(for state: StatusItemState) -> StatusItemTitle {
    if let problem = state.problems.first {
      return .formatted("a11y.menuBar.problem", problem.title)
    }
    return .key(state.controllers.isEmpty ? "a11y.menuBar.noController" : "a11y.menuBar.ready")
  }

  /// One row per connected controller, or one unavailable row that says none is connected.
  private static func controllerRows(_ state: StatusItemState) -> [StatusItemEntry] {
    guard !state.controllers.isEmpty else {
      return [
        StatusItemEntry(
          id: "controller.none",
          title: .key(MainMenuModel.noControllerTitleKey),
          isEnabled: false
        )
      ]
    }
    return state.controllers.map { controller in
      let details =
        (controller.battery.map { [StatusItemTitle.verbatim($0)] } ?? [])
        + ((controller.profileInForce ?? controller.profiles.first(where: \.isActive)?.name).map {
          [.verbatim($0)]
        } ?? [])
        + (controller.profileSelectedBy.map {
          [.formatted("ui.extra.profileSelectedByApp", .verbatim($0))]
        } ?? [])
        + (controller.isPaused || controller.isSuspended
          ? [.key("ui.controllers.paused.value")] : [])
      return StatusItemEntry(
        id: "controller.\(controller.id)",
        title: .verbatim(controller.name),
        submenu: controllerActions(controller, profileListRead: state.profileListRead),
        details: details
      )
    }
  }

  /// Returns the items of one controller's submenu: the profile list, pause or resume, test
  /// input, show in window and, for a wireless controller, disconnect.
  private static func controllerActions(
    _ controller: StatusItemState.Controller,
    profileListRead: Bool
  ) -> [StatusItemEntry] {
    let prefix = "controller.\(controller.id)"
    let pause =
      controller.isSuspended
      ? StatusItemEntry(
        id: "\(prefix).resume",
        title: .key("ui.extra.resume"),
        action: .resumeController(sessionToken: controller.id)
      )
      : StatusItemEntry(
        id: "\(prefix).pause",
        title: .key("ui.extra.pause"),
        action: .suspendController(sessionToken: controller.id)
      )
    let disconnect =
      controller.isWireless
      ? [
        StatusItemEntry(
          id: "\(prefix).disconnectWireless",
          title: .key("ui.extra.disconnectWireless"),
          action: .disconnectWireless(sessionToken: controller.id)
        )
      ] : []
    return profileList(controller, prefix: prefix, profileListRead: profileListRead) + [
      .separator("\(prefix).separator"),
      pause,
      StatusItemEntry(
        id: "\(prefix).testInput",
        title: .key("ui.extra.testInput"),
        action: .testInput(sessionToken: controller.id)
      ),
      StatusItemEntry(
        id: "\(prefix).showInWindow",
        title: .key("ui.extra.showInWindow"),
        action: .showController(sessionToken: controller.id)
      ),
    ] + disconnect
  }

  /// The one checkmarked profile list of a controller.
  ///
  /// It shows at most ``profileListLimit`` profiles, the active one among them, then "No Profile",
  /// which is checked while none is active, and "More Profiles" when profiles were left out.
  private static func profileList(
    _ controller: StatusItemState.Controller,
    prefix: String,
    profileListRead: Bool
  ) -> [StatusItemEntry] {
    guard profileListRead else {
      return [
        StatusItemEntry(
          id: "\(prefix).profile.none",
          title: .key(MainMenuModel.emptyActivateProfileTitleKey(profileListRead: false)),
          isEnabled: false
        )
      ]
    }
    let active = controller.profiles.first(where: \.isActive)
    var shown = Array(controller.profiles.prefix(profileListLimit))
    if let active, !shown.contains(active) { shown[shown.count - 1] = active }
    let rows = shown.map {
      StatusItemEntry(
        id: "\(prefix).profile.\($0.id.uuidString)",
        title: .verbatim($0.name),
        isEnabled: !$0.isActive,
        isChecked: $0.isActive,
        action: $0.isActive ? nil : .activateProfile($0.id)
      )
    }
    let none = StatusItemEntry(
      id: "\(prefix).profile.none",
      title: .key("ui.extra.noProfile"),
      isEnabled: active != nil,
      isChecked: active == nil,
      action: active.map { .deactivateProfile($0.id) }
    )
    let more =
      controller.profiles.count > profileListLimit
      ? [
        StatusItemEntry(
          id: "\(prefix).profile.more",
          title: .key("ui.extra.moreProfiles"),
          action: .showArea(.profiles)
        )
      ] : []
    return rows + [none] + more
  }
}
