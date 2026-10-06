import Foundation

extension ApplicationServiceClient {

  public func pairRemappingJoyCons(
    leftRuntimeIdentifier: String,
    rightRuntimeIdentifier: String,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .pairRemappingJoyCons,
      ApplicationServiceJoyConPairArguments(
        leftRuntimeIdentifier: leftRuntimeIdentifier,
        rightRuntimeIdentifier: rightRuntimeIdentifier,
        profileID: profileID
      )
    )
  }

  public func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .unpairRemappingJoyCons,
      ApplicationServiceJoyConUnpairArguments(sessionID: sessionID)
    )
  }

  public func getRemappingProfile(id: UUID) async throws -> RemappingProfile {
    try await call(
      .getRemappingProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  public func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .createRemappingProfile,
      ApplicationServiceRemappingProfileArguments(profile: profile)
    )
  }

  public func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .updateRemappingProfile,
      ApplicationServiceRemappingProfileUpdateArguments(
        profile: profile,
        expectedCurrent: expectedCurrent
      )
    )
  }

  public func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .importRemappingProfile,
      ApplicationServiceRemappingProfileArguments(profile: profile)
    )
  }

  public func deleteRemappingProfile(
    id: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deleteRemappingProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  public func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deleteDamagedRemappingProfile,
      ApplicationServiceRemappingProfileIssueArguments(issueID: issueID)
    )
  }

  public func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .resetRemappingProfileLibrary,
      ApplicationServiceRemappingProfileIssueArguments(issueID: issueID)
    )
  }

  public func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .activateRemappingProfile,
      ApplicationServiceRemappingActivateArguments(profileID: id, allowEmpty: allowEmpty)
    )
  }

  public func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deactivateRemappingProfile,
      ApplicationServiceRemappingModelArguments(vendorID: vendorID, productID: productID)
    )
  }

  public func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deactivateRemappingProfileByID,
      ApplicationServiceRemappingProfileIDArguments(profileID: profileID)
    )
  }

  public func getRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await call(.getRemappingPostEventAccess, LocalServiceRPCEmptyArguments())
  }

  public func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await call(.requestRemappingPostEventAccess, LocalServiceRPCEmptyArguments())
  }
}
