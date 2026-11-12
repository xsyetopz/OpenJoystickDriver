import Combine
import Foundation
import OpenJoystickDriverKit

extension ApplicationServiceClientGateway {

  /// Reads the status of the service after connecting on demand.
  ///
  /// - Returns: The status the service reports.
  func status() async throws -> ApplicationServiceStatusPayload {
    await ensureConnection()
    return try await client.getStatus()
  }

  /// Reads the diagnostics of the virtual devices after connecting on demand.
  ///
  /// - Returns: The diagnostics the service reports.
  func virtualDeviceDiagnostics() async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    await ensureConnection()
    return try await client.getVirtualDeviceDiagnostics()
  }

  /// Reads the frame timings of every connected controller after connecting on demand.
  ///
  /// - Parameter lastSeconds: The number of latest seconds to read; nil reads all kept frames.
  /// - Returns: The frame timings the service reports.
  /// - Throws: The error of the request.
  func frameTimings(lastSeconds: Int?) async throws -> ApplicationServiceFrameTimingsPayload {
    await ensureConnection()
    return try await client.getFrameTimings(lastSeconds: lastSeconds)
  }

  /// Asks macOS for the permissions that the service requires.
  ///
  /// - Returns: The state of the permissions after the request.
  func requestPermissions() async throws -> PermissionManager.Snapshot {
    await ensureConnection()
    return try await client.requestRequiredAccess()
  }

  /// Asks macOS for one permission.
  ///
  /// - Parameter requirement: The permission to request.
  /// - Returns: The state of the permissions after the request.
  /// - Throws: The error of the request.
  func requestPermission(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot {
    await ensureConnection()
    return try await client.requestAccess(requirement)
  }

  /// Asks macOS for Bluetooth access.
  ///
  /// - Returns: The state of the access after the request.
  func requestBluetoothAccess() async throws -> BluetoothAccessState {
    await ensureConnection()
    return try await client.requestBluetoothAccess()
  }

  /// Reads the latest input state of a controller.
  ///
  /// - Parameter selector: The controller.
  /// - Returns: The state, or nil when the service has none.
  /// - Throws: The error of the request.
  func controllerState(for selector: ControllerReference) async throws -> ControllerState? {
    await ensureConnection()
    return try await client.controllerState(for: selector)
  }

  /// Reads the values the virtual gamepad of a controller last reported.
  ///
  /// - Parameter selector: The controller.
  /// - Returns: The values, or nil when no virtual gamepad publishes the controller.
  /// - Throws: The error of the request.
  func virtualOutputState(
    for selector: ControllerReference
  ) async throws -> ApplicationServiceVirtualOutputState? {
    await ensureConnection()
    return try await client.virtualOutputState(for: selector)
  }

  /// Reads the packet log of a controller.
  ///
  /// - Parameter selector: The controller.
  /// - Returns: The logged packets.
  /// - Throws: The error of the request.
  func packetLog(for selector: ControllerReference) async throws -> [PacketLogEntry] {
    await ensureConnection()
    return try await client.packetLog(for: selector)
  }

  /// Reads the snapshot of the profile library.
  ///
  /// - Returns: The snapshot the service reports.
  func remappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.getRemappingSnapshot()
  }

  /// Reads one profile of the library.
  ///
  /// - Parameter id: The identifier of the profile.
  /// - Returns: The profile.
  /// - Throws: The error of the request.
  func remappingProfile(id: UUID) async throws -> RemappingProfile {
    await ensureConnection()
    return try await client.getRemappingProfile(id: id)
  }

  /// Adds a profile to the library.
  ///
  /// - Parameter profile: The profile to add.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func createRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.createRemappingProfile(profile)
  }

  /// Saves an edited profile.
  ///
  /// - Parameters:
  ///   - profile: The profile to save.
  ///   - expectedCurrent: The stored version that the edit started from.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func updateRemappingProfile(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.updateRemappingProfile(profile, expectedCurrent: expectedCurrent)
  }

  /// Adds an imported profile to the library.
  ///
  /// - Parameter profile: The imported profile.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func importRemappingProfile(
    _ profile: RemappingProfile
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.importRemappingProfile(profile)
  }

  /// Deletes a profile from the library.
  ///
  /// - Parameter id: The identifier of the profile.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func deleteRemappingProfile(id: UUID) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deleteRemappingProfile(id: id)
  }

  /// Deletes the damaged profile that a library issue describes.
  ///
  /// - Parameter issueID: The identifier of the issue.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func deleteDamagedRemappingProfile(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deleteDamagedRemappingProfile(issueID: issueID)
  }

  /// Resets the profile library that a library issue describes.
  ///
  /// - Parameter issueID: The identifier of the issue.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func resetRemappingProfileLibrary(
    issueID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.resetRemappingProfileLibrary(issueID: issueID)
  }

  /// Activates a profile.
  ///
  /// - Parameters:
  ///   - id: The identifier of the profile.
  ///   - allowEmpty: Whether a profile that produces no output is accepted.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func activateRemappingProfile(
    id: UUID,
    allowEmpty: Bool
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.activateRemappingProfile(id: id, allowEmpty: allowEmpty)
  }

  /// Deactivates the active profile of a controller model.
  ///
  /// - Parameters:
  ///   - vendorID: The USB vendor ID of the model.
  ///   - productID: The USB product ID of the model.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func deactivateRemappingProfile(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deactivateRemappingProfile(vendorID: vendorID, productID: productID)
  }

  /// Deactivates a profile by its identifier.
  ///
  /// - Parameter profileID: The identifier of the profile.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func deactivateRemappingProfile(
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.deactivateRemappingProfile(profileID: profileID)
  }

  /// Reads the state of the Post Event access.
  ///
  /// - Returns: The state of the access.
  func remappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    await ensureConnection()
    return try await client.getRemappingPostEventAccess()
  }

  /// Asks macOS for the Post Event access.
  ///
  /// - Returns: The state of the access after the request.
  func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    await ensureConnection()
    return try await client.requestRemappingPostEventAccess()
  }

  /// Pairs two Joy-Con controllers under a profile.
  ///
  /// - Parameters:
  ///   - left: The left Joy-Con.
  ///   - right: The right Joy-Con.
  ///   - profileID: The identifier of the profile the pair uses.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func pairRemappingJoyCons(
    left: ControllerReference,
    right: ControllerReference,
    profileID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.pairRemappingJoyCons(left: left, right: right, profileID: profileID)
  }

  /// Unpairs a Joy-Con session.
  ///
  /// - Parameter sessionID: The identifier of the session.
  /// - Returns: The snapshot of the library after the change.
  /// - Throws: The error of the request.
  func unpairRemappingJoyCons(
    sessionID: UUID
  ) async throws -> ApplicationServiceRemappingSnapshotPayload {
    await ensureConnection()
    return try await client.unpairRemappingJoyCons(sessionID: sessionID)
  }

  /// Sets the virtual HID profile override of a controller.
  ///
  /// - Parameters:
  ///   - profile: The virtual HID profile to publish.
  ///   - selector: The controller.
  ///   - scope: Whether the override covers the controller's model or only this unit.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID,
    for selector: ControllerReference,
    scope: VirtualHIDProfileOverrideScope
  ) async throws -> VirtualHIDProfileOverrideResult {
    await ensureConnection()
    return try await client.setVirtualHIDProfileOverride(
      profile.rawValue,
      for: selector,
      unit: scope == .unit
    )
  }

  /// Resets the virtual HID profile override of a controller to automatic selection.
  ///
  /// - Parameters:
  ///   - selector: The controller.
  ///   - scope: Whether the reset covers the controller's model or only this unit.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func resetVirtualHIDProfileOverride(
    for selector: ControllerReference,
    scope: VirtualHIDProfileOverrideScope
  ) async throws -> VirtualHIDProfileOverrideResult {
    await ensureConnection()
    return try await client.resetVirtualHIDProfileOverride(for: selector, unit: scope == .unit)
  }

  /// Asks the service to announce a test notification.
  ///
  /// - Returns: How the announcement ended.
  func requestTestNotification() async throws -> TestNotificationOutcome {
    await ensureConnection()
    return try await client.sendTestNotification()
  }

  /// Answers an announcement that this app took from the service.
  ///
  /// - Parameters:
  ///   - announcement: The identifier of the announcement.
  ///   - outcome: How the notification ended.
  /// - Returns: The service's answer; false when the announcement is not pending.
  /// - Throws: The error of the request.
  func reportTestNotification(
    _ announcement: UUID,
    outcome: TestNotificationOutcome
  ) async throws -> Bool {
    await ensureConnection()
    return try await client.reportTestNotificationResult(
      announcement: announcement,
      outcome: outcome
    )
  }

  /// Returns every controller model to automatic virtual HID profile selection.
  ///
  /// - Returns: False when the service could not apply it.
  func resetAllVirtualHIDProfileOverrides() async throws -> Bool {
    await ensureConnection()
    return try await client.resetSettings()
  }

  /// Sets the server of a controller model.
  ///
  /// - Parameters:
  ///   - model: The controller model.
  ///   - server: The server that serves the model.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func setControllerServer(
    model: ControllerModelID,
    server: ControllerServer
  ) async throws -> ControllerServerResult {
    await ensureConnection()
    return try await client.setControllerServer(model: model, server: server)
  }

  /// Sets a tuning value of a controller model.
  ///
  /// - Parameters:
  ///   - model: The controller model.
  ///   - key: The tuning key.
  ///   - value: The value; nil clears it.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func setControllerTuning(
    model: ControllerModelID,
    key: ControllerTuning.Key,
    value: Double?
  ) async throws -> ControllerTuningResult {
    await ensureConnection()
    return try await client.setControllerTuning(model: model, key: key, value: value)
  }

  /// Suspends a controller.
  ///
  /// - Parameter selector: The controller.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func suspendController(_ selector: ControllerReference) async throws -> ControllerSuspendResult {
    await ensureConnection()
    return try await client.suspendController(selector)
  }

  /// Resumes a controller.
  ///
  /// - Parameter selector: The controller.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func resumeController(_ selector: ControllerReference) async throws -> ControllerResumeResult {
    await ensureConnection()
    return try await client.resumeController(selector)
  }

  /// Disconnects the wireless link of a controller.
  ///
  /// - Parameter selector: The controller.
  /// - Returns: The result the service reports.
  /// - Throws: The error of the request.
  func disconnectWirelessController(
    _ selector: ControllerReference
  ) async throws -> WirelessControllerDisconnectResult {
    await ensureConnection()
    return try await client.disconnectWirelessController(selector)
  }

  /// Connects the client to the service unless it is connected.
  ///
  /// Concurrent callers wait for the same connection.
  func ensureConnection() async {
    guard !client.isConnected else { return }
    if let connectionTask {
      await connectionTask.value
      return
    }
    let client = self.client
    let task = Task { await client.connect() }
    connectionTask = task
    await task.value
    connectionTask = nil
  }
}
