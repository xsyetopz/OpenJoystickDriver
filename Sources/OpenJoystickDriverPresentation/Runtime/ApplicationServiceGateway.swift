import Combine
import Foundation
import OpenJoystickDriverKit

protocol RuntimeStatusGateway: Sendable {
  func status() async throws -> ApplicationServiceStatusPayload
  func virtualDeviceDiagnostics() async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  func requestPermissions() async throws -> PermissionManager.Snapshot
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot
  func controllerState(for selector: RuntimeDeviceSelector) async throws -> ControllerState?
}

protocol ControllerDiagnosticsGateway: Sendable {
  func controllerState(for selector: RuntimeDeviceSelector) async throws -> ControllerState?
  func packetLog(for selector: RuntimeDeviceSelector) async throws -> [PacketLogEntry]
}

protocol RemappingGateway: Sendable {
  func remappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload
  func remappingProfile(id: UUID) async throws -> RemappingProfile
  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func activateRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func remappingPostEventAccess() async throws -> RemappingPostEventAccessState
  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState
  func pairRemappingJoyCons(
    left: String,
    right: String,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
}

protocol VirtualOutputGateway: Sendable {
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID,
    for selector: RuntimeDeviceSelector
  ) async throws -> VirtualHIDProfileOverrideResult
  func resetVirtualHIDProfileOverride(
    for selector: RuntimeDeviceSelector
  ) async throws -> VirtualHIDProfileOverrideResult
  func suspendController(_ selector: RuntimeDeviceSelector) async throws -> ControllerSuspendResult
  func resumeController(_ selector: RuntimeDeviceSelector) async throws -> ControllerResumeResult
  func disconnectWirelessController(
    _ selector: RuntimeDeviceSelector
  ) async throws -> WirelessControllerDisconnectResult
}

extension VirtualOutputGateway {
  func suspendController(_ selector: RuntimeDeviceSelector) throws -> ControllerSuspendResult {
    ControllerSuspendResult(state: .active, failure: .notFound)
  }

  func resumeController(_ selector: RuntimeDeviceSelector) throws -> ControllerResumeResult {
    ControllerResumeResult(state: .suspended, failure: .notFound)
  }

  func disconnectWirelessController(
    _ selector: RuntimeDeviceSelector
  ) throws -> WirelessControllerDisconnectResult {
    WirelessControllerDisconnectResult(state: .active, failure: .notFound)
  }
}

protocol ApplicationServiceGateway: RuntimeStatusGateway, ControllerDiagnosticsGateway,
  RemappingGateway, VirtualOutputGateway
{}

enum ApplicationServiceGatewayError: Error, LocalizedError, Sendable, Equatable {
  case profileRecoveryUnavailable
  case controllerSessionChangeRejected

  var errorDescription: String? {
    switch self {
    case .profileRecoveryUnavailable:
      return OJDLocalized.string("profiles.unavailable")
    case .controllerSessionChangeRejected:
      return OJDLocalized.string(
        "error.controllerSessionChangeRejected"
      )
    }
  }
}

package actor ApplicationServiceClientGateway: ApplicationServiceGateway {
  let client: ApplicationServiceClient
  var connectionTask: Task<Void, Never>?

  package init(client: ApplicationServiceClient = ApplicationServiceClient()) {
    self.client = client
  }
}

extension RemappingGateway {
  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await Task.yield()
    throw ApplicationServiceGatewayError.profileRecoveryUnavailable
  }

  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await Task.yield()
    throw ApplicationServiceGatewayError.profileRecoveryUnavailable
  }
}

extension ApplicationServiceClientGateway: InputTestDeviceGateway {
  func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for selector: RuntimeDeviceSelector
  ) async throws -> ControllerOutputResult {
    await ensureConnection()
    return try await client.sendControllerOutput(
      command,
      vendorID: selector.vendorID,
      productID: selector.productID,
      runtimeIdentifier: selector.runtimeIdentifier
    )
  }

  func previewColor(
    for selector: RuntimeDeviceSelector,
    token: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    await ensureConnection()
    return try await client.previewPhysicalColor(
      vendorID: selector.vendorID,
      productID: selector.productID,
      runtimeIdentifier: selector.runtimeIdentifier,
      token: token,
      red: red,
      green: green,
      blue: blue
    )
  }

  func releaseColorPreview(for selector: RuntimeDeviceSelector, token: UUID) async throws -> Bool {
    await ensureConnection()
    return try await client.releasePhysicalColorPreview(
      vendorID: selector.vendorID,
      productID: selector.productID,
      runtimeIdentifier: selector.runtimeIdentifier,
      token: token
    )
  }

  func motionCalibration(
    for selector: RuntimeDeviceSelector,
    command: RemappingMotionCalibrationCommand?
  ) async throws -> RemappingMotionCalibrationStatus {
    guard let runtimeIdentifier = selector.runtimeIdentifier else {
      throw RemappingMotionCalibrationError.controllerUnavailable
    }
    await ensureConnection()
    return try await client.remappingMotionCalibration(
      runtimeIdentifier: runtimeIdentifier,
      command: command
    )
  }
}

struct RuntimeDeviceSelector: Codable, Equatable, Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16
  let runtimeIdentifier: String?

  init(vendorID: UInt16, productID: UInt16, runtimeIdentifier: String? = nil) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
  }

  init(device: ApplicationServiceDeviceDescription) {
    self.init(
      vendorID: device.vendorID,
      productID: device.productID,
      runtimeIdentifier: device.runtimeIdentifier
    )
  }

  var displayIdentifier: String {
    runtimeIdentifier ?? String(format: "%04X:%04X", vendorID, productID)
  }
}
