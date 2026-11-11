public import Foundation

extension ApplicationServiceClient {

  /// Pairs the left and right Joy-Con into one controller session that the profile `profileID`
  /// remaps.
  ///
  /// - Returns: The remapping snapshot, which lists the pair in
  ///   ``ApplicationServiceRemappingSnapshotPayload/joyConPairs``.
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the pair.
  public func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .pairRemappingJoyCons,
      ApplicationServiceJoyConPairArguments(
        left: left,
        right: right,
        profileID: profileID
      )
    )
  }

  /// Splits the Joy-Con pair of the session `sessionID` into two controllers again.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the request.
  public func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .unpairRemappingJoyCons,
      ApplicationServiceJoyConUnpairArguments(sessionID: sessionID)
    )
  }

  /// Reads the remapping profile with the ID `id`.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service has no profile with the ID.
  public func getRemappingProfile(id: UUID) async throws -> RemappingProfile {
    try await call(
      .getRemappingProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  /// Adds `profile` to the remapping profile library.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the profile, for
  ///   example with ``ApplicationServiceRemappingRPCError/Code/profileAlreadyExists``.
  public func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .createRemappingProfile,
      ApplicationServiceRemappingProfileArguments(profile: profile)
    )
  }

  /// Replaces the stored profile `expectedCurrent` with `profile`.
  ///
  /// The service refuses the update when the stored profile differs from `expectedCurrent`, so an
  /// edit never overwrites a change made elsewhere.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` with
  ///   ``ApplicationServiceRemappingRPCError/Code/profileUpdateConflict`` when the stored profile
  ///   differs.
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

  /// Adds an imported `profile` to the remapping profile library.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the profile.
  public func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .importRemappingProfile,
      ApplicationServiceRemappingProfileArguments(profile: profile)
    )
  }

  /// Deletes the remapping profile with the ID `id`.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the request.
  public func deleteRemappingProfile(
    id: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deleteRemappingProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  /// Deletes the damaged profile that the profile issue `issueID` reports.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the request.
  public func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deleteDamagedRemappingProfile,
      ApplicationServiceRemappingProfileIssueArguments(issueID: issueID)
    )
  }

  /// Resets the profile library that the profile issue `issueID` reports as unusable.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the request.
  public func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .resetRemappingProfileLibrary,
      ApplicationServiceRemappingProfileIssueArguments(issueID: issueID)
    )
  }

  /// Activates the remapping profile `id`.
  ///
  /// `allowEmpty` admits a profile that produces no output.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` with
  ///   ``ApplicationServiceRemappingRPCError/Code/profileProducesNoOutput`` when the profile
  ///   produces no output and `allowEmpty` is false.
  public func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .activateRemappingProfile,
      ApplicationServiceRemappingActivateArguments(profileID: id, allowEmpty: allowEmpty)
    )
  }

  /// Deactivates the active remapping profile of the controller model `vendorID`:`productID`.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the request.
  public func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deactivateRemappingProfile,
      ApplicationServiceRemappingModelArguments(vendorID: vendorID, productID: productID)
    )
  }

  /// Deactivates the active remapping profile with the ID `profileID`.
  ///
  /// - Throws: ``ApplicationServiceRemappingRPCError`` when the service refuses the request.
  public func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(
      .deactivateRemappingProfileByID,
      ApplicationServiceRemappingProfileIDArguments(profileID: profileID)
    )
  }

  /// Reads the state of the macOS permission to post input events, which remapped keyboard and
  /// mouse output needs.
  public func getRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await call(.getRemappingPostEventAccess, LocalServiceRPCEmptyArguments())
  }

  /// Asks macOS for the permission to post input events and returns its state afterward.
  public func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await call(.requestRemappingPostEventAccess, LocalServiceRPCEmptyArguments())
  }
}
