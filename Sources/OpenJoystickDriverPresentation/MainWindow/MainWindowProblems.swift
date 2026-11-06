import Foundation
import OpenJoystickDriverKit

/// Something that stops controllers from working, shown in the main window's problem banner while
/// it lasts.
///
/// A healthy app has none, and the banner is then absent.
enum MainWindowProblem: Equatable, Sendable, Identifiable {
  /// The application service did not answer; the message says why.
  case serviceUnavailable(String)
  /// The service's request listener stopped; the message gives its code and error number.
  case listenerStopped(String)
  /// The Xbox USB driver extension is not active.
  case driver(SystemExtensionSetupState)
  /// macOS has not granted a permission the service needs.
  case accessMissing
  /// The service's change notifications are unavailable for the reason, so the app reads the
  /// service repeatedly instead.
  case liveUpdatesPolling(ControllerLiveUpdateFailure)

  /// The identity of the banner row; the two service problems share one row.
  var id: String {
    switch self {
    case .serviceUnavailable, .listenerStopped: return "service"
    case .driver: return "driver"
    case .accessMissing: return "access"
    case .liveUpdatesPolling: return "liveUpdates"
    }
  }

  /// The localization key of the banner row's title.
  var titleKey: String {
    switch self {
    case .serviceUnavailable, .listenerStopped: return "ui.banner.service.title"
    case .driver: return "ui.setup.driverTitle"
    case .accessMissing: return "ui.banner.access.title"
    case .liveUpdatesPolling: return "ui.banner.liveUpdates.title"
    }
  }

  /// The localization key of the detail, or nil when the detail is the service's own message.
  var detailKey: String? {
    switch self {
    case .serviceUnavailable, .listenerStopped: return nil
    case .liveUpdatesPolling(let failure): return failure.detailKey
    case .driver(let state):
      switch state {
      case .missingEmbedded: return "ui.setup.missingDetail"
      case .invalid: return "ui.setup.invalidDetail"
      case .awaitingApproval: return "platform.macos.ui.setup.approvalDetail"
      case .needsActivation, .replacementNeeded, .failed: return "ui.setup.repairDetail"
      case .checking, .active:
        preconditionFailure("A driver problem is never made for \(state)")
      }
    case .accessMissing: return "platform.macos.ui.banner.access.detail"
    }
  }

  /// The button of the banner row, or nil when the row offers no fix.
  var action: MainWindowProblemAction? {
    switch self {
    case .serviceUnavailable: return .retryService
    case .listenerStopped: return .restartListener
    case .driver(let state):
      switch state {
      case .awaitingApproval: return .openDriverApproval
      case .needsActivation, .replacementNeeded, .failed, .invalid: return .repairDriver
      case .missingEmbedded: return nil
      case .checking, .active:
        preconditionFailure("A driver problem is never made for \(state)")
      }
    case .accessMissing: return .showAccess
    case .liveUpdatesPolling: return nil
    }
  }

  /// Whether the problem stops every controller.
  ///
  /// The other problems need the user's attention.
  var isFailure: Bool {
    switch self {
    case .serviceUnavailable, .listenerStopped: return true
    case .driver(let state): return state == .missingEmbedded || state == .invalid
    case .accessMissing, .liveUpdatesPolling: return false
    }
  }

  /// Returns the problems of the current state, most blocking first.
  ///
  /// Without the service nothing else can be read, and without the driver Xbox USB controllers
  /// cannot connect.
  static func current(
    permissions: RuntimePermissionLoadState,
    status: RuntimeStatusState,
    driver: SystemExtensionSetupState,
    liveUpdatesFallbackReason: ControllerLiveUpdateFailure?,
    listenerFailure: ServiceListenerFailure?
  ) -> [Self] {
    var problems: [Self] = []
    switch status {
    case .unavailable(let message), .error(let message):
      problems.append(
        listenerFailure == nil ? .serviceUnavailable(message) : .listenerStopped(message)
      )
    case .loading, .available: break
    }
    switch driver {
    case .checking, .active: break
    case .missingEmbedded, .needsActivation, .replacementNeeded, .awaitingApproval, .failed,
      .invalid:
      problems.append(.driver(driver))
    }
    if AccessReadiness.hasMissingPermission(permissionState: permissions, statusState: status) {
      problems.append(.accessMissing)
    }
    if let failure = liveUpdatesFallbackReason { problems.append(.liveUpdatesPolling(failure)) }
    return problems
  }
}

/// The fix that a banner row's button runs.
enum MainWindowProblemAction: Equatable, Sendable {
  /// Reads the service again.
  case retryService
  /// Restarts the service's request listener.
  case restartListener
  /// Opens System Settings to approve the driver extension.
  case openDriverApproval
  /// Repairs the driver extension.
  case repairDriver
  /// Shows the Access area.
  case showAccess

  /// The localization key of the button title.
  var titleKey: String {
    switch self {
    case .retryService: return "action.tryAgain"
    case .restartListener: return "status.listenerFailure.restart"
    case .openDriverApproval: return "platform.macos.ui.setup.openSystemSettings"
    case .repairDriver: return "ui.setup.repairDriver"
    case .showAccess: return "ui.extra.grantAccess"
    }
  }
}
