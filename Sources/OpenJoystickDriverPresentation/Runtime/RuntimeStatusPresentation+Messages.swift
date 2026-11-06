import Foundation
import OpenJoystickDriverKit

extension RuntimeStatusPresentation {

  /// Returns `copy` with this presentation's unserved devices, which a presentation built from
  /// parts does not take.
  private func carryingUnservedDevices(to copy: Self) -> Self {
    var carrying = copy
    carrying.unservedDevices = unservedDevices
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

  /// Returns the presentation with whether the snapshot requires Post Event access, with
  /// `postEventAccess`, and with the readiness worked out again.
  func applyingRemappingSnapshot(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    postEventAccess: RemappingPostEventAccessState?
  ) -> Self {
    let requiresPostEventAccess = snapshot.requiresPostEventAccess
    return carryingUnservedDevices(
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

  /// The phrase for the number of connected controllers.
  var deviceCountLabel: String { RuntimePresentation.deviceCountLabel(devices.count) }

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
    lhs.sessionToken.rawValue == rhs.sessionToken.rawValue && lhs.name == rhs.name
      && lhs.vendorID == rhs.vendorID && lhs.productID == rhs.productID
      && lhs.connection == rhs.connection && lhs.discoverySource == rhs.discoverySource
      && lhs.physicalOwnership == rhs.physicalOwnership
      && lhs.duplicateExposureRisk == rhs.duplicateExposureRisk
      && lhs.serialNumber == rhs.serialNumber && lhs.protocolBinding == rhs.protocolBinding
      && lhs.parameters == rhs.parameters && lhs.inputEndpoint == rhs.inputEndpoint
      && lhs.outputEndpoint == rhs.outputEndpoint
      && lhs.needsSetConfiguration == rhs.needsSetConfiguration
      && lhs.postHandshakeSettleMs == rhs.postHandshakeSettleMs
      && lhs.preferredBackends == rhs.preferredBackends
      && lhs.physicalOutputCapabilities == rhs.physicalOutputCapabilities
      && lhs.inputHealth.state == rhs.inputHealth.state
      && lhs.inputHealth.reportFormat == rhs.inputHealth.reportFormat
      && lhs.inputHealth.lastReportAgeNanoseconds == rhs.inputHealth.lastReportAgeNanoseconds
      && lhs.inputHealth.failureReason == rhs.inputHealth.failureReason
      && lhs.inputHealth.recoveryCount == rhs.inputHealth.recoveryCount
      && lhs.virtualHIDProfile == rhs.virtualHIDProfile
      && lhs.recordServer == rhs.recordServer
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
