import Foundation
import OpenJoystickDriverKit

extension RuntimeStatusPresentation {

  func applyingPostEventAccess(_ state: RemappingPostEventAccessState?) -> Self {
    Self(
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
  }

  func applyingPermissions(_ permissions: RuntimePermissionSummary) -> Self {

    Self(
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
  }

  func applyingRemappingSnapshot(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    postEventAccess: RemappingPostEventAccessState?
  ) -> Self {
    let requiresPostEventAccess = Self.requiresPostEventAccess(in: snapshot)
    return Self(
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
  }

  var postEventAccessLabel: String { RuntimePresentation.postEventAccessLabel(postEventAccess) }

  var readinessLabel: String { RuntimePresentation.readinessLabel(readiness) }

  var deviceCountLabel: String { RuntimePresentation.deviceCountLabel(devices.count) }

  /// Service-wide problems with stored virtual HID profile overrides, one line each.
  var virtualHIDProfileOverrideStoreMessages: [String] {
    var messages: [String] = []
    if let virtualHIDProfileOverrideError {
      messages.append(
        OJDLocalized.formatted(
          "virtualProfile.storeError",
          virtualHIDProfileOverrideError
        )
      )
    }
    return messages
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.permissions == rhs.permissions
      && lhs.devices.elementsEqual(rhs.devices, by: deviceDescriptionsEqual)
      && lhs.virtualHIDProfileOverrideError == rhs.virtualHIDProfileOverrideError
      && lhs.outputState == rhs.outputState && lhs.outputDetail == rhs.outputDetail
      && lhs.postEventAccess == rhs.postEventAccess
      && lhs.requiresPostEventAccess == rhs.requiresPostEventAccess
      && lhs.readiness == rhs.readiness
  }

  private static func deviceDescriptionsEqual(
    _ lhs: ApplicationServiceDeviceDescription,
    _ rhs: ApplicationServiceDeviceDescription
  ) -> Bool {
    lhs.runtimeIdentifier == rhs.runtimeIdentifier && lhs.name == rhs.name
      && lhs.vendorID == rhs.vendorID && lhs.productID == rhs.productID
      && lhs.connection == rhs.connection && lhs.discoverySource == rhs.discoverySource
      && lhs.physicalOwnership == rhs.physicalOwnership
      && lhs.duplicateExposureRisk == rhs.duplicateExposureRisk
      && lhs.serialNumber == rhs.serialNumber && lhs.protocolBinding == rhs.protocolBinding
      && lhs.quirks == rhs.quirks && lhs.inputEndpoint == rhs.inputEndpoint
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
  }

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

  static func requiresPostEventAccess(
    in snapshot: ApplicationServiceRemappingSnapshotPayload
  ) -> Bool {
    snapshot.activeProfiles.contains { activeProfile in
      guard let profile = snapshot.profiles.first(where: { $0.id == activeProfile.profileID })
      else {
        // An active profile without its record is an incomplete snapshot.  Keep the readiness
        // indicator conservative rather than claiming output is safe to dispatch.
        return true
      }
      return profile.hasOutputMappings && profile.requiresSystemInputAccess
    }
  }
}
