import Foundation
import OpenJoystickDriverKit

/// What the app offers beside a check that is not a pass.
enum ActivityCheckFix: Equatable {
  /// Request the Input Read permission.
  case requestInputRead
  /// Request the Input Inject permission.
  case requestInputInject
  /// Open System Settings to approve the driver extension.
  case approveDriver
  /// Show the Library area.
  case showLibrary

  /// The localization key of the fix button's title.
  var titleKey: String {
    switch self {
    case .requestInputRead, .requestInputInject: return "action.request"
    case .approveDriver: return "platform.macos.ui.setup.openSystemSettings"
    case .showLibrary: return "ui.activity.fix.showLibrary"
    }
  }
}

/// A check's place in the app: its name and the GUI action that fixes it.
///
/// A check without an action says so; its details text still names the fix.
struct ActivityCheckKind: Equatable {
  /// What the app does for a check.
  enum Action: Equatable {
    /// A button that does the fix.
    case fix(ActivityCheckFix)
    /// The app has no action; the details text names the fix.
    case noGUIAction
  }

  /// The check's identifier, as `ojd diagnose` prints it.
  let id: String
  /// The localization key of the check's name.
  let nameKey: String
  /// The GUI action for the check.
  let action: Action

  /// Every check of `ojd diagnose` that the app runs. `runtime-health` is a command-line option
  /// and is not run.
  static let all = [
    Self(
      id: "transport-extension-bundle",
      nameKey: "ui.activity.check.transportExtensionBundle",
      action: .noGUIAction
    ),
    Self(
      id: "transport-extension-registration",
      nameKey: "ui.activity.check.transportExtensionRegistration",
      action: .fix(.approveDriver)
    ),
    Self(id: "service", nameKey: "cli.status.group.labelService", action: .noGUIAction),
    Self(
      id: "input-read",
      nameKey: "platform.macos.term.inputRead",
      action: .fix(.requestInputRead)
    ),
    Self(
      id: "input-inject",
      nameKey: "platform.macos.term.inputInject",
      action: .fix(.requestInputInject)
    ),
    Self(
      id: "virtual-device",
      nameKey: "cli.status.group.labelVirtualDevice",
      action: .noGUIAction
    ),
    Self(id: "controller-records", nameKey: "ui.library.records", action: .fix(.showLibrary)),
    Self(id: "config-files", nameKey: "ui.activity.check.configFiles", action: .noGUIAction),
    Self(id: "usb-access", nameKey: "ui.activity.check.usbAccess", action: .fix(.requestInputRead)),
  ]

  /// Returns the kind of the check with the identifier, or nil when the app does not list it.
  static func kind(of id: String) -> Self? { all.first { $0.id == id } }
}

/// One `ojd diagnose` check as a table row. `detail` is the text the command prints; for a
/// check that is not a pass it names the fix.
struct ActivityCheckRow: Identifiable, Equatable {
  /// The check's identifier.
  let id: String
  /// The check's result.
  let status: DiagnoseStatus
  /// The text that `ojd diagnose` prints for the check.
  let detail: String
  /// The localized name; nil for a check the app does not list, which shows its id.
  let nameKey: String?
  /// The button beside a warning or failure whose fix the app can do.
  let fix: ActivityCheckFix?

  /// Creates the row from a check; a fix shows only for a warning or failure that has one.
  init(_ check: DiagnoseCheck) {
    id = check.id
    status = check.status
    detail = check.detail
    let kind = ActivityCheckKind.kind(of: check.id)
    nameKey = kind?.nameKey
    if check.status == .warn || check.status == .fail, case .fix(let fix)? = kind?.action {
      self.fix = fix
    } else {
      fix = nil
    }
  }

  /// The localization key of the result's name.
  var statusKey: String {
    switch status {
    case .pass: return "ui.activity.status.pass"
    case .warn: return "ui.activity.status.warn"
    case .fail: return "status.failed"
    case .skip: return "ui.activity.status.skip"
    }
  }

  /// The SF Symbol of the result.
  var symbolName: String {
    switch status {
    case .pass: return "checkmark.circle.fill"
    case .warn: return "exclamationmark.triangle.fill"
    case .fail: return "xmark.octagon.fill"
    case .skip: return "minus.circle"
    }
  }
}

/// The result of running the checks of `ojd diagnose`.
enum ActivityDiagnosticsState: Equatable {
  /// The checks have not run.
  case idle
  /// The checks are running.
  case running
  /// The checks have run; the value holds the rows in order.
  case finished([ActivityCheckRow])
}

/// Runs the checks of `ojd diagnose` for the Activity Diagnostics view.
@MainActor
final class ActivityDiagnosticsModel: ObservableObject {
  /// The state of the run.
  @Published
  private(set) var state = ActivityDiagnosticsState.idle

  /// Runs the checks.
  private let runChecks: @MainActor () async -> [DiagnoseCheck]

  /// Creates the model on `runChecks`.
  init(runChecks: @escaping @MainActor () async -> [DiagnoseCheck]) { self.runChecks = runChecks }

  /// Whether a run is in progress.
  var isRunning: Bool { state == .running }

  /// Runs every check once; a run in progress is not started again.
  func run() async {
    guard !isRunning else { return }
    state = .running
    state = .finished(await runChecks().map(ActivityCheckRow.init))
  }

  /// Runs the checks when none ran yet.
  func runIfNeeded() async {
    guard state == .idle else { return }
    await run()
  }
}
