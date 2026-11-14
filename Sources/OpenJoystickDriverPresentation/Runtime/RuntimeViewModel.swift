import Combine
import Foundation
import OpenJoystickDriverKit

/// The parts of the service state that a scoped refresh reads.
struct ScopedRefresh: OptionSet {
  /// The bits of the parts that the refresh reads.
  let rawValue: UInt8

  /// The connected controllers and the permissions.
  static let inventory = Self(rawValue: 1 << 0)
  /// The connected controllers and the permissions, and the profile library.
  static let live = Self(rawValue: 1 << 1)
}

/// The app's view of the service: its status, profile library, permissions and driver extension,
/// with the requests that read and change them.
@MainActor
final class RuntimeViewModel: ObservableObject {
  /// The connection to the service.
  let gateway: any ApplicationServiceGateway

  /// Whether the first read of the service has loaded.
  @Published
  var loadState: RuntimeLoadState = .loading
  /// Why the service's change notifications are unavailable, so the app reads the service
  /// repeatedly instead; nil while they work.
  @Published
  var liveUpdatesFallbackReason: ControllerLiveUpdateFailure?
  /// The service status as the views show it.
  @Published
  var statusState: RuntimeStatusState = .loading
  /// The profile library.
  @Published
  var remappingState: RuntimeRemappingState = .loading
  /// The Input Read and Input Inject permissions.
  @Published
  var permissionState: RuntimePermissionLoadState = .unavailable
  /// The Post Event access.
  @Published
  var postEventAccessState: RuntimePostEventAccessLoadState = .loading
  /// Whether the latest attempt to open a Privacy & Security pane failed.
  @Published
  var permissionSettingsOpenFailed = false
  /// The pending and failed virtual HID profile override requests, keyed by controller model.
  @Published
  var virtualHIDProfileOverrideStates:
    [RuntimeControllerModel: RuntimeVirtualHIDProfileOverrideState] = [:]
  /// The state of the capture of the control that the user presses.
  @Published
  var inputCaptureState: RuntimeInputCaptureState = .idle
  /// Why the latest suspend, resume or disconnect request of a controller failed, keyed by its
  /// session token; cleared when the controller's next action starts.
  @Published
  var controllerActionFailures: [String: String] = [:]
  /// The server chosen for each controller model while the service applies it, so the picker
  /// keeps the choice instead of showing the record's value until the record changes.
  @Published
  var pendingControllerServers: [RuntimeControllerModel: ControllerServer] = [:]
  /// Why the service refused the latest server choice of each controller model; cleared when the
  /// model's next choice starts.
  @Published
  var controllerServerFailures: [RuntimeControllerModel: String] = [:]
  /// Why the latest background status read failed while the last controller list stays visible.
  @Published
  var liveStatusError: String?
  /// Where the Xbox USB driver extension is.
  @Published
  private(set) var systemExtensionSetupState: SystemExtensionSetupState = .checking
  /// Counts the changes of the set of connected controllers.
  @Published
  var controllerInventoryGeneration = 0
  /// Whether a scoped refresh runs.
  var isScopedRefreshInFlight = false
  /// Publishes ``isScopedRefreshInFlight``.
  let scopedRefreshInFlightPublisher = CurrentValueSubject<Bool, Never>(false)

  /// Counts the full refreshes, so that a refresh can tell whether another began.
  var refreshGeneration = 0
  /// Counts the status reads, so that a read can tell whether another began.
  var liveStatusGeneration = 0
  /// Counts the permission reads and requests, so that one can tell whether another began.
  var permissionRefreshGeneration = 0
  /// Counts the Post Event access reads and requests, so that one can tell whether another began.
  var postEventAccessGeneration = 0
  /// The permissions that the latest read or request returned, or nil while one is pending.
  var authoritativePermissionSummary: RuntimePermissionSummary?
  /// The Post Event access that the latest read or request returned, or nil while one is pending.
  var authoritativePostEventAccess: RemappingPostEventAccessState?
  /// Counts the input captures, so that a capture can tell whether another began.
  var inputGeneration = 0
  /// Whether a profile mutation holds the runtime; full and scoped refreshes wait behind it.
  private(set) var mutationInFlight = false
  /// Whether a full refresh runs.
  var fullRefreshInFlight = false
  /// The scoped refreshes that wait to run.
  var pendingScopedRefreshes: ScopedRefresh = []
  /// The session tokens of the connected controllers.
  var controllerSessionTokens: [ControllerSessionToken] = []
  /// The callers that wait for the scoped refresh to end.
  var scopedRefreshWaiters: [CheckedContinuation<Void, Never>] = []
  /// The callers that wait for a full refresh or a change to end.
  var exclusiveOperationWaiters: [CheckedContinuation<Void, Never>] = []
  /// Works out the state of the driver extension.
  private let systemExtensionSetup: SystemExtensionSetupCoordinator
  /// The in-process service's request listener: its failure and the way to start it again.
  private let listenerState: ServiceListenerState
  /// Why the request listener stopped, or nil while it listens.
  @Published
  private(set) var listenerFailure: ServiceListenerFailure?

  /// Creates the model on a service gateway, the driver extension coordinator and the state of the
  /// request listener, and follows the listener.
  init(
    gateway: any ApplicationServiceGateway,
    systemExtensionSetup: SystemExtensionSetupCoordinator,
    listenerState: ServiceListenerState
  ) {
    self.gateway = gateway
    self.systemExtensionSetup = systemExtensionSetup
    self.listenerState = listenerState
    listenerFailure = listenerState.failure
    listenerState.observe { [weak self] in
      Task { @MainActor in await self?.listenerStateChanged() }
    }
  }

  /// Reads the failure of the listener again and refreshes, so that the status line and the problem
  /// banner follow.
  private func listenerStateChanged() async {
    listenerFailure = listenerState.failure
    await refresh()
  }

  /// Starts the request listener again.
  ///
  /// A start that works clears the failure; one that fails leaves it and says why in the status
  /// line. A listener that already runs counts as started.
  func restartListener() async {
    do { try listenerState.restart() } catch LocalServiceRPCError.alreadyRunning {
      listenerState.set(nil)
    } catch {
      await refresh()
      let reason: String
      switch error {
      case LocalServiceRPCError.connectionFailed(let code):
        reason = OJDLocalized.formatted("status.listenerFailure.restartFailed", String(code))
      case ServiceListenerState.RestartError.unavailable, LocalServiceRPCError.stopping:
        reason = OJDLocalized.string("status.listenerFailure.restartUnavailable")
      default:
        reason = OJDLocalized.formatted(
          "status.listenerFailure.restartFailedReason",
          error.localizedDescription
        )
      }
      statusState = .unavailable(
        [reason, listenerFailure?.localizedSummary].compactMap { $0 }.joined(separator: " ")
      )
    }
  }

  /// The status line for a failed status request.
  ///
  /// A service that stopped its request listener explains why, with the code and the error number,
  /// whatever the request failed with: the stopped listener removed the socket.
  func statusFailureMessage(_ error: any Error) -> String {
    listenerFailure?.localizedSummary ?? RuntimePresentation.userFacingError(error)
  }

  /// Waits for scoped refreshes and exclusive operations, then claims the exclusive slot for a
  /// profile mutation.
  ///
  /// Returns false when another mutation holds the slot.
  func beginMutation() async -> Bool {
    guard !mutationInFlight else { return false }
    await waitForExclusiveAccess()
    guard !mutationInFlight else { return false }
    mutationInFlight = true
    return true
  }

  /// Releases the slot `beginMutation()` claimed and runs the refreshes deferred behind it.
  func endMutation() {
    mutationInFlight = false
    resumeDeferredRefreshes()
  }

  /// Reads the state of the driver extension at launch; it sends no request.
  func startSystemExtensionSetup() {
    systemExtensionSetup.launch()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  /// Reads the state of the driver extension again.
  func refreshSystemExtensionSetup() {
    systemExtensionSetup.refresh()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  /// Asks macOS to activate or replace the driver extension, for the user's click.
  func repairSystemExtension() async {
    if systemExtensionSetupState != .running { systemExtensionSetupState = .running }
    await systemExtensionSetup.repair()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  /// Deactivates the driver extension.
  func uninstallSystemExtension() async {
    await systemExtensionSetup.uninstall()
    systemExtensionSetupState = systemExtensionSetup.state
  }

  /// Reads the driver extension state, the service status and the profile library from the service,
  /// showing a loading state while it reads.
  ///
  /// It waits for the refreshes and changes that run first.
  func refresh() async {
    await waitForScopedRefreshCompletion()
    await waitForExclusiveOperationCompletion()
    refreshGeneration += 1
    let generation = refreshGeneration
    fullRefreshInFlight = true
    defer {
      if generation == refreshGeneration {
        fullRefreshInFlight = false
        resumeExclusiveOperationWaiters()
        schedulePendingScopedRefresh()
      }
    }
    refreshSystemExtensionSetup()
    liveStatusGeneration += 1
    let statusGeneration = liveStatusGeneration
    loadState = .loading
    statusState = .loading
    remappingState = .loading
    permissionRefreshGeneration += 1
    let permissionGeneration = permissionRefreshGeneration
    postEventAccessGeneration += 1
    let postEventGeneration = postEventAccessGeneration
    authoritativePermissionSummary = nil
    authoritativePostEventAccess = nil
    permissionState = .loading
    postEventAccessState = .loading
    liveStatusError = nil
    var loadedAny = false
    var failureMessage: String?

    do {
      let payload = try await gateway.status()
      guard generation == refreshGeneration, statusGeneration == liveStatusGeneration else {
        return
      }
      let permissions: RuntimePermissionSummary
      if permissionGeneration == permissionRefreshGeneration {
        permissions = RuntimePermissionSummary(status: payload)
        authoritativePermissionSummary = permissions
      } else {
        // A newer permission request owns the visible permission state. Until its response
        // arrives, show unknown instead of the payload's value.
        permissions =
          authoritativePermissionSummary
          ?? RuntimePermissionSummary(inputRead: .unknown, inputInject: .unknown)
      }
      let presentation = RuntimeStatusPresentation(payload: payload).applyingPermissions(
        permissions
      )
      statusState = .available(presentation)
      publishControllerInventory(payload.connectedDevices)
      if permissionGeneration == permissionRefreshGeneration {
        permissionState = .available(permissions)
      }
      loadedAny = true
    } catch {
      guard generation == refreshGeneration else { return }
      let message = statusFailureMessage(error)
      statusState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      if permissionGeneration == permissionRefreshGeneration { permissionState = .error(message) }
      failureMessage = message
    }

    do {
      let snapshot = try await gateway.remappingSnapshot()
      guard generation == refreshGeneration else { return }
      remappingState = .available(snapshot)
      let postEventAccess: RemappingPostEventAccessState?
      if postEventGeneration == postEventAccessGeneration {
        let currentPostEventAccess = snapshot.postEventAccess
        postEventAccess = currentPostEventAccess
        authoritativePostEventAccess = currentPostEventAccess
        postEventAccessState = .available(currentPostEventAccess)
      } else {
        // A newer access request owns the visible state; this older snapshot must not roll its
        // result back, whether the request is loading or done.
        postEventAccess = authoritativePostEventAccess
      }
      updateStatusRemappingSnapshot(snapshot, postEventAccess: postEventAccess)
      loadedAny = true
    } catch {
      guard generation == refreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      remappingState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      if postEventGeneration == postEventAccessGeneration {
        postEventAccessState =
          RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      }
      failureMessage = failureMessage ?? message
    }

    guard generation == refreshGeneration else { return }
    loadState =
      loadedAny
      ? .available
      : .unavailable(
        failureMessage
          ?? OJDLocalized.string(
            "ui.error.notAvailable"
          )
      )
  }

  /// Reads the permissions from the service status again.
  ///
  /// They read as unknown until the answer arrives.
  func refreshPermissions() async {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .loading
    updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    do {
      let payload = try await gateway.status()
      guard generation == permissionRefreshGeneration else { return }
      let presentation = RuntimeStatusPresentation(payload: payload)
      permissionState = .available(presentation.permissions)
      authoritativePermissionSummary = presentation.permissions
      updateStatusPermissions(presentation.permissions)
    } catch {
      guard generation == permissionRefreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    }
  }

  /// Asks macOS, through the service, for the permissions that the service requires.
  ///
  /// Returns the permissions, or nil when the request failed or a later read or request replaced
  /// it.
  @discardableResult
  func requestPermissions() async -> RuntimePermissionSummary? {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    do {
      let snapshot = try await gateway.requestPermissions()
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
      return nil
    }
  }

  /// Asks macOS, through the service, for one permission.
  ///
  /// Returns the permissions, or nil when the request failed or a later read or request replaced
  /// it.
  @discardableResult
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async -> RuntimePermissionSummary? {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
    do {
      let snapshot = try await gateway.requestPermission(requirement)
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputRead: .unknown, inputInject: .unknown))
      return nil
    }
  }

  /// Asks macOS, through the service, for Bluetooth access.
  ///
  /// Returns the state at the answer, or nil when the request failed. The status shows it at once.
  @discardableResult
  func requestBluetoothAccess() async -> BluetoothAccessState? {
    guard let access = try? await gateway.requestBluetoothAccess() else { return nil }
    if case .available(var presentation) = statusState {
      presentation.bluetoothAccess = access
      statusState = .available(presentation)
    }
    return access
  }

  /// Asks macOS for the Post Event access.
  ///
  /// Returns its state, or nil when the request failed or a later read or request replaced it.
  @discardableResult
  func requestPostEventAccess() async -> RemappingPostEventAccessState? {
    postEventAccessGeneration += 1
    let generation = postEventAccessGeneration
    authoritativePostEventAccess = nil
    postEventAccessState = .requesting
    updateStatusPostEventAccess(nil)
    do {
      let state = try await gateway.requestRemappingPostEventAccess()
      guard generation == postEventAccessGeneration else { return nil }
      postEventAccessState = .available(state)
      authoritativePostEventAccess = state
      updateStatusPostEventAccess(state)
      return state
    } catch {
      guard generation == postEventAccessGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
      return nil
    }
  }

  /// Reads the Post Event access again.
  func refreshPostEventAccess() async {
    postEventAccessGeneration += 1
    let generation = postEventAccessGeneration
    authoritativePostEventAccess = nil
    postEventAccessState = .loading
    updateStatusPostEventAccess(nil)
    do {
      let state = try await gateway.remappingPostEventAccess()
      guard generation == postEventAccessGeneration else { return }
      postEventAccessState = .available(state)
      authoritativePostEventAccess = state
      updateStatusPostEventAccess(state)
    } catch {
      guard generation == postEventAccessGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
    }
  }

}
