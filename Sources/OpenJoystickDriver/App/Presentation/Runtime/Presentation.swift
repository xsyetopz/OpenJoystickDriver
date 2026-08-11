import Foundation
import OpenJoystickDriverKit

enum RuntimeLoadState: Sendable {
  case loading
  case available
  case unavailable(String)
  case error(String)
}

enum RuntimePermissionState: String, Sendable {
  case granted
  case denied
  case unknown
  case unavailable
}

struct RuntimePermissionSummary: Sendable {
  let inputMonitoring: RuntimePermissionState
  let accessibility: RuntimePermissionState

  init(inputMonitoring: RuntimePermissionState, accessibility: RuntimePermissionState) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
  }

  init(status: ApplicationServiceStatusPayload) {
    self.init(
      inputMonitoring: Self.state(for: status.inputMonitoring),
      accessibility: Self.state(for: status.accessibility)
    )
  }

  init(snapshot: PermissionManager.Snapshot) {
    self.init(
      inputMonitoring: Self.state(for: snapshot.inputMonitoring),
      accessibility: Self.state(for: snapshot.accessibility)
    )
  }

  var isReady: Bool { inputMonitoring == .granted && accessibility == .granted }

  var inputMonitoringLabel: String { RuntimePresentation.permissionLabel(inputMonitoring) }

  var accessibilityLabel: String { RuntimePresentation.permissionLabel(accessibility) }

  private static func state(for value: String) -> RuntimePermissionState {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "granted": return .granted
    case "denied": return .denied
    case "unknown": return .unknown
    default: return .unavailable
    }
  }

  private static func state(for value: PermissionManager.AccessState) -> RuntimePermissionState {
    switch value {
    case .granted: return .granted
    case .denied: return .denied
    case .unknown: return .unknown
    }
  }
}

enum RuntimeOutputState: String, Sendable {
  case ready
  case unavailable
  case error
  case unknown
}

enum RuntimeReadiness: String, Sendable {
  case ready
  case needsAttention
  case noController
}

struct RuntimeStatusPresentation: Sendable {
  let permissions: RuntimePermissionSummary
  let devices: [ApplicationServiceDeviceDescription]
  let compatibilityIdentity: CompatibilityIdentity?
  let compatibilityLabel: String
  let outputState: RuntimeOutputState
  let outputDetail: String?
  let postEventAccess: RemappingPostEventAccessState?
  let requiresPostEventAccess: Bool?
  let readiness: RuntimeReadiness

  init(
    payload: ApplicationServiceStatusPayload,
    postEventAccess: RemappingPostEventAccessState? = nil,
    requiresPostEventAccess: Bool? = nil
  ) {
    let permissions = RuntimePermissionSummary(status: payload)
    let identity = payload.compatibilityIdentity.flatMap(CompatibilityIdentity.init(rawValue:))
    let outputState: RuntimeOutputState
    if payload.userSpaceVirtualDeviceStatus?.lowercased().hasPrefix("error:") == true {
      outputState = .error
    } else if payload.userSpaceVirtualDeviceEnabled == nil {
      outputState = .unknown
    } else if payload.userSpaceVirtualDeviceEnabled == false {
      outputState = .unavailable
    } else {
      outputState = .ready
    }

    self.permissions = permissions
    self.devices = payload.connectedDevices
    self.compatibilityIdentity = identity
    self.compatibilityLabel = identity.map(RuntimePresentation.compatibilityLabel) ?? "Unavailable"
    self.outputState = outputState
    self.outputDetail = RuntimePresentation.outputDetail(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus
    )
    self.postEventAccess = postEventAccess
    self.requiresPostEventAccess = requiresPostEventAccess
    self.readiness = Self.readiness(
      permissions: permissions,
      outputState: outputState,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess,
      deviceCount: payload.connectedDevices.count
    )
  }

  func applyingPostEventAccess(_ state: RemappingPostEventAccessState?) -> Self {
    Self(
      permissions: permissions,
      devices: devices,
      compatibilityIdentity: compatibilityIdentity,
      compatibilityLabel: compatibilityLabel,
      outputState: outputState,
      outputDetail: outputDetail,
      postEventAccess: state,
      requiresPostEventAccess: requiresPostEventAccess,
      readiness: Self.readiness(
        permissions: permissions,
        outputState: outputState,
        postEventAccess: state,
        requiresPostEventAccess: requiresPostEventAccess,
        deviceCount: devices.count
      )
    )
  }

  func applyingPermissions(_ permissions: RuntimePermissionSummary) -> Self {
    Self(
      permissions: permissions,
      devices: devices,
      compatibilityIdentity: compatibilityIdentity,
      compatibilityLabel: compatibilityLabel,
      outputState: outputState,
      outputDetail: outputDetail,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess,
      readiness: Self.readiness(
        permissions: permissions,
        outputState: outputState,
        postEventAccess: postEventAccess,
        requiresPostEventAccess: requiresPostEventAccess,
        deviceCount: devices.count
      )
    )
  }

  func applyingCompatibilityIdentity(_ identity: CompatibilityIdentity?) -> Self {
    Self(
      permissions: permissions,
      devices: devices,
      compatibilityIdentity: identity,
      compatibilityLabel: identity.map(RuntimePresentation.compatibilityLabel) ?? "Checking",
      outputState: outputState,
      outputDetail: outputDetail,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess,
      readiness: Self.readiness(
        permissions: permissions,
        outputState: outputState,
        postEventAccess: postEventAccess,
        requiresPostEventAccess: requiresPostEventAccess,
        deviceCount: devices.count
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
      compatibilityIdentity: compatibilityIdentity,
      compatibilityLabel: compatibilityLabel,
      outputState: outputState,
      outputDetail: outputDetail,
      postEventAccess: postEventAccess,
      requiresPostEventAccess: requiresPostEventAccess,
      readiness: Self.readiness(
        permissions: permissions,
        outputState: outputState,
        postEventAccess: postEventAccess,
        requiresPostEventAccess: requiresPostEventAccess,
        deviceCount: devices.count
      )
    )
  }

  var postEventAccessLabel: String { RuntimePresentation.postEventAccessLabel(postEventAccess) }

  var readinessLabel: String { RuntimePresentation.readinessLabel(readiness) }

  var deviceCountLabel: String { RuntimePresentation.deviceCountLabel(devices.count) }

  private init(
    permissions: RuntimePermissionSummary,
    devices: [ApplicationServiceDeviceDescription],
    compatibilityIdentity: CompatibilityIdentity?,
    compatibilityLabel: String,
    outputState: RuntimeOutputState,
    outputDetail: String?,
    postEventAccess: RemappingPostEventAccessState?,
    requiresPostEventAccess: Bool?,
    readiness: RuntimeReadiness
  ) {
    self.permissions = permissions
    self.devices = devices
    self.compatibilityIdentity = compatibilityIdentity
    self.compatibilityLabel = compatibilityLabel
    self.outputState = outputState
    self.outputDetail = outputDetail
    self.postEventAccess = postEventAccess
    self.requiresPostEventAccess = requiresPostEventAccess
    self.readiness = readiness
  }

  private static func readiness(
    permissions: RuntimePermissionSummary,
    outputState: RuntimeOutputState,
    postEventAccess: RemappingPostEventAccessState?,
    requiresPostEventAccess: Bool?,
    deviceCount: Int
  ) -> RuntimeReadiness {
    guard permissions.isReady, outputState == .ready else { return .needsAttention }
    guard let requiresPostEventAccess else { return .needsAttention }
    guard !requiresPostEventAccess || postEventAccess == .granted else { return .needsAttention }
    return deviceCount == 0 ? .noController : .ready
  }

  private static func requiresPostEventAccess(
    in snapshot: ApplicationServiceRemappingSnapshotPayload
  ) -> Bool {
    snapshot.activeProfiles.contains { activeProfile in
      guard let profile = snapshot.profiles.first(where: { $0.id == activeProfile.profileID })
      else {
        // An active profile without its record is an incomplete snapshot.  Keep the readiness
        // indicator conservative rather than claiming output is safe to dispatch.
        return true
      }
      return profile.hasOutputMappings
    }
  }
}

extension RemappingProfile {
  var hasOutputMappings: Bool {
    if !bindings.isEmpty || !chords.isEmpty || !sequences.isEmpty { return true }
    return layers.contains { layer in
      !layer.bindings.isEmpty || !layer.chords.isEmpty || !layer.sequences.isEmpty
    }
  }
}

enum RuntimeStatusState: Sendable {
  case loading
  case available(RuntimeStatusPresentation)
  case unavailable(String)
  case error(String)
}

enum RuntimeRemappingState: Sendable {
  case loading
  case available(ApplicationServiceRemappingSnapshotPayload)
  case unavailable(String)
  case error(String)
}

enum RuntimeActiveProfileState: Sendable, Equatable {
  case loading
  case noProfile
  case profile(String)
  case unavailable(String)
  case error(String)
}

enum RuntimePermissionLoadState: Sendable {
  case loading
  case unavailable
  case requesting
  case available(RuntimePermissionSummary)
  case error(String)
}

enum RuntimePostEventAccessLoadState: Sendable {
  case loading
  case requesting
  case available(RemappingPostEventAccessState)
  case unavailable(String)
  case error(String)
}

enum RuntimeCompatibilityState: Sendable {
  case loading
  case available(CompatibilityIdentity)
  case unavailable(String)
  case error(String)
}

enum RuntimeMutationState: Sendable {
  case idle
  case saving
  case succeeded(profileID: UUID)
  case completed(RuntimeMutationOperation)
  case conflict(profileID: UUID?)
  case error(String)
}

enum RuntimeMutationOperation: Sendable, Equatable {
  case create(profileID: UUID)
  case update(profileID: UUID)
  case importProfile(profileID: UUID)
  case delete(profileID: UUID)
  case activate(profileID: UUID)
  case deactivate(profileID: UUID?)

  var profileID: UUID? {
    switch self {
    case .create(let profileID), .update(let profileID), .importProfile(let profileID),
      .delete(let profileID), .activate(let profileID):
      return profileID
    case .deactivate(let profileID): return profileID
    }
  }
}

enum RuntimeInputCaptureState: Sendable {
  case idle
  case listening(RuntimeDeviceSelector)
  case received(RuntimeDeviceSelector, DeviceInputState)
  case detected(RuntimeDeviceSelector, DeviceInputState, RemappingSource)
  case unavailable(RuntimeDeviceSelector, String)
  case error(RuntimeDeviceSelector, String)
}
