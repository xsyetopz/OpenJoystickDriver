import Foundation
import OpenJoystickDriverKit

/// Each handler throws `ApplicationServiceRemappingRPCError`, which the local RPC bridge sends
/// as a structured remapping error.
extension ApplicationServiceServer {

  /// Returns the profiles, active profiles, routes, Joy-Con pairs and issues as one snapshot.
  package func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.snapshot().get()
  }

  /// Reloads the profile files after they change on disk and refreshes the affected routes.
  func reloadRemappingProfiles() async {
    if case .failure(let error) = await remappingRequests.reloadProfiles() {
      fputs("[Profiles] Reload failed: \(error.message)\n", stderr)
    }
  }

  /// Deletes the damaged profile of the issue and returns the snapshot.
  func deleteDamagedRemappingProfile(
    _ arguments: ApplicationServiceRemappingProfileIssueArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.deleteDamagedProfile(issueID: arguments.issueID).get()
  }

  /// Resets the damaged library of the issue and returns the snapshot.
  func resetRemappingProfileLibrary(
    _ arguments: ApplicationServiceRemappingProfileIssueArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.resetDamagedLibrary(issueID: arguments.issueID).get()
  }

  /// Runs the motion calibration command on the controller that `arguments` names.
  func remappingMotionCalibration(
    _ arguments: ApplicationServiceMotionCalibrationArguments
  ) async throws -> RemappingMotionCalibrationStatus {
    try await remappingRequests.motionCalibration(arguments).get()
  }

  /// Pairs two Joy-Con controllers under a profile and returns the snapshot.
  func pairRemappingJoyCons(
    _ arguments: ApplicationServiceJoyConPairArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.pairJoyCons(arguments).get()
  }

  /// Ends a Joy-Con pair session and returns the snapshot.
  func unpairRemappingJoyCons(
    _ arguments: ApplicationServiceJoyConUnpairArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.unpairJoyCons(arguments).get()
  }

  /// Returns the profile `id`.
  func getRemappingProfile(id: UUID) async throws -> RemappingProfile {
    try await remappingRequests.profile(id: id).get()
  }

  /// Adds `profile` to the library and returns the snapshot.
  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.create(profile).get()
  }

  /// Replaces `profile` if the stored one equals `expectedCurrent`, and returns the snapshot.
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.update(profile, expectedCurrent: expectedCurrent).get()
  }

  /// Adds `profile` as an imported profile and returns the snapshot.
  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.importProfile(profile).get()
  }

  /// Deletes the profile `id` and returns the snapshot.
  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.delete(id: id).get()
  }

  /// Activates the profile `id` for its model; `allowEmpty` lets a profile that produces no output
  /// activate.
  package func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.activate(id: id, allowEmpty: allowEmpty).get()
  }

  /// Deactivates every profile of the model and returns the snapshot.
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.deactivate(vendorID: vendorID, productID: productID).get()
  }

  /// Deactivates the profile `id` and returns the snapshot.
  package func deactivateRemappingProfile(
    id: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.deactivate(profileID: id).get()
  }

  /// Returns the state of the access to post system input events.
  func getRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await remappingRequests.currentPostEventAccess().get()
  }

  /// Requests the access to post system input events.
  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await remappingRequests.requestPostEventAccess().get()
  }
}
