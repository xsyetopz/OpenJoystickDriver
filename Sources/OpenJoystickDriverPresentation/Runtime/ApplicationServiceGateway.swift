import Combine
import Foundation
package import OpenJoystickDriverKit

/// The service status, permission and controller input requests of the runtime.
protocol RuntimeStatusGateway: Sendable {
  /// Returns the status of the service.
  func status() async throws -> ApplicationServiceStatusPayload
  /// Returns the diagnostics of the virtual devices.
  func virtualDeviceDiagnostics() async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  /// Returns the frame timings of every connected controller from the last `lastSeconds` seconds,
  /// or all kept frames when nil.
  func frameTimings(lastSeconds: Int?) async throws -> ApplicationServiceFrameTimingsPayload
  /// Asks macOS for the permissions that the service requires and returns their state.
  func requestPermissions() async throws -> PermissionManager.Snapshot
  /// Asks macOS for one permission and returns the state of the permissions.
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot
  /// Asks macOS for Bluetooth access and returns its state.
  func requestBluetoothAccess() async throws -> BluetoothAccessState
  /// Returns the latest input state of the controller, or nil when the service has none.
  func controllerState(for selector: ControllerReference) async throws -> ControllerState?
}

/// The input and packet reads of the developer tools.
protocol ControllerDiagnosticsGateway: Sendable {
  /// Returns the latest input state of the controller, or nil when the service has none.
  func controllerState(for selector: ControllerReference) async throws -> ControllerState?
  /// Returns the values the controller's virtual gamepad last reported, after stick transfer, dead
  /// zone and remapping, or nil when no virtual gamepad publishes the controller.
  func virtualOutputState(
    for selector: ControllerReference
  ) async throws -> ApplicationServiceVirtualOutputState?
  /// Returns the packet log of the controller.
  func packetLog(for selector: ControllerReference) async throws -> [PacketLogEntry]
}

/// The profile requests of the service: the profile library, activation and Joy-Con pairing.
///
/// Each request that changes the library returns the library snapshot.
protocol RemappingGateway: Sendable {
  /// Returns the snapshot of the profile library.
  func remappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Returns the profile with the identifier.
  func remappingProfile(id: UUID) async throws -> RemappingProfile
  /// Adds `profile` to the library.
  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Saves `profile`; `expectedCurrent` is the stored version that the edit started from.
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Adds an imported profile to the library.
  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Deletes the profile with the identifier.
  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Deletes the damaged profile that the issue describes.
  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Resets the profile library that the issue describes.
  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Activates the profile; `allowEmpty` accepts a profile that produces no output.
  func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Deactivates the active profile of the controller model with the vendor and product IDs.
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Deactivates the profile with the identifier.
  func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Returns the state of the Post Event access.
  func remappingPostEventAccess() async throws -> RemappingPostEventAccessState
  /// Asks macOS for the Post Event access and returns its state.
  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState
  /// Pairs two Joy-Con controllers under the profile.
  func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
  /// Unpairs the Joy-Con session.
  func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload
}

/// The virtual output requests of the service: the virtual HID profile, the controller server and
/// tuning, and suspending and disconnecting controllers.
protocol VirtualOutputGateway: Sendable {
  /// Sets the virtual HID profile override. `scope` is the controller's model, or the one
  /// controller by its unit ID.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID,
    for selector: ControllerReference,
    scope: VirtualHIDProfileOverrideScope
  ) async throws -> VirtualHIDProfileOverrideResult
  /// Resets the virtual HID profile override of the controller to automatic selection.
  func resetVirtualHIDProfileOverride(
    for selector: ControllerReference,
    scope: VirtualHIDProfileOverrideScope
  ) async throws -> VirtualHIDProfileOverrideResult
  /// Returns every controller model, connected or not, to automatic virtual HID profile selection;
  /// false when the service could not apply it.
  func resetAllVirtualHIDProfileOverrides() async throws -> Bool
  /// Sets the server of the controller model.
  func setControllerServer(
    model: ControllerModelID,
    server: ControllerServer
  ) async throws -> ControllerServerResult
  /// Sets a tuning value of the controller model; nil clears it.
  func setControllerTuning(
    model: ControllerModelID,
    key: ControllerTuning.Key,
    value: Double?
  ) async throws -> ControllerTuningResult
  /// Suspends the controller.
  func suspendController(_ selector: ControllerReference) async throws -> ControllerSuspendResult
  /// Resumes the controller.
  func resumeController(_ selector: ControllerReference) async throws -> ControllerResumeResult
  /// Disconnects the wireless link of the controller.
  func disconnectWirelessController(
    _ selector: ControllerReference
  ) async throws -> WirelessControllerDisconnectResult
}

/// The recalibration request of the service.
protocol ControllerRecalibrationGateway: Sendable {
  /// Runs a recalibration step on the controller, or resets its stored calibration.
  func recalibrateController(
    _ controller: ControllerReference,
    action: ControllerRecalibrationAction
  ) async throws -> ControllerRecalibrationResult
}

/// Every request of the service that the app makes.
protocol ApplicationServiceGateway: RuntimeStatusGateway, ControllerDiagnosticsGateway,
  RemappingGateway, VirtualOutputGateway, ControllerRecalibrationGateway
{}

/// Why a gateway request failed.
enum ApplicationServiceGatewayError: Error, LocalizedError, Sendable, Equatable {
  /// The service rejected the change of the controller session.
  case controllerSessionChangeRejected

  /// The localized message of the failure.
  var errorDescription: String? {
    switch self {
    case .controllerSessionChangeRejected:
      return OJDLocalized.string(
        "ui.error.controllerSessionChangeRejected"
      )
    }
  }
}

/// Sends the app's requests to the service over the local connection, connecting on demand.
package actor ApplicationServiceClientGateway: ApplicationServiceGateway {
  /// The service client.
  let client: ApplicationServiceClient
  /// The task that connects the client, while one runs.
  var connectionTask: Task<Void, Never>?

  /// Creates the gateway on a client.
  package init(client: ApplicationServiceClient = ApplicationServiceClient()) {
    self.client = client
  }
}

extension ApplicationServiceClientGateway: ControllerRecalibrationGateway {
  /// Runs a recalibration step on a controller, or resets its stored calibration.
  ///
  /// - Parameters:
  ///   - controller: The controller.
  ///   - action: The step to run, or the reset.
  /// - Returns: What the service stored or cleared, or why it stored nothing.
  /// - Throws: The error of the request.
  func recalibrateController(
    _ controller: ControllerReference,
    action: ControllerRecalibrationAction
  ) async throws -> ControllerRecalibrationResult {
    await ensureConnection()
    return try await client.recalibrateController(controller, action: action)
  }
}

extension ApplicationServiceClientGateway: InputTestDeviceGateway {
  /// Sends an output command to a controller.
  ///
  /// - Parameters:
  ///   - command: The output command.
  ///   - selector: The controller.
  /// - Returns: The result, which says whether the controller received the command.
  /// - Throws: The error of the request.
  func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for selector: ControllerReference
  ) async throws -> ControllerOutputResult {
    await ensureConnection()
    return try await client.sendControllerOutput(
      command,
      for: selector
    )
  }

  /// Previews a color on the controller's lighting until the preview is released.
  ///
  /// - Parameters:
  ///   - selector: The controller.
  ///   - token: Names the preview.
  ///   - red: The red component, 0 to 255.
  ///   - green: The green component, 0 to 255.
  ///   - blue: The blue component, 0 to 255.
  /// - Returns: Whether the request succeeded.
  /// - Throws: The error of the request.
  func previewColor(
    for selector: ControllerReference,
    token: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    await ensureConnection()
    return try await client.previewPhysicalColor(
      for: selector,
      token: token,
      red: red,
      green: green,
      blue: blue
    )
  }

  /// Ends the preview of `token` so that the controller shows its own color.
  ///
  /// - Parameters:
  ///   - selector: The controller.
  ///   - token: Names the preview.
  /// - Returns: Whether the request succeeded.
  /// - Throws: The error of the request.
  func releaseColorPreview(for selector: ControllerReference, token: UUID) async throws -> Bool {
    await ensureConnection()
    return try await client.releasePhysicalColorPreview(
      for: selector,
      token: token
    )
  }

  /// Reads or changes the Motion calibration of a controller.
  ///
  /// - Parameters:
  ///   - selector: The controller.
  ///   - command: The command to send, or nil to only read the status.
  /// - Returns: The calibration status after the command.
  /// - Throws: The error of the request.
  func motionCalibration(
    for selector: ControllerReference,
    command: RemappingMotionCalibrationCommand?
  ) async throws -> RemappingMotionCalibrationStatus {
    await ensureConnection()
    return try await client.remappingMotionCalibration(for: selector, command: command)
  }
}
