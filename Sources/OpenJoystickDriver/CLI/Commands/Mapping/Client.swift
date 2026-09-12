import Foundation
import OpenJoystickDriverKit

protocol MappingServiceClient: Sendable {
  func snapshot() async throws -> ApplicationServiceRemappingSnapshotPayload
  func profile(id: UUID) async throws -> RemappingProfile
  func create(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func importProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func delete(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func activate(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deactivate(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deactivate(profileID: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func access(request: Bool) async throws -> RemappingPostEventAccessState
  func motionCalibration(
    runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand?
  ) async throws -> RemappingMotionCalibrationStatus
  func pairJoyCons(
    left: String,
    right: String,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func unpairJoyCons(sessionID: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
}

struct ApplicationMappingServiceClient: MappingServiceClient {
  let client: ApplicationServiceClient

  func motionCalibration(
    runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand?
  ) async throws -> RemappingMotionCalibrationStatus {
    try await client.remappingMotionCalibration(
      runtimeIdentifier: runtimeIdentifier,
      command: command
    )
  }

  func pairJoyCons(
    left: String,
    right: String,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.pairRemappingJoyCons(
      leftRuntimeIdentifier: left,
      rightRuntimeIdentifier: right,
      profileID: profileID
    )
  }

  func unpairJoyCons(sessionID: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.unpairRemappingJoyCons(sessionID: sessionID)
  }

  func snapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.getRemappingSnapshot()
  }

  func profile(id: UUID) async throws -> RemappingProfile {
    try await client.getRemappingProfile(id: id)
  }

  func create(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.createRemappingProfile(profile)
  }

  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
  }

  func importProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.importRemappingProfile(profile)
  }

  func delete(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.deleteRemappingProfile(id: id)
  }

  func activate(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.activateRemappingProfile(id: id)
  }

  func deactivate(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
  }

  func deactivate(profileID: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await client.deactivateRemappingProfile(profileID: profileID)
  }

  func access(request: Bool) async throws -> RemappingPostEventAccessState {
    if request { return try await client.requestRemappingPostEventAccess() }
    return try await client.getRemappingPostEventAccess()
  }
}
