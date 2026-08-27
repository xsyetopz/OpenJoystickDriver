import Combine
import Foundation
import OpenJoystickDriverKit

@MainActor final class RuntimeViewModel: ObservableObject {
  let gateway: any ApplicationServiceGateway

  @Published private(set) var loadState: RuntimeLoadState = .loading
  @Published private(set) var statusState: RuntimeStatusState = .loading
  @Published private(set) var remappingState: RuntimeRemappingState = .loading
  @Published private(set) var permissionState: RuntimePermissionLoadState = .unavailable
  @Published private(set) var postEventAccessState: RuntimePostEventAccessLoadState = .loading
  @Published private(set) var compatibilityState: RuntimeCompatibilityState = .loading
  @Published private(set) var compatibilityError: String?
  @Published private(set) var mutationState: RuntimeMutationState = .idle
  @Published private(set) var inputCaptureState: RuntimeInputCaptureState = .idle
  @Published private(set) var inputStates: [RuntimeDeviceSelector: DeviceInputState] = [:]
  @Published var supportDiagnosticsState: RuntimeSupportDiagnosticsState = .idle
  @Published var supportReportState: RuntimeSupportReportState = .idle
  @Published var supportLogsState: RuntimeSupportLogsState = .idle
  @Published private(set) var lastError: String?
  @Published private(set) var activeMutationOperation: RuntimeMutationOperation?
  @Published private(set) var activeMutationID: UUID?
  @Published private(set) var lastMutationOperation: RuntimeMutationOperation?
  @Published private(set) var lastMutationID: UUID?

  private var refreshGeneration = 0
  private var liveStatusGeneration = 0
  private var permissionRefreshGeneration = 0
  private var postEventAccessGeneration = 0
  private var compatibilityGeneration = 0
  private var authoritativePermissionSummary: RuntimePermissionSummary?
  private var authoritativePostEventAccess: RemappingPostEventAccessState?
  private var authoritativeCompatibilityIdentity: CompatibilityIdentity?
  private var inputGeneration = 0
  var supportDiagnosticsGeneration = 0
  var supportReportGeneration = 0
  var supportLogsGeneration = 0
  private var mutationInFlight = false
  private var fullRefreshInFlight = false

  init(gateway: any ApplicationServiceGateway) { self.gateway = gateway }

  func refresh() async {
    refreshGeneration += 1
    let generation = refreshGeneration
    fullRefreshInFlight = true
    defer { if generation == refreshGeneration { fullRefreshInFlight = false } }
    liveStatusGeneration += 1
    let statusGeneration = liveStatusGeneration
    loadState = .loading
    statusState = .loading
    remappingState = .loading
    permissionRefreshGeneration += 1
    let permissionGeneration = permissionRefreshGeneration
    postEventAccessGeneration += 1
    let postEventGeneration = postEventAccessGeneration
    compatibilityGeneration += 1
    let compatibilityOperationGeneration = compatibilityGeneration
    authoritativePermissionSummary = nil
    authoritativePostEventAccess = nil
    authoritativeCompatibilityIdentity = nil
    permissionState = .loading
    postEventAccessState = .loading
    compatibilityState = .loading
    compatibilityError = nil
    lastError = nil
    var loadedAny = false

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
        // A newer permission request owns the visible permission state.  Until its response is
        // available, replace the payload's old value with an honest checking state.
        permissions =
          authoritativePermissionSummary
          ?? RuntimePermissionSummary(inputMonitoring: .unknown, accessibility: .unknown)
      }
      let presentation = RuntimeStatusPresentation(payload: payload).applyingPermissions(
        permissions
      ).applyingCompatibilityIdentity(authoritativeCompatibilityIdentity)
      statusState = .available(presentation)
      if permissionGeneration == permissionRefreshGeneration {
        permissionState = .available(permissions)
      }
      loadedAny = true
    } catch {
      guard generation == refreshGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      statusState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      if permissionGeneration == permissionRefreshGeneration { permissionState = .error(message) }
      lastError = message
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
        // A newer access request owns the visible state.  Do not let this older snapshot roll its
        // result back while the newer request is loading or has already completed.
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
      lastError = lastError ?? message
    }

    do {
      let identity = try await gateway.compatibilityIdentity()
      guard generation == refreshGeneration else { return }
      // A scoped Output action may have started while the broader refresh was in flight.  Keep
      // that newer operation authoritative instead of letting this older read roll it back.
      if compatibilityOperationGeneration == compatibilityGeneration {
        authoritativeCompatibilityIdentity = identity
        compatibilityState = .available(identity)
        compatibilityError = nil
        updateStatusCompatibilityIdentity(identity)
        loadedAny = true
      }
    } catch {
      guard generation == refreshGeneration else { return }
      if compatibilityOperationGeneration == compatibilityGeneration {
        let message = RuntimePresentation.userFacingError(error)
        compatibilityState =
          RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
        compatibilityError = message
        authoritativeCompatibilityIdentity = nil
        updateStatusCompatibilityIdentity(nil)
        lastError = lastError ?? message
      }
    }

    guard generation == refreshGeneration else { return }
    loadState =
      loadedAny
      ? .available
      : .unavailable(
        lastError
          ?? OJDLocalized.string(
            "error.notAvailable",
            fallback: "OpenJoystickDriver isn’t available right now."
          )
      )
  }

  /// Refreshes connection- and profile-sensitive state without replacing the UI with loading state.
  func refreshLiveStatus() async {
    guard !fullRefreshInFlight, !mutationInFlight else { return }
    liveStatusGeneration += 1
    let generation = liveStatusGeneration
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
          ?? RuntimePermissionSummary(inputMonitoring: .unknown, accessibility: .unknown)
      case .loading, .available, .unavailable, .error:
        permissions = RuntimePermissionSummary(status: payload)
        authoritativePermissionSummary = permissions
      }
      statusState = .available(
        RuntimeStatusPresentation(
          payload: payload,
          postEventAccess: authoritativePostEventAccess ?? previousStatus?.postEventAccess,
          requiresPostEventAccess: previousStatus?.requiresPostEventAccess
        ).applyingPermissions(permissions)
      )
      if case .requesting = permissionState {
        // The explicit permission request remains authoritative until its response arrives.
      } else {
        permissionState = .available(permissions)
      }
      loadState = .available
      lastError = nil
    } catch {
      guard generation == liveStatusGeneration else { return }
      if case .loading = statusState {
        let message = RuntimePresentation.userFacingError(error)
        statusState =
          RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
        lastError = message
      }
    }

    do {
      let snapshot = try await gateway.remappingSnapshot()
      guard generation == liveStatusGeneration else { return }
      remappingState = .available(snapshot)
      authoritativePostEventAccess = snapshot.postEventAccess
      postEventAccessState = .available(snapshot.postEventAccess)
      updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
    } catch {
      // Keep the last known remapping state during an unobtrusive background refresh.
    }
  }

  func refreshPermissions() async {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .loading
    updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
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
      updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
      lastError = message
    }
  }

  @discardableResult func requestPermissions() async -> RuntimePermissionSummary? {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
    do {
      let snapshot = try await gateway.requestPermissions()
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      lastError = nil
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
      lastError = message
      return nil
    }
  }

  @discardableResult func requestPermission(_ requirement: PermissionManager.Requirement) async
    -> RuntimePermissionSummary?
  {
    permissionRefreshGeneration += 1
    let generation = permissionRefreshGeneration
    authoritativePermissionSummary = nil
    permissionState = .requesting
    updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
    do {
      let snapshot = try await gateway.requestPermission(requirement)
      guard generation == permissionRefreshGeneration else { return nil }
      let permissions = RuntimePermissionSummary(snapshot: snapshot)
      permissionState = .available(permissions)
      authoritativePermissionSummary = permissions
      updateStatusPermissions(permissions)
      lastError = nil
      return permissions
    } catch {
      guard generation == permissionRefreshGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      permissionState = .error(message)
      updateStatusPermissions(.init(inputMonitoring: .unknown, accessibility: .unknown))
      lastError = message
      return nil
    }
  }

  @discardableResult func requestPostEventAccess() async -> RemappingPostEventAccessState? {
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
      lastError = nil
      return state
    } catch {
      guard generation == postEventAccessGeneration else { return nil }
      let message = RuntimePresentation.userFacingError(error)
      postEventAccessState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      authoritativePostEventAccess = nil
      updateStatusPostEventAccess(nil)
      lastError = message
      return nil
    }
  }

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
      lastError = message
    }
  }

  func readInputState(for selector: RuntimeDeviceSelector) async {
    inputGeneration += 1
    let generation = inputGeneration
    inputCaptureState = .listening(selector)
    do {
      let state = try await gateway.deviceInputState(for: selector)
      guard generation == inputGeneration else { return }
      guard let state else {
        inputCaptureState = .unavailable(
          selector,
          OJDLocalized.string(
            "error.noControllerInput",
            fallback: "No controller input is available yet."
          )
        )
        return
      }
      inputStates[selector] = state
      inputCaptureState = .received(selector, state)
    } catch is CancellationError {
      guard generation == inputGeneration else { return }
      inputCaptureState = .idle
    } catch {
      guard generation == inputGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      inputCaptureState =
        RuntimePresentation.isUnavailable(error)
        ? .unavailable(selector, message) : .error(selector, message)
      lastError = message
    }
  }

  func listenForInput(for selector: RuntimeDeviceSelector) async {
    inputGeneration += 1
    let generation = inputGeneration
    inputCaptureState = .listening(selector)
    var baselineState: DeviceInputState?

    for attempt in 0..<50 {
      guard generation == inputGeneration else { return }
      do {
        if let state = try await gateway.deviceInputState(for: selector) {
          guard generation == inputGeneration else { return }
          inputStates[selector] = state
          if let baselineState,
            let detectedSource = RuntimePresentation.detectedTransition(
              from: baselineState,
              to: state
            )
          {
            inputCaptureState = .detected(selector, state, detectedSource)
            return
          }
          baselineState = state
        }
        if attempt < 49 { try await Task.sleep(nanoseconds: 100_000_000) }
      } catch is CancellationError {
        guard generation == inputGeneration else { return }
        inputCaptureState = .idle
        return
      } catch {
        guard generation == inputGeneration else { return }
        let message = RuntimePresentation.userFacingError(error)
        inputCaptureState =
          RuntimePresentation.isUnavailable(error)
          ? .unavailable(selector, message) : .error(selector, message)
        lastError = message
        return
      }
    }

    guard generation == inputGeneration else { return }
    inputCaptureState = .unavailable(
      selector,
      OJDLocalized.string(
        "error.noDetectedControl",
        fallback: "No new controller control was detected."
      )
    )
  }

  func cancelInputCapture() {
    inputGeneration += 1
    inputCaptureState = .idle
  }

  @discardableResult
  func createRemappingProfile(_ profile: RemappingProfile, request: RuntimeMutationRequest) async
    -> RuntimeMutationResult
  {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    if let failure = locallyValid(profile, request: request) {
      return failure
    }
    let gateway = self.gateway
    return await performMutation(
      request: request,
      conflictProfileID: nil
    ) {
      try await gateway.createRemappingProfile(profile)
    }
  }

  @discardableResult
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile,
    request: RuntimeMutationRequest
  ) async
    -> RuntimeMutationResult
  {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    if let failure = locallyValid(profile, request: request) {
      return failure
    }
    let gateway = self.gateway
    // Keep the expected snapshot exactly as supplied.  The service's compare-and-swap operation
    // owns conflict detection; the view model never fetches and silently overwrites it.
    return await performMutation(
      request: request,
      conflictProfileID: profile.id
    ) {
      try await gateway.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
    }
  }

  @discardableResult
  func importRemappingProfile(_ profile: RemappingProfile, request: RuntimeMutationRequest) async
    -> RuntimeMutationResult
  {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    if let failure = locallyValid(profile, request: request) {
      return failure
    }
    let gateway = self.gateway
    return await performMutation(
      request: request,
      conflictProfileID: nil
    ) {
      try await gateway.importRemappingProfile(profile)
    }
  }

  @discardableResult
  func deleteRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    let gateway = self.gateway
    return await performMutation(
      request: request,
      conflictProfileID: id
    ) {
      try await gateway.deleteRemappingProfile(id: id)
    }
  }

  @discardableResult
  func activateRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    let gateway = self.gateway
    return await performMutation(
      request: request,
      conflictProfileID: id
    ) {
      try await gateway.activateRemappingProfile(id: id)
    }
  }

  @discardableResult
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    let gateway = self.gateway
    return await performMutation(
      request: request,
      conflictProfileID: nil
    ) {
      try await gateway.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
    }
  }

  @discardableResult
  func deactivateRemappingProfile(profileID: UUID, request: RuntimeMutationRequest) async
    -> RuntimeMutationResult
  {
    guard !mutationInFlight else {
      return rejectMutation(request)
    }
    let gateway = self.gateway
    return await performMutation(
      request: request,
      conflictProfileID: profileID
    ) {
      try await gateway.deactivateRemappingProfile(profileID: profileID)
    }
  }

  func loadCompatibilityIdentity() async {
    compatibilityGeneration += 1
    let generation = compatibilityGeneration
    authoritativeCompatibilityIdentity = nil
    compatibilityState = .loading
    compatibilityError = nil
    updateStatusCompatibilityIdentity(nil)
    do {
      let identity = try await gateway.compatibilityIdentity()
      guard generation == compatibilityGeneration else { return }
      authoritativeCompatibilityIdentity = identity
      compatibilityState = .available(identity)
      updateStatusCompatibilityIdentity(identity)
    } catch {
      guard generation == compatibilityGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      compatibilityState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      compatibilityError = message
      authoritativeCompatibilityIdentity = nil
      updateStatusCompatibilityIdentity(nil)
      lastError = message
    }
  }

  func setCompatibilityIdentity(_ identity: CompatibilityIdentity) async {
    compatibilityGeneration += 1
    let generation = compatibilityGeneration
    authoritativeCompatibilityIdentity = nil
    compatibilityState = .loading
    compatibilityError = nil
    updateStatusCompatibilityIdentity(nil)
    do {
      guard try await gateway.setCompatibilityIdentity(identity) else {
        throw ApplicationServiceGatewayError.compatibilityIdentityChangeRejected(identity)
      }
      guard generation == compatibilityGeneration else { return }
      authoritativeCompatibilityIdentity = identity
      compatibilityState = .available(identity)
      compatibilityError = nil
      updateStatusCompatibilityIdentity(identity)
      lastError = nil
    } catch {
      guard generation == compatibilityGeneration else { return }
      let message = RuntimePresentation.userFacingError(error)
      compatibilityState =
        RuntimePresentation.isUnavailable(error) ? .unavailable(message) : .error(message)
      compatibilityError = message
      authoritativeCompatibilityIdentity = nil
      updateStatusCompatibilityIdentity(nil)
      lastError = message
    }
  }

  func resetCompatibilityIdentity() async {
    // Reset only the compatibility selection. The broader service reset changes unrelated runtime
    // settings and remains CLI-only.
    await setCompatibilityIdentity(.appleGameController)
  }

  private func locallyValid(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) -> RuntimeMutationResult?
  {
    do {
      try profile.validate()
      return nil
    } catch {
      lastMutationID = request.id
      lastMutationOperation = request.operation
      let message = RuntimePresentation.userFacingError(error)
      mutationState = .error(message)
      lastError = message
      return .failed(id: request.id, operation: request.operation, message: message)
    }
  }

  private func performMutation(
    request mutationRequest: RuntimeMutationRequest,
    conflictProfileID: UUID?,
    request: @escaping @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
  ) async -> RuntimeMutationResult {
    guard !mutationInFlight else {
      return rejectMutation(mutationRequest)
    }
    let operation = mutationRequest.operation
    let mutationID = mutationRequest.id
    mutationInFlight = true
    activeMutationOperation = operation
    activeMutationID = mutationID
    lastMutationOperation = nil
    lastMutationID = nil
    mutationState = .saving
    defer {
      mutationInFlight = false
      activeMutationOperation = nil
      activeMutationID = nil
    }
    do {
      let snapshot = try await request()
      remappingState = .available(snapshot)
      postEventAccessState = .available(snapshot.postEventAccess)
      postEventAccessGeneration += 1
      authoritativePostEventAccess = snapshot.postEventAccess
      updateStatusRemappingSnapshot(snapshot, postEventAccess: snapshot.postEventAccess)
      lastMutationOperation = operation
      lastMutationID = mutationID
      switch operation {
      case .update(let profileID): mutationState = .succeeded(profileID: profileID)
      default: mutationState = .completed(operation)
      }
      lastError = nil
      return .succeeded(id: mutationID, operation: operation)
    } catch {
      let message = RuntimePresentation.userFacingError(error)
      if let rpcError = error as? ApplicationServiceRemappingRPCError,
        rpcError.code == .profileUpdateConflict
      {
        lastMutationOperation = operation
        lastMutationID = mutationID
        mutationState = .conflict(profileID: conflictProfileID)
        lastError = message
        return .conflict(id: mutationID, operation: operation)
      }
      lastMutationOperation = operation
      lastMutationID = mutationID
      mutationState = .error(message)
      lastError = message
      return .failed(id: mutationID, operation: operation, message: message)
    }
  }

  @discardableResult
  private func rejectMutation(_ request: RuntimeMutationRequest) -> RuntimeMutationResult {
    lastMutationOperation = request.operation
    lastMutationID = request.id
    let message = OJDLocalized.string(
      "error.actionInProgress",
      fallback: "Another profile action is already in progress."
    )
    mutationState = .error(message)
    lastError = message
    return .rejected(id: request.id, operation: request.operation, message: message)
  }

  private func updateStatusPermissions(_ permissions: RuntimePermissionSummary) {
    guard case .available(let status) = statusState else { return }
    statusState = .available(status.applyingPermissions(permissions))
  }

  private func updateStatusPostEventAccess(_ state: RemappingPostEventAccessState?) {
    guard case .available(let status) = statusState else { return }
    statusState = .available(status.applyingPostEventAccess(state))
  }

  private func updateStatusCompatibilityIdentity(_ identity: CompatibilityIdentity?) {
    guard case .available(let status) = statusState else { return }
    statusState = .available(status.applyingCompatibilityIdentity(identity))
  }

  private func updateStatusRemappingSnapshot(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    postEventAccess: RemappingPostEventAccessState?
  ) {
    guard case .available(let status) = statusState else { return }
    statusState = .available(
      status.applyingRemappingSnapshot(snapshot, postEventAccess: postEventAccess)
    )
  }
}
