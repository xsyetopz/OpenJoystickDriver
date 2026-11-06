import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// Reads the service status and the profile library again without replacing the views with a
  /// loading state.
  ///
  /// A call made while another refresh or a change runs waits for it. Returns whether the status,
  /// the profiles, the permissions or the load state changed.
  @discardableResult
  func refreshLiveStatus() async -> Bool { await enqueueScopedRefresh(.live) }

  /// Reads the service status again, for the connected controllers and the permissions, without
  /// reading the profile library.
  func refreshControllerInventory() async { _ = await enqueueScopedRefresh(.inventory) }

  /// Starts the scoped refresh, or waits for the refresh or change that runs and covers it.
  ///
  /// Returns whether the state changed.
  private func enqueueScopedRefresh(_ refresh: ScopedRefresh) async -> Bool {
    let previousStatusState = statusState
    let previousRemappingState = remappingState
    let previousPermissionState = permissionState
    let previousPostEventAccessState = postEventAccessState
    let previousLoadState = loadState
    pendingScopedRefreshes.formUnion(refresh)
    guard !isScopedRefreshInFlight, !fullRefreshInFlight, !mutationInFlight else {
      await withCheckedContinuation { scopedRefreshWaiters.append($0) }
      return scopedRefreshChanged(
        statusState: previousStatusState,
        remappingState: previousRemappingState,
        permissionState: previousPermissionState,
        postEventAccessState: previousPostEventAccessState,
        loadState: previousLoadState
      )
    }
    setScopedRefreshInFlight(true)
    defer {
      setScopedRefreshInFlight(false)
      let waiters = scopedRefreshWaiters
      scopedRefreshWaiters = []
      for waiter in waiters { waiter.resume() }
    }

    while !pendingScopedRefreshes.isEmpty, !fullRefreshInFlight, !mutationInFlight {
      let refreshes = pendingScopedRefreshes
      pendingScopedRefreshes = []
      liveStatusGeneration += 1
      let generation = liveStatusGeneration
      await refreshStatusRetainingPresentation(generation: generation)

      guard refreshes.contains(.live) else { continue }
      do {
        let snapshot = try await gateway.remappingSnapshot()
        guard generation == liveStatusGeneration else { continue }
        let nextRemappingState = RuntimeRemappingState.available(snapshot)
        if remappingState != nextRemappingState { remappingState = nextRemappingState }
        authoritativePostEventAccess = snapshot.postEventAccess
        let nextPostEventAccessState = RuntimePostEventAccessLoadState.available(
          snapshot.postEventAccess
        )
        if postEventAccessState != nextPostEventAccessState {
          postEventAccessState = nextPostEventAccessState
        }
        updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
      } catch {
        // Keep the last known remapping state during an unobtrusive background refresh.
      }
    }
    return scopedRefreshChanged(
      statusState: previousStatusState,
      remappingState: previousRemappingState,
      permissionState: previousPermissionState,
      postEventAccessState: previousPostEventAccessState,
      loadState: previousLoadState
    )
  }

  /// Sets whether a scoped refresh runs and publishes the value.
  private func setScopedRefreshInFlight(_ isInFlight: Bool) {
    isScopedRefreshInFlight = isInFlight
    scopedRefreshInFlightPublisher.send(isInFlight)
  }

  /// Returns whether the status, the profile library, the permissions, the Post Event access or the
  /// load state differs from the previous values.
  private func scopedRefreshChanged(
    statusState previousStatusState: RuntimeStatusState,
    remappingState previousRemappingState: RuntimeRemappingState,
    permissionState previousPermissionState: RuntimePermissionLoadState,
    postEventAccessState previousPostEventAccessState: RuntimePostEventAccessLoadState,
    loadState previousLoadState: RuntimeLoadState
  ) -> Bool {
    previousStatusState != statusState || previousRemappingState != remappingState
      || previousPermissionState != permissionState
      || previousPostEventAccessState != postEventAccessState || previousLoadState != loadState
  }

  /// Reads the service status and updates the status, the permissions and the controller list in
  /// place.
  ///
  /// A failure shows as an error only while the status is loading; otherwise it sets
  /// ``liveStatusError`` and keeps the last list.
  private func refreshStatusRetainingPresentation(generation: Int) async {
    do {
      let payload = try await gateway.status()
      guard generation == liveStatusGeneration else { return }
      let previousStatus: RuntimeStatusPresentation?
      if case .available(let status) = statusState {
        previousStatus = status
      } else {
        previousStatus = nil
      }
      let permissions: RuntimePermissionSummary
      switch permissionState {
      case .requesting:
        permissions =
          authoritativePermissionSummary
          ?? RuntimePermissionSummary(inputRead: .unknown, inputInject: .unknown)
      case .loading, .available, .unavailable, .error:
        permissions = RuntimePermissionSummary(status: payload)
        authoritativePermissionSummary = permissions
      }
      let nextStatusState = RuntimeStatusState.available(
        RuntimeStatusPresentation(
          payload: payload,
          postEventAccess: authoritativePostEventAccess ?? previousStatus?.postEventAccess,
          requiresPostEventAccess: previousStatus?.requiresPostEventAccess
        ).applyingPermissions(permissions)
      )
      if statusState != nextStatusState { statusState = nextStatusState }
      publishControllerInventory(payload.connectedDevices)
      if case .requesting = permissionState {
        // The explicit permission request remains authoritative until its response arrives.
      } else {
        let nextPermissionState = RuntimePermissionLoadState.available(permissions)
        if permissionState != nextPermissionState { permissionState = nextPermissionState }
      }
      if loadState != .available { loadState = .available }
      if liveStatusError != nil { liveStatusError = nil }
    } catch {
      guard generation == liveStatusGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      if case .loading = statusState {
        statusState =
          RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      } else if liveStatusError != message {
        // The last list stays visible, but must not pass for current while reads keep failing.
        liveStatusError = message
      }
    }
  }

  /// Publishes the session tokens of the connected controllers when they differ, and drops the
  /// finished override states of controller models that are not connected.
  func publishControllerInventory(_ devices: [ApplicationServiceDeviceDescription]) {
    let connectedModels = Set(devices.map(RuntimeControllerModel.init))
    let staleModels = virtualHIDProfileOverrideStates.filter { model, state in
      !state.inFlight && !connectedModels.contains(model)
    }.keys
    for model in staleModels { virtualHIDProfileOverrideStates[model] = nil }
    let identifiers = devices.map(\.sessionToken)
    guard identifiers != controllerSessionTokens else { return }
    controllerSessionTokens = identifiers
    controllerInventoryGeneration &+= 1
  }

  /// Returns when the running scoped refresh ends; returns at once when none runs.
  func waitForScopedRefreshCompletion() async {
    guard isScopedRefreshInFlight else { return }
    await withCheckedContinuation { scopedRefreshWaiters.append($0) }
  }

  /// Returns when no full refresh and no change runs.
  func waitForExclusiveOperationCompletion() async {
    while fullRefreshInFlight || mutationInFlight {
      await withCheckedContinuation { exclusiveOperationWaiters.append($0) }
    }
  }

  /// Resumes the callers that wait for an exclusive operation.
  func resumeExclusiveOperationWaiters() {
    let waiters = exclusiveOperationWaiters
    exclusiveOperationWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  /// Runs the pending scoped refreshes, if there are any.
  func schedulePendingScopedRefresh() {
    guard !pendingScopedRefreshes.isEmpty else { return }
    Task { @MainActor in _ = await enqueueScopedRefresh([]) }
  }
}
