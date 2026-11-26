import Foundation
import OpenJoystickDriverKit

extension RuntimeStatusPresentation {

  /// Returns `copy` with this presentation's unserved devices, which a presentation built from
  /// parts does not take.
  private func carryingUnservedDevices(to copy: Self) -> Self {
    var carrying = copy
    carrying.unservedDevices = unservedDevices
    carrying.bluetoothAccess = bluetoothAccess
    return carrying
  }

  /// Returns the presentation with `state` as the Post Event access and the readiness worked out
  /// again.
  func applyingPostEventAccess(_ state: RemappingPostEventAccessState?) -> Self {
    carryingUnservedDevices(
      to: Self(
        permissions: permissions,
        devices: devices,
        virtualHIDProfileOverrideError: virtualHIDProfileOverrideError,
        outputState: outputState,
        outputDetail: outputDetail,
        postEventAccess: state,
        requiresPostEventAccess: requiresPostEventAccess,
        readiness: Self.readiness(
          permissions: permissions,
          outputState: outputState,
          postEventAccess: state,
          requiresPostEventAccess: requiresPostEventAccess,
          devices: devices
        )
      )
    )
  }

  /// Returns the presentation with `permissions` and the readiness worked out again.
  func applyingPermissions(_ permissions: RuntimePermissionSummary) -> Self {
    recomputingReadiness(
      permissions: permissions,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess
    )
  }

  /// Returns the presentation with whether the snapshot requires Post Event access, with
  /// `postEventAccess`, and with the readiness worked out again.
  func applyingRemappingSnapshot(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    postEventAccess: RemappingPostEventAccessState?
  ) -> Self {
    recomputingReadiness(
      permissions: permissions,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: snapshot.requiresPostEventAccess
    )
  }

  /// Returns the presentation with the given permissions and Post Event access, and with the
  /// readiness worked out again.
  private func recomputingReadiness(
    permissions: RuntimePermissionSummary,
    postEventAccess: RemappingPostEventAccessState?,
    requiresPostEventAccess: Bool?
  ) -> Self {
    carryingUnservedDevices(
      to: Self(
        permissions: permissions,
        devices: devices,
        virtualHIDProfileOverrideError: virtualHIDProfileOverrideError,
        outputState: outputState,
        outputDetail: outputDetail,
        postEventAccess: postEventAccess,
        requiresPostEventAccess: requiresPostEventAccess,
        readiness: Self.readiness(
          permissions: permissions,
          outputState: outputState,
          postEventAccess: postEventAccess,
          requiresPostEventAccess: requiresPostEventAccess,
          devices: devices
        )
      )
    )
  }

  /// The label of the Post Event access.
  var postEventAccessLabel: String { RuntimePresentation.postEventAccessLabel(postEventAccess) }

  /// The label of the readiness.
  var readinessLabel: String { RuntimePresentation.readinessLabel(readiness) }

  /// The phrase for the number of connected controllers, those OJD serves and those it does not.
  var deviceCountLabel: String {
    RuntimePresentation.deviceCountLabel(devices.count + unservedDevices.count)
  }

  /// Service-wide problems with stored virtual HID profile overrides, one line each.
  var virtualHIDProfileOverrideStoreMessages: [String] {
    var messages: [String] = []
    if let virtualHIDProfileOverrideError {
      messages.append(
        OJDLocalized.formatted(
          "ui.virtualProfile.storeError",
          virtualHIDProfileOverrideError
        )
      )
    }
    return messages
  }

  /// Returns whether two statuses show the same permissions, devices, output and readiness.
  ///
  /// The comparison reads every field of each device description, including the input health.
  ///
  /// - Parameters:
  ///   - lhs: The first status.
  ///   - rhs: The second status.
  /// - Returns: True when the fields that the messages read are equal.
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.permissions == rhs.permissions
      && lhs.devices.elementsEqual(rhs.devices, by: deviceDescriptionsEqual)
      && lhs.virtualHIDProfileOverrideError == rhs.virtualHIDProfileOverrideError
      && lhs.outputState == rhs.outputState && lhs.outputDetail == rhs.outputDetail
      && lhs.postEventAccess == rhs.postEventAccess
      && lhs.requiresPostEventAccess == rhs.requiresPostEventAccess
      && lhs.readiness == rhs.readiness
  }

  /// Returns whether two device descriptions are equal in every field, including the input health.
  private static func deviceDescriptionsEqual(
    _ lhs: ApplicationServiceDeviceDescription,
    _ rhs: ApplicationServiceDeviceDescription
  ) -> Bool {
    (
      lhs.sessionToken.rawValue, lhs.name, lhs.vendorID, lhs.productID, lhs.connection,
      lhs.discoverySource
    )
      == (
        rhs.sessionToken.rawValue, rhs.name, rhs.vendorID, rhs.productID, rhs.connection,
        rhs.discoverySource
      )
      && (
        lhs.physicalOwnership, lhs.duplicateExposureRisk, lhs.serialNumber,
        lhs.protocolBinding, lhs.parameters, lhs.inputEndpoint
      )
        == (
          rhs.physicalOwnership, rhs.duplicateExposureRisk, rhs.serialNumber,
          rhs.protocolBinding, rhs.parameters, rhs.inputEndpoint
        )
      && (
        lhs.outputEndpoint, lhs.needsSetConfiguration, lhs.postHandshakeSettleMs,
        lhs.preferredBackends, lhs.physicalOutputCapabilities
      )
        == (
          rhs.outputEndpoint, rhs.needsSetConfiguration, rhs.postHandshakeSettleMs,
          rhs.preferredBackends, rhs.physicalOutputCapabilities
        )
      && (
        lhs.inputHealth.state, lhs.inputHealth.reportFormat,
        lhs.inputHealth.lastReportAgeNanoseconds, lhs.inputHealth.failureReason,
        lhs.inputHealth.recoveryCount
      )
        == (
          rhs.inputHealth.state, rhs.inputHealth.reportFormat,
          rhs.inputHealth.lastReportAgeNanoseconds, rhs.inputHealth.failureReason,
          rhs.inputHealth.recoveryCount
        )
      && (lhs.virtualHIDProfile, lhs.recordServer) == (rhs.virtualHIDProfile, rhs.recordServer)
  }

  /// Returns the readiness.
  ///
  /// It needs attention until the permissions are granted, the output is ready, it is known whether
  /// Post Event access is required and, when it is, granted, and the input of every controller is
  /// healthy. With those met, it is Connect a Controller while none is connected, otherwise Ready.
  static func readiness(
    permissions: RuntimePermissionSummary,
    outputState: RuntimeOutputState,
    postEventAccess: RemappingPostEventAccessState?,
    requiresPostEventAccess: Bool?,
    devices: [ApplicationServiceDeviceDescription]
  ) -> RuntimeReadiness {
    guard permissions.isReady, outputState == .ready else { return .needsAttention }
    guard let requiresPostEventAccess else { return .needsAttention }
    guard !requiresPostEventAccess || postEventAccess == .granted else { return .needsAttention }
    guard devices.allSatisfy({ $0.inputHealth.state == .healthy }) else { return .needsAttention }
    return devices.isEmpty ? .noController : .ready
  }
}
