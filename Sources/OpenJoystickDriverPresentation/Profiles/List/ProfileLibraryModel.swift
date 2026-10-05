import Foundation
import OpenJoystickDriverKit

/// Owns remapping profile library requests: create, update, import, delete, activation, and
/// recovery of a damaged library.
///
/// The runtime keeps the remapping snapshot and the refresh scheduling. A request claims the
/// runtime's exclusive operation slot, and a returned snapshot goes back through
/// `RuntimeViewModel.applyRemappingSnapshot(_:)`.
@MainActor
final class ProfileLibraryModel: ObservableObject {
  let runtime: RuntimeViewModel

  @Published
  var mutationState: RuntimeMutationState = .idle
  @Published
  var profileRecoveryInFlight = false
  /// The message of the latest failed profile request, cleared when a request succeeds.
  @Published
  var lastError: String?
  @Published
  var activeMutationOperation: RuntimeMutationOperation?
  @Published
  var activeMutationID: UUID?
  @Published
  var lastMutationOperation: RuntimeMutationOperation?
  @Published
  var lastMutationID: UUID?

  init(runtime: RuntimeViewModel) { self.runtime = runtime }

  private var gateway: any ApplicationServiceGateway { runtime.gateway }

  @discardableResult
  func createRemappingProfile(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await gateway.createRemappingProfile(profile)
    }
  }

  @discardableResult
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: profile.id) {
      try await gateway.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
    }
  }

  @discardableResult
  func importRemappingProfile(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await gateway.importRemappingProfile(profile)
    }
  }

  @discardableResult
  func deleteRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: id) {
      try await gateway.deleteRemappingProfile(id: id)
    }
  }

  func deleteDamagedRemappingProfile(issueID: UUID) async -> String? {
    let gateway = self.gateway
    return await performProfileRecovery {
      try await gateway.deleteDamagedRemappingProfile(issueID: issueID)
    }
  }

  func resetRemappingProfileLibrary(issueID: UUID) async -> String? {
    let gateway = self.gateway
    return await performProfileRecovery {
      try await gateway.resetRemappingProfileLibrary(issueID: issueID)
    }
  }

  @discardableResult
  func activateRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: id) {
      try await gateway.activateRemappingProfile(id: id)
    }
  }

  @discardableResult
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await gateway.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
    }
  }

  @discardableResult
  func deactivateRemappingProfile(
    profileID: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let gateway = self.gateway
    return await performMutation(request: request, conflictProfileID: profileID) {
      try await gateway.deactivateRemappingProfile(profileID: profileID)
    }
  }

  private func performMutation(
    request mutationRequest: RuntimeMutationRequest,
    conflictProfileID: UUID?,
    request: @escaping @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
  ) async -> RuntimeMutationResult {
    guard await runtime.beginMutation() else { return rejectMutation(mutationRequest) }
    let operation = mutationRequest.operation
    let mutationID = mutationRequest.id
    activeMutationOperation = operation
    activeMutationID = mutationID
    lastMutationOperation = nil
    lastMutationID = nil
    mutationState = .saving
    defer {
      activeMutationOperation = nil
      activeMutationID = nil
      runtime.endMutation()
    }
    do {
      let snapshot = try await request()
      runtime.applyRemappingSnapshot(snapshot)
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

  private func performProfileRecovery(
    request: @escaping @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
  ) async -> String? {
    guard !profileRecoveryInFlight, !runtime.mutationInFlight else {
      return OJDLocalized.string(
        "error.actionInProgress"
      )
    }
    await runtime.waitForExclusiveAccess()
    guard !profileRecoveryInFlight, !runtime.mutationInFlight else {
      return OJDLocalized.string(
        "error.actionInProgress"
      )
    }
    profileRecoveryInFlight = true
    defer {
      profileRecoveryInFlight = false
      runtime.resumeDeferredRefreshes()
    }
    do {
      let snapshot = try await request()
      runtime.applyRemappingSnapshot(snapshot)
      lastError = nil
      return nil
    } catch {
      let message = RuntimePresentation.userFacingError(error)
      lastError = message
      return message
    }
  }

  @discardableResult
  private func rejectMutation(_ request: RuntimeMutationRequest) -> RuntimeMutationResult {
    lastMutationOperation = request.operation
    lastMutationID = request.id
    let message = OJDLocalized.string(
      "error.actionInProgress"
    )
    mutationState = .error(message)
    lastError = message
    return .rejected(id: request.id, operation: request.operation, message: message)
  }

  private func locallyValid(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) -> RuntimeMutationResult? {
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
}
