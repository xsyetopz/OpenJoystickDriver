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

struct SourceOption: Hashable {
  let source: RemappingSource
  let title: String

  static func options(including current: RemappingSource? = nil) -> [Self] {
    var options = all
    if let current, !options.contains(where: { $0.source == current }) {
      options.append(Self(source: current, title: RuntimePresentation.sourceLabel(current)))
    }
    return options
  }

  static let all: [Self] = {
    let buttons: [RemappingSource] = RemappingButton.allCases.compactMap { button in
      // The Guide/Home control remains reserved for the operating system in the ordinary UI.
      guard button != .guide else { return nil }
      return .button(button)
    }
    let dpad: [RemappingSource] = RemappingDpadDirection.allCases.map { .dpad($0) }
    let axes: [RemappingSource] = RemappingAxis.allCases.flatMap { axis in
      [.axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive)]
    }
    return (buttons + dpad + axes).map {
      .init(source: $0, title: RuntimePresentation.sourceLabel($0))
    }
  }()
}

struct DestinationOption: Hashable {
  let destination: RemappingDestination
  let title: String

  static func options(for source: RemappingSource, including current: RemappingDestination? = nil)
    -> [Self]
  {
    var options = all.filter { isCompatible($0.destination, with: source) }
    if let current, isCompatible(current, with: source),
      !options.contains(where: { $0.destination == current })
    {
      options.append(
        Self(destination: current, title: RuntimePresentation.destinationLabel(current))
      )
    }
    return options
  }

  static let all: [Self] = {
    // Keep the ordinary keyboard destination first so source changes can fall back to a useful,
    // conventional choice instead of an arbitrary enum ordering.  Modifier combinations are
    // limited to arrow and function keys; capture can still preserve any custom destination.
    let keyboardKeys =
      [RemappingKeyboardKey.space] + RemappingKeyboardKey.allCases.filter { $0 != .space }
    let plainKeyboard = keyboardKeys.map { key in
      RemappingDestination.keyboard(key: key, modifiers: [])
    }
    let modifierGroups: [Set<RemappingKeyModifier>] =
      [[.command], [.control], [.option], [.shift]] + [
        [.command, .control], [.command, .option], [.command, .shift]
      ] + [[.control, .option], [.control, .shift], [.option, .shift]]
    let modifiedKeyboardKeys: [RemappingKeyboardKey] =
      [.arrowUp, .arrowDown, .arrowLeft, .arrowRight] + [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10
      ] + [.f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20]
    let modifiedKeyboard = modifiedKeyboardKeys.flatMap { key in
      modifierGroups.map { modifiers in
        RemappingDestination.keyboard(key: key, modifiers: modifiers)
      }
    }
    let keyboard = (plainKeyboard + modifiedKeyboard).map { destination in
      Self(destination: destination, title: RuntimePresentation.destinationLabel(destination))
    }
    let mouse = RemappingMouseButton.allCases.map { button in
      let destination = RemappingDestination.mouseButton(button)
      return Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination)
      )
    }
    let pointerAxes: [RemappingPointerAxis] = [.x, .y]
    let pointer = pointerAxes.flatMap { axis in
      [RemappingDestination.mouseMovement(axis), RemappingDestination.scroll(axis)]
    }.map { destination in
      Self(destination: destination, title: RuntimePresentation.destinationLabel(destination))
    }
    return keyboard + mouse + pointer
  }()

  private static func isCompatible(
    _ destination: RemappingDestination,
    with source: RemappingSource
  ) -> Bool {
    switch source {
    case .axis: return destination.isContinuous
    case .axisDirection, .button, .dpad: return !destination.isContinuous
    }
  }
}

enum RuntimeProfileDraftError: Error, LocalizedError, Equatable, Sendable {
  case bindingNotFound(UUID)
  case validation(RemappingValidationError)

  var errorDescription: String? {
    switch self {
    case .bindingNotFound: return "The selected assignment is no longer available."
    case .validation: return "Review the assignments before saving this profile."
    }
  }
}

struct RuntimeProfileDraft: Sendable, Equatable {
  let profile: RemappingProfile

  func validatedProfile() throws -> RemappingProfile { try Self.validate(profile) }

  func settingDestination(_ destination: RemappingDestination, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: destination,
        axisTuning: binding.axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap
      )
    }
  }

  func settingSource(_ source: RemappingSource, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      let tuning: RemappingAxisTuning?
      switch source {
      case .axis, .axisDirection: tuning = binding.axisTuning ?? .default
      case .button, .dpad: tuning = nil
      }
      let destination = Self.destination(for: source, preserving: binding.destination)
      return RemappingBinding(
        id: binding.id,
        source: source,
        destination: destination,
        axisTuning: tuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap
      )
    }
  }

  private static func destination(
    for source: RemappingSource,
    preserving current: RemappingDestination
  ) -> RemappingDestination {
    let options = DestinationOption.options(for: source, including: current)
    if let preserved = options.first(where: { $0.destination == current }) {
      return preserved.destination
    }
    return options.first?.destination ?? current
  }

  func settingAxisTuning(_ axisTuning: RemappingAxisTuning?, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        axisTuning: axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap
      )
    }
  }

  func addingBinding(
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil
  ) throws -> Self {
    let tuning: RemappingAxisTuning?
    switch source {
    case .axis, .axisDirection: tuning = axisTuning ?? .default
    case .button, .dpad: tuning = nil
    }
    let binding = RemappingBinding(source: source, destination: destination, axisTuning: tuning)
    var bindings = profile.bindings
    bindings.append(binding)
    let candidate = RemappingProfile(
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func removingBinding(_ bindingID: UUID) throws -> Self {
    guard profile.bindings.contains(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    let bindings = profile.bindings.filter { $0.id != bindingID }
    let candidate = RemappingProfile(
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  private func replacingBinding(
    _ bindingID: UUID,
    _ makeBinding: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    guard let index = profile.bindings.firstIndex(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    var bindings = profile.bindings
    bindings[index] = makeBinding(bindings[index])
    let candidate = RemappingProfile(
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  private static func validate(_ profile: RemappingProfile) throws -> RemappingProfile {
    do {
      try profile.validate()
      return profile
    } catch let error as RemappingValidationError {
      throw RuntimeProfileDraftError.validation(error)
    } catch { throw RuntimeProfileDraftError.validation(.encodingFailed) }
  }
}
