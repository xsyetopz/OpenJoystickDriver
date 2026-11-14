import Foundation
import OpenJoystickDriverKit

/// Something that stops controllers from working, shown in the main window's problem banner while
/// it lasts.
///
/// A healthy app has none, and the banner is then absent.
enum MainWindowProblem: Equatable, Sendable, Identifiable {
  /// The service is in a state that needs attention; the message is the service's own, and empty
  /// when it gave none.
  case service(ServiceReadiness, String)
  /// The Xbox USB driver extension is not active; the names are those of the connected
  /// controllers whose route is the extension.
  case driver(SystemExtensionSetupState, controllers: [String])
  /// macOS has not granted a permission the service needs.
  case accessMissing
  /// The service's change notifications are unavailable for the reason, so the app reads the
  /// service repeatedly instead.
  case liveUpdatesPolling(ControllerLiveUpdateFailure)
  /// The service cannot read the stored virtual HID profile overrides; the message says why. No
  /// single control started it, so it is not shown beside the override pop-up.
  case virtualProfileStore(String)

  /// The identity of the banner row; every service problem shares one row.
  var id: String {
    switch self {
    case .service: return "service"
    case .driver: return "driver"
    case .accessMissing: return "access"
    case .liveUpdatesPolling: return "liveUpdates"
    case .virtualProfileStore: return "virtualProfileStore"
    }
  }

  /// The localization key of the banner row's title.
  var titleKey: String {
    switch self {
    case .service(let readiness, _): return readiness.messageKey
    case .driver: return "ui.banner.driver.title"
    case .accessMissing: return "ui.banner.access.title"
    case .liveUpdatesPolling: return "ui.banner.liveUpdates.title"
    case .virtualProfileStore: return "ui.virtualProfile.title"
    }
  }

  /// The banner row's title; the driver problem names its controllers.
  var title: String {
    guard case .driver(_, let controllers) = self else { return OJDLocalized.string(titleKey) }
    return OJDLocalized.formatted(titleKey, ListFormatter.localizedString(byJoining: controllers))
  }

  /// The localization key of the detail, or nil when the detail is the service's own message.
  var detailKey: String? {
    switch self {
    case .service, .virtualProfileStore: return nil
    case .liveUpdatesPolling(let failure): return failure.detailKey
    case .driver(let state, _):
      switch state {
      case .missingEmbedded: return "ui.setup.missingDetail"
      case .invalid: return "ui.setup.invalidDetail"
      case .unavailable: return "ui.setup.unavailableDetail"
      case .running: return "ui.setup.runningDetail"
      case .needsApproval: return "platform.macos.ui.setup.approvalDetail"
      case .cancelled: return "ui.setup.cancelledDetail"
      case .timedOut: return "ui.setup.timedOutDetail"
      case .failed: return "ui.setup.failedDetail"
      case .needsActivation, .replacementNeeded: return "ui.setup.repairDetail"
      case .checking, .active:
        preconditionFailure("A driver problem is never made for \(state)")
      }
    case .accessMissing: return "platform.macos.ui.banner.access.detail"
    }
  }

  /// The button of the banner row, or nil when the row offers no fix.
  var action: MainWindowProblemAction? {
    switch self {
    case .service(let readiness, _):
      switch readiness {
      case .listenerStopped: return .restartListener
      case .versionMismatch, .checking, .running: return nil
      case .stopped, .readFailed, .notInstalled, .needsApproval: return .retryService
      }
    case .driver(let state, _):
      switch state {
      case .needsApproval: return .openDriverApproval
      case .needsActivation, .replacementNeeded, .running, .cancelled, .timedOut, .failed:
        return .repairDriver
      case .missingEmbedded, .invalid, .unavailable: return nil
      case .checking, .active:
        preconditionFailure("A driver problem is never made for \(state)")
      }
    case .accessMissing: return .showAccess
    case .liveUpdatesPolling, .virtualProfileStore: return nil
    }
  }

  /// The localization key of the button title, or nil when the row has no button.
  var actionTitleKey: String? {
    guard let action else { return nil }
    switch self {
    case .driver(.running, _): return "ui.setup.repairRunning"
    case .driver(.failed, _), .driver(.cancelled, _), .driver(.timedOut, _):
      return "action.tryAgain"
    default: return action.titleKey
    }
  }

  /// Whether the button of the row can be pressed; a request that runs disables it.
  var isActionEnabled: Bool {
    guard case .driver(.running, _) = self else { return true }
    return false
  }

  /// Whether the problem stops every controller.
  ///
  /// The other problems need the user's attention.
  var isFailure: Bool {
    switch self {
    case .service(let readiness, _): return readiness.isFailure
    case .driver(let state, _): return state == .missingEmbedded || state == .invalid
    case .accessMissing, .liveUpdatesPolling, .virtualProfileStore: return false
    }
  }

  /// Returns the problems of the current state, most blocking first.
  ///
  /// Without the service nothing else can be read. The driver problem shows only while
  /// `extensionRouteControllers` names a connected controller whose route is the extension.
  static func current(
    permissions: RuntimePermissionLoadState,
    status: RuntimeStatusState,
    driver: SystemExtensionSetupState,
    extensionRouteControllers: [String],
    liveUpdatesFallbackReason: ControllerLiveUpdateFailure?,
    listenerFailure: ServiceListenerFailure?,
    registration: ApplicationServiceRegistrationStatus? = nil
  ) -> [Self] {
    var problems: [Self] = []
    let readiness = ServiceReadiness.resolve(
      ServiceReadinessInput(
        status: status,
        listenerStopped: listenerFailure != nil,
        registration: registration
      )
    )
    if readiness.isProblem {
      switch status {
      case .unavailable(let message), .error(let message):
        problems.append(.service(readiness, message))
      case .loading, .available: problems.append(.service(readiness, ""))
      }
    }
    switch driver {
    case .checking, .active: break
    case .missingEmbedded, .invalid, .unavailable, .needsActivation, .replacementNeeded, .running,
      .needsApproval, .cancelled, .timedOut, .failed:
      if !extensionRouteControllers.isEmpty {
        problems.append(.driver(driver, controllers: extensionRouteControllers))
      }
    }
    if AccessReadiness.hasMissingPermission(permissionState: permissions, statusState: status) {
      problems.append(.accessMissing)
    }
    if let failure = liveUpdatesFallbackReason { problems.append(.liveUpdatesPolling(failure)) }
    if case .available(let presentation) = status {
      problems += presentation.virtualHIDProfileOverrideStoreMessages.map {
        .virtualProfileStore($0)
      }
    }
    return problems
  }
}

extension RuntimeStatusState {
  /// The names of the connected controllers whose route is the extension: Apple's driver holds it
  /// and a claim activates the extension, or the extension already owns its USB interface.
  var extensionRouteControllerNames: [String] {
    guard case .available(let presentation) = self else { return [] }
    return presentation.devices.filter {
      $0.isHeldByAppleDriver || $0.physicalOwnership == .extensionOwnedUSB
    }.map(\.name)
  }
}

extension MainWindowProblem {
  /// Whether the banner row's button already offers the fix that a controller's button offers.
  ///
  /// A row without a button offers none.
  ///
  /// - Parameter action: What the controller's button does.
  /// - Returns: Whether this row's button and the controller's button fix the same problem.
  func offersFix(of action: ControllerReadinessAction) -> Bool {
    guard self.action != nil else { return false }
    switch (self, action) {
    case (.driver, .setUpDriver), (.accessMissing, .openAccess): return true
    default: return false
    }
  }
}

extension RuntimeViewModel {
  /// The problems that the main window's banner shows.
  var mainWindowProblems: [MainWindowProblem] {
    MainWindowProblem.current(
      permissions: permissionState,
      status: statusState,
      driver: systemExtensionSetupState,
      extensionRouteControllers: statusState.extensionRouteControllerNames,
      liveUpdatesFallbackReason: liveUpdatesFallbackReason,
      listenerFailure: listenerFailure,
      registration: ServiceReadiness.currentRegistration(for: statusState)
    )
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
  /// Shows the Access area and requests the missing permissions, opening the Privacy & Security
  /// pane of the first one macOS does not grant.
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
