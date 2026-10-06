import Foundation
import OpenJoystickDriverKit

/// Each handler throws `ApplicationServiceRemappingRPCError`, which the local RPC bridge sends
/// as a structured remapping error.
extension ApplicationServiceServer {

  package func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.snapshot().get()
  }

  /// Reloads the profile files after they change on disk and refreshes the affected routes.
  func reloadRemappingProfiles() async {
    if case .failure(let error) = await remappingRequests.reloadProfiles() {
      fputs("[Profiles] Reload failed: \(error.message)\n", stderr)
    }
  }

  func deleteDamagedRemappingProfile(
    _ arguments: ApplicationServiceRemappingProfileIssueArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.deleteDamagedProfile(issueID: arguments.issueID).get()
  }

  func resetRemappingProfileLibrary(
    _ arguments: ApplicationServiceRemappingProfileIssueArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.resetDamagedLibrary(issueID: arguments.issueID).get()
  }

  func remappingMotionCalibration(
    _ arguments: ApplicationServiceMotionCalibrationArguments
  ) async throws -> RemappingMotionCalibrationStatus {
    try await remappingRequests.motionCalibration(arguments).get()
  }

  func pairRemappingJoyCons(
    _ arguments: ApplicationServiceJoyConPairArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.pairJoyCons(arguments).get()
  }

  func unpairRemappingJoyCons(
    _ arguments: ApplicationServiceJoyConUnpairArguments
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.unpairJoyCons(arguments).get()
  }

  func getRemappingProfile(id: UUID) async throws -> RemappingProfile {
    try await remappingRequests.profile(id: id).get()
  }

  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.create(profile).get()
  }

  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.update(profile, expectedCurrent: expectedCurrent).get()
  }

  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.importProfile(profile).get()
  }

  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.delete(id: id).get()
  }

  package func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.activate(id: id, allowEmpty: allowEmpty).get()
  }

  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.deactivate(vendorID: vendorID, productID: productID).get()
  }

  package func deactivateRemappingProfile(
    id: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingRequests.deactivate(profileID: id).get()
  }

  func getRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await remappingRequests.currentPostEventAccess().get()
  }

  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await remappingRequests.requestPostEventAccess().get()
  }
}
