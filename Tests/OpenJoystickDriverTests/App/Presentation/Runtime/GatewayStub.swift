import Foundation
import OpenJoystickDriverKit

@testable import OpenJoystickDriver

func makeProfile(id: UUID = UUID(), name: String = "Test Profile") -> RemappingProfile {
  RemappingProfile(
    id: id,
    name: name,
    device: RemappingDeviceScope(vendorID: 0x1234, productID: 0x5678),
    applicationScope: .global,
    bindings: [
      RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
    ]
  )
}

func snapshot(
  profiles: [RemappingProfile],
  activeProfiles: [ApplicationServiceRemappingActiveProfilePayload] = [],
  postEventAccess: RemappingPostEventAccessState = .granted
) -> ApplicationServiceRemappingSnapshotPayload {
  ApplicationServiceRemappingSnapshotPayload(
    profiles: profiles,
    activeProfiles: activeProfiles,
    routes: [],
    postEventAccess: postEventAccess
  )
}

actor GatewayStub: ApplicationServiceGateway {
  var statusPayload: ApplicationServiceStatusPayload
  var snapshotPayload: ApplicationServiceRemappingSnapshotPayload
  var statusShouldFail: Bool
  let statusReadDelayNanoseconds: UInt64
  let inputState: DeviceInputState?
  let inputSequence: [DeviceInputState]?
  let inputStatesByRuntimeIdentifier: [String: DeviceInputState]
  var packetEntries: [PacketLogEntry]
  let packetSequence: [[PacketLogEntry]]?
  let packetEntriesByRuntimeIdentifier: [String: [PacketLogEntry]]
  let deviceReadDelaysNanoseconds: [String: UInt64]
  let updateShouldConflict: Bool
  let updateDelayNanoseconds: UInt64
  let deleteShouldFail: Bool
  let setIdentityResult: Bool
  let compatibilityReadDelayNanoseconds: UInt64
  var lastExpectedCurrent: RemappingProfile?
  var lastInputSelector: RuntimeDeviceSelector?
  var updateCallCount = 0
  var deleteCallCount = 0
  var lastDeletedProfileID: UUID?
  var inputReadCount = 0
  var packetReadCount = 0
  var statusCallCount = 0
  var activeStatusCalls = 0
  var maximumConcurrentStatusCalls = 0
  var remappingSnapshotCallCount = 0
  var setIdentityCallCount = 0
  var selectedIdentity: CompatibilityIdentity = .sdl2_3

  init(
    statusPayload: ApplicationServiceStatusPayload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    ),
    snapshotPayload: ApplicationServiceRemappingSnapshotPayload =
      ApplicationServiceRemappingSnapshotPayload(
        profiles: [],
        activeProfiles: [],
        routes: [],
        postEventAccess: .granted
      ),
    statusShouldFail: Bool = false,
    statusReadDelayNanoseconds: UInt64 = 0,
    inputState: DeviceInputState? = nil,
    inputSequence: [DeviceInputState]? = nil,
    inputStatesByRuntimeIdentifier: [String: DeviceInputState] = [:],
    packetEntries: [PacketLogEntry] = [],
    packetSequence: [[PacketLogEntry]]? = nil,
    packetEntriesByRuntimeIdentifier: [String: [PacketLogEntry]] = [:],
    deviceReadDelaysNanoseconds: [String: UInt64] = [:],
    updateShouldConflict: Bool = false,
    updateDelayNanoseconds: UInt64 = 0,
    deleteShouldFail: Bool = false,
    setIdentityResult: Bool = true,
    compatibilityReadDelayNanoseconds: UInt64 = 0
  ) {
    self.statusPayload = statusPayload
    self.snapshotPayload = snapshotPayload
    self.statusShouldFail = statusShouldFail
    self.statusReadDelayNanoseconds = statusReadDelayNanoseconds
    self.inputState = inputState
    self.inputSequence = inputSequence
    self.inputStatesByRuntimeIdentifier = inputStatesByRuntimeIdentifier
    self.packetEntries = packetEntries
    self.packetSequence = packetSequence
    self.packetEntriesByRuntimeIdentifier = packetEntriesByRuntimeIdentifier
    self.deviceReadDelaysNanoseconds = deviceReadDelaysNanoseconds
    self.updateShouldConflict = updateShouldConflict
    self.updateDelayNanoseconds = updateDelayNanoseconds
    self.deleteShouldFail = deleteShouldFail
    self.setIdentityResult = setIdentityResult
    self.compatibilityReadDelayNanoseconds = compatibilityReadDelayNanoseconds
  }

  func status() async throws -> ApplicationServiceStatusPayload {
    statusCallCount += 1
    activeStatusCalls += 1
    maximumConcurrentStatusCalls = max(maximumConcurrentStatusCalls, activeStatusCalls)
    defer { activeStatusCalls -= 1 }
    if statusReadDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: statusReadDelayNanoseconds)
    }
    if statusShouldFail { throw ApplicationServiceClientError.timeout }
    return statusPayload
  }

  func setStatusPayload(_ payload: ApplicationServiceStatusPayload) { statusPayload = payload }

  func setStatusShouldFail(_ shouldFail: Bool) { statusShouldFail = shouldFail }

  func setSnapshotPayload(_ payload: ApplicationServiceRemappingSnapshotPayload) {
    snapshotPayload = payload
  }

  func virtualDeviceDiagnostics() throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload {
    ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      hidGamepads: []
    )
  }

  func requestPermissions() throws -> PermissionManager.Snapshot {
    PermissionManager.Snapshot(inputMonitoring: .granted, accessibility: .granted)
  }

  func deviceInputState(for selector: RuntimeDeviceSelector) async throws -> DeviceInputState? {
    lastInputSelector = selector
    if let runtimeIdentifier = selector.runtimeIdentifier {
      if let delay = deviceReadDelaysNanoseconds[runtimeIdentifier] {
        try await Task.sleep(nanoseconds: delay)
      }
      if let mapped = inputStatesByRuntimeIdentifier[runtimeIdentifier] { return mapped }
    }
    if let inputSequence, !inputSequence.isEmpty {
      let index = min(inputReadCount, inputSequence.count - 1)
      inputReadCount += 1
      return inputSequence[index]
    }
    return inputState
  }

  func packetLog(for selector: RuntimeDeviceSelector) async throws -> [PacketLogEntry] {
    lastInputSelector = selector
    if let runtimeIdentifier = selector.runtimeIdentifier {
      if let delay = deviceReadDelaysNanoseconds[runtimeIdentifier] {
        try await Task.sleep(nanoseconds: delay)
      }
      if let mapped = packetEntriesByRuntimeIdentifier[runtimeIdentifier] { return mapped }
    }
    if let packetSequence, !packetSequence.isEmpty {
      let index = min(packetReadCount, packetSequence.count - 1)
      packetReadCount += 1
      return packetSequence[index]
    }
    return packetEntries
  }

  func setPacketEntries(_ entries: [PacketLogEntry]) { packetEntries = entries }

  func remappingSnapshot() throws -> ApplicationServiceRemappingSnapshotPayload {
    remappingSnapshotCallCount += 1
    return snapshotPayload
  }

  func remappingProfile(id: UUID) throws -> RemappingProfile {
    guard let profile = snapshotPayload.profiles.first(where: { $0.id == id }) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return profile
  }

  func createRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    snapshotPayload = snapshot(
      profiles: snapshotPayload.profiles + [profile],
      activeProfiles: snapshotPayload.activeProfiles,
      postEventAccess: snapshotPayload.postEventAccess
    )
    return snapshotPayload
  }

  func updateRemappingProfile(_ profile: RemappingProfile, expectedCurrent: RemappingProfile)
    async throws -> ApplicationServiceRemappingSnapshotPayload
  {
    updateCallCount += 1
    lastExpectedCurrent = expectedCurrent
    if updateDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: updateDelayNanoseconds) }
    if updateShouldConflict {
      throw ApplicationServiceRemappingRPCError(
        code: .profileUpdateConflict,
        message: "stale profile"
      )
    }
    var profiles = snapshotPayload.profiles
    if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
    snapshotPayload = snapshot(
      profiles: profiles,
      activeProfiles: snapshotPayload.activeProfiles,
      postEventAccess: snapshotPayload.postEventAccess
    )
    return snapshotPayload
  }

  func importRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    var profiles = snapshotPayload.profiles
    if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
      profiles[index] = profile
    } else {
      profiles.append(profile)
    }
    snapshotPayload = snapshot(
      profiles: profiles,
      activeProfiles: snapshotPayload.activeProfiles,
      postEventAccess: snapshotPayload.postEventAccess
    )
    return snapshotPayload
  }

  func deleteRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    if deleteShouldFail { throw ApplicationServiceClientError.timeout }
    deleteCallCount += 1
    lastDeletedProfileID = id
    snapshotPayload = snapshot(
      profiles: snapshotPayload.profiles.filter { $0.id != id },
      activeProfiles: snapshotPayload.activeProfiles.filter { $0.profileID != id },
      postEventAccess: snapshotPayload.postEventAccess
    )
    return snapshotPayload
  }

  func activateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    snapshotPayload
  }

  func deactivateRemappingProfile(vendorID: UInt16, productID: UInt16) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func deactivateRemappingProfile(profileID: UUID) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func remappingPostEventAccess() throws -> RemappingPostEventAccessState {
    snapshotPayload.postEventAccess
  }

  func requestRemappingPostEventAccess() throws -> RemappingPostEventAccessState {
    snapshotPayload.postEventAccess
  }

  func compatibilityIdentity() async throws -> CompatibilityIdentity {
    let identity = selectedIdentity
    if compatibilityReadDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: compatibilityReadDelayNanoseconds)
    }
    return identity
  }

  func setCompatibilityIdentity(_ identity: CompatibilityIdentity) throws -> Bool {
    setIdentityCallCount += 1
    if setIdentityResult { selectedIdentity = identity }
    return setIdentityResult
  }
}
