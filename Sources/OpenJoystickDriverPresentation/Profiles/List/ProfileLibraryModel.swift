import Combine
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
  /// The model of the app's view of the service, whose exclusive operation slot the requests
  /// claim.
  let runtime: RuntimeViewModel

  /// The state of the latest request: idle, saving, or how it ended.
  @Published
  var mutationState: RuntimeMutationState = .idle
  /// Whether a recovery of a damaged library runs.
  @Published
  var profileRecoveryInFlight = false
  /// The message of the latest failed profile request, cleared when a request succeeds.
  @Published
  var lastError: String?
  /// The operation in flight, or nil.
  @Published
  var activeMutationOperation: RuntimeMutationOperation?
  /// The identifier of the request in flight, or nil.
  @Published
  var activeMutationID: UUID?
  /// The operation of the latest finished request, or nil.
  @Published
  var lastMutationOperation: RuntimeMutationOperation?
  /// The identifier of the latest finished request, or nil.
  @Published
  var lastMutationID: UUID?

  /// Creates the model on `runtime`.
  init(runtime: RuntimeViewModel) { self.runtime = runtime }

  /// The service gateway of the runtime.
  private var gateway: any ApplicationServiceGateway { runtime.gateway }

  /// Creates a profile through the service.
  ///
  /// - Parameters:
  ///   - profile: The profile to create.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a request made while another change runs is rejected.
  @discardableResult
  func createRemappingProfile(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await service.createRemappingProfile(profile)
    }
  }

  /// Updates a profile through the service, which refuses the update when the stored profile no
  /// longer equals `expectedCurrent`.
  ///
  /// - Parameters:
  ///   - profile: The edited profile.
  ///   - expectedCurrent: The stored profile that the edit started from.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a stored profile that changed elsewhere ends it as a
  ///   conflict, and a request made while another change runs is rejected.
  @discardableResult
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: profile.id) {
      try await service.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
    }
  }

  /// Imports a profile through the service.
  ///
  /// - Parameters:
  ///   - profile: The profile to import.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a request made while another change runs is rejected.
  @discardableResult
  func importRemappingProfile(
    _ profile: RemappingProfile,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    if let failure = locallyValid(profile, request: request) { return failure }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await service.importRemappingProfile(profile)
    }
  }

  /// Deletes a profile through the service.
  ///
  /// - Parameters:
  ///   - id: The identifier of the profile.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a request made while another change runs is rejected.
  @discardableResult
  func deleteRemappingProfile(
    id: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: id) {
      try await service.deleteRemappingProfile(id: id)
    }
  }

  /// Deletes a damaged profile file through the service.
  ///
  /// - Parameter issueID: The identifier of the profile issue.
  /// - Returns: The message of the failure, or nil when the file was deleted.
  func deleteDamagedRemappingProfile(issueID: UUID) async -> String? {
    let service = self.gateway
    return await performProfileRecovery {
      try await service.deleteDamagedRemappingProfile(issueID: issueID)
    }
  }

  /// Resets the profile library through the service, which recovers an unusable library.
  ///
  /// - Parameter issueID: The identifier of the profile issue.
  /// - Returns: The message of the failure, or nil when the library was reset.
  func resetRemappingProfileLibrary(issueID: UUID) async -> String? {
    let service = self.gateway
    return await performProfileRecovery {
      try await service.resetRemappingProfileLibrary(issueID: issueID)
    }
  }

  /// Activates a profile through the service.
  ///
  /// - Parameters:
  ///   - id: The identifier of the profile.
  ///   - allowEmpty: Whether the profile may be activated when it produces no output.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a request made while another change runs is rejected.
  @discardableResult
  func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: id) {
      try await service.activateRemappingProfile(id: id, allowEmpty: allowEmpty)
    }
  }

  /// Deactivates the active profile of a controller model through the service.
  ///
  /// - Parameters:
  ///   - vendorID: The vendor ID of the model.
  ///   - productID: The product ID of the model.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a request made while another change runs is rejected.
  @discardableResult
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: nil) {
      try await service.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
    }
  }

  /// Deactivates a profile through the service.
  ///
  /// - Parameters:
  ///   - profileID: The identifier of the profile.
  ///   - request: The identifier and operation of the request.
  /// - Returns: How the request ended; a request made while another change runs is rejected.
  @discardableResult
  func deactivateRemappingProfile(
    profileID: UUID,
    request: RuntimeMutationRequest
  ) async -> RuntimeMutationResult {
    guard !runtime.mutationInFlight else { return rejectMutation(request) }
    let service = self.gateway
    return await performMutation(request: request, conflictProfileID: profileID) {
      try await service.deactivateRemappingProfile(profileID: profileID)
    }
  }

  /// Runs a profile request in the runtime's exclusive operation slot and records how it ended.
  ///
  /// A snapshot that comes back goes to the runtime. A stored profile that changed elsewhere ends
  /// as a conflict for `conflictProfileID`, any other error as a failure, and a slot that is taken
  /// as a rejection.
  ///
  /// - Parameters:
  ///   - mutationRequest: The identifier and operation of the request.
  ///   - conflictProfileID: The profile that a conflict concerns, or nil.
  ///   - request: Sends the request to the service.
  /// - Returns: How the request ended.
  private func performMutation(
    request mutationRequest: RuntimeMutationRequest,
    conflictProfileID: UUID?,
    request: @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
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

  /// Runs the recovery of a damaged library once the runtime's exclusive access is free.
  ///
  /// - Parameter request: Sends the recovery to the service.
  /// - Returns: The message of the failure or of a change that is in flight, or nil on success.
  private func performProfileRecovery(
    request: @Sendable () async throws -> ApplicationServiceRemappingSnapshotPayload
  ) async -> String? {
    guard !profileRecoveryInFlight, !runtime.mutationInFlight else {
      return OJDLocalized.string(
        "ui.error.actionInProgress"
      )
    }
    await runtime.waitForExclusiveAccess()
    guard !profileRecoveryInFlight, !runtime.mutationInFlight else {
      return OJDLocalized.string(
        "ui.error.actionInProgress"
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

  /// Records that the request was refused because another change runs.
  ///
  /// - Parameter request: The refused request.
  /// - Returns: The rejection with the message that an action is in progress.
  @discardableResult
  private func rejectMutation(_ request: RuntimeMutationRequest) -> RuntimeMutationResult {
    lastMutationOperation = request.operation
    lastMutationID = request.id
    let message = OJDLocalized.string(
      "ui.error.actionInProgress"
    )
    mutationState = .error(message)
    lastError = message
    return .rejected(id: request.id, operation: request.operation, message: message)
  }

  /// Validates the profile before it is sent.
  ///
  /// - Parameters:
  ///   - profile: The profile to check.
  ///   - request: The identifier and operation of the request.
  /// - Returns: The failure, recorded as the latest request, or nil when the profile is valid.
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
