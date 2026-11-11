import OpenJoystickDriverKit

/// A permission `ojd` reports.
///
/// The raw values are the ids in `--json`; the command line and `--plain` rows spell them in
/// lowercase kebab-case, such as `input-read`.
enum PermissionID: String, CaseIterable, Sendable {
  /// Reading input from controllers.
  case inputRead = "InputRead"
  /// Injecting input into other apps.
  case inputInject = "InputInject"
  /// Claiming USB controllers through the DriverKit extension.
  case usbTransport = "USBTransport"
  /// Posting events to the system, which some profile outputs need.
  case postEvent = "PostEvent"

  /// The id on the command line and in `--plain` rows.
  var commandLineName: String { CommandLineName.kebab(rawValue) }

  /// The macOS privacy permissions that `ojd permission request` can ask for.
  static let requestable: [Self] = [.inputRead, .inputInject]

  /// The English name and purpose in `--json`, which are never localized.
  private var inventoryEntry: OJDPermissionRequirement {
    switch self {
    case .inputRead: .inputRead
    case .inputInject: .inputInject
    case .usbTransport: .usbTransport
    case .postEvent: .postEvent
    }
  }

  /// The English name in `--json`.
  var name: String { inventoryEntry.name }

  /// The English purpose in `--json`.
  var purpose: String { inventoryEntry.purpose }

  /// The name in the user's language.
  var localizedName: String {
    switch self {
    case .inputRead: CLILocalized.text("platform.macos.cli.permission.group.nameInputRead")
    case .inputInject: CLILocalized.text("platform.macos.cli.permission.group.nameInputInject")
    case .usbTransport: CLILocalized.text("cli.permission.group.nameUsbTransport")
    case .postEvent: CLILocalized.text("cli.permission.group.namePostEvent")
    }
  }

  /// The purpose in the user's language.
  var localizedPurpose: String {
    switch self {
    case .inputRead: CLILocalized.text("cli.permission.group.purposeInputRead")
    case .inputInject: CLILocalized.text("cli.permission.group.purposeInputInject")
    case .usbTransport: CLILocalized.text("platform.macos.cli.permission.group.purposeUsbTransport")
    case .postEvent: CLILocalized.text("cli.permission.group.purposePostEvent")
    }
  }

  /// Where the user allows this permission in System Settings.
  var localizedSettingsPane: String {
    switch self {
    case .inputRead:
      CLILocalized.text(
        "platform.macos.cli.permission.group.paneInputRead"
      )
    case .inputInject, .postEvent:
      CLILocalized.text("platform.macos.cli.permission.group.paneInputInject")
    case .usbTransport:
      CLILocalized.text(
        "platform.macos.cli.permission.group.paneUsbTransport"
      )
    }
  }
}

/// The `ojd permission request --json` result, and the items of `ojd permission list --json`.
struct PermissionReport: Encodable, Equatable {
  /// One permission in the report.
  struct Entry: Encodable, Equatable {
    /// The permission id.
    let id: String
    /// The English name.
    let name: String
    /// The state of the permission.
    let state: PermissionManager.AccessState
    /// The English purpose.
    let purpose: String
    /// Whether the active profile needs the permission.
    ///
    /// Only `PostEvent` has it, and only when the service reported the profiles.
    let requiredByActiveProfile: Bool?

    /// Creates the entry for a permission.
    init(
      _ permission: PermissionID,
      state: PermissionManager.AccessState,
      requiredByActiveProfile: Bool? = nil
    ) {
      id = permission.rawValue
      name = permission.name
      self.state = state
      purpose = permission.purpose
      self.requiredByActiveProfile = requiredByActiveProfile
    }
  }

  /// The permissions in report order.
  let permissions: [Entry]

  /// The Post Event access the service reports, and whether the active profile needs it.
  struct PostEvent: Equatable {
    /// The state of Post Event access.
    let state: PermissionManager.AccessState
    /// Whether the active profile needs Post Event access, when the service reported the profiles.
    let requiredByActiveProfile: Bool?
  }

  /// Creates the report from the permission snapshot and the state of the DriverKit extension.
  ///
  /// - Parameters:
  ///   - snapshot: The state of each permission.
  ///   - extensionStatus: The registration state of the DriverKit extension.
  ///   - postEvent: The Post Event access, or nil for a report that does not cover it.
  init(
    snapshot: PermissionManager.Snapshot,
    extensionStatus: ExtensionStatus,
    postEvent: PostEvent? = nil
  ) {
    let driverState: PermissionManager.AccessState
    switch extensionStatus.registration {
    case .active: driverState = .granted
    case .inactive: driverState = .denied
    case .absent, .unavailable: driverState = .unknown
    }
    var entries = [
      Entry(.inputRead, state: snapshot.inputRead),
      Entry(.inputInject, state: snapshot.inputInject),
      Entry(.usbTransport, state: driverState),
    ]
    if let postEvent {
      entries.append(
        Entry(
          .postEvent,
          state: postEvent.state,
          requiredByActiveProfile: postEvent.requiredByActiveProfile
        )
      )
    }
    permissions = entries
  }

  /// The state of `permission` in the report.
  func state(of permission: PermissionID) -> PermissionManager.AccessState {
    permissions.first { $0.id == permission.rawValue }?.state ?? .unknown
  }

  /// One row per permission: id and state, plus `required` or `not-required` for Post Event
  /// access when the service reported the profiles.
  var plainRows: [[String]] {
    permissions.map { entry in
      var row = [CommandLineName.kebab(entry.id), CommandLineName.kebab(entry.state.rawValue)]
      if let required = entry.requiredByActiveProfile {
        row.append(required ? "required" : "not-required")
      }
      return row
    }
  }
}
