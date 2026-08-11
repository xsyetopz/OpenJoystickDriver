import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct RuntimePermissionGenerationTests {
  @Test func newerPermissionRequestWinsOverAnOlderRefresh() async {
    let gateway = PermissionRaceGatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "denied",
        accessibility: "denied",
        connectedDevices: [],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      statusDelayNanoseconds: 100_000_000
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let refresh = Task { @MainActor in await viewModel.refreshPermissions() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.requestPermissions()
    await refresh.value

    let state = await MainActor.run { viewModel.permissionState }
    guard case .available(let permissions) = state else {
      Issue.record("Expected the newer permission request to remain authoritative")
      return
    }
    #expect(permissions.isReady)
  }

  @Test func newerPermissionRequestWinsInTheFullRefreshStatusSummary() async {
    let gateway = PermissionRaceGatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "denied",
        accessibility: "denied",
        connectedDevices: [],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      statusDelayNanoseconds: 100_000_000
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let refresh = Task { @MainActor in await viewModel.refresh() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.requestPermissions()
    await refresh.value

    let state = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = state else {
      Issue.record("Expected the full refresh status to remain available")
      return
    }
    #expect(status.permissions.isReady)
  }

  @Test func newerPostEventRequestWinsOverAnOlderRefresh() async {
    let gateway = PermissionRaceGatewayStub(
      snapshotPayload: ApplicationServiceRemappingSnapshotPayload(
        profiles: [],
        activeProfiles: [],
        routes: [],
        postEventAccess: .notAuthorized
      ),
      postEventAccessDelayNanoseconds: 100_000_000,
      requestedPostEventAccess: .granted
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let refresh = Task { @MainActor in await viewModel.refreshPostEventAccess() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.requestPostEventAccess()
    await refresh.value

    let state = await MainActor.run { viewModel.postEventAccessState }
    guard case .available(let access) = state else {
      Issue.record("Expected the newer post-event request to remain authoritative")
      return
    }
    #expect(access == .granted)
  }

  @Test func newerPostEventRequestWinsInTheFullRefreshStatusSummary() async {
    let gateway = PermissionRaceGatewayStub(
      snapshotPayload: ApplicationServiceRemappingSnapshotPayload(
        profiles: [],
        activeProfiles: [],
        routes: [],
        postEventAccess: .notAuthorized
      ),
      snapshotDelayNanoseconds: 100_000_000,
      requestedPostEventAccess: .granted
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let refresh = Task { @MainActor in await viewModel.refresh() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.requestPostEventAccess()
    await refresh.value

    let state = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = state else {
      Issue.record("Expected the full refresh status to remain available")
      return
    }
    #expect(status.postEventAccess == .granted)
  }
}

private actor PermissionRaceGatewayStub: ApplicationServiceGateway {
  let statusPayload: ApplicationServiceStatusPayload
  let snapshotPayload: ApplicationServiceRemappingSnapshotPayload
  let statusDelayNanoseconds: UInt64
  let snapshotDelayNanoseconds: UInt64
  let postEventAccessDelayNanoseconds: UInt64
  let requestedPostEventAccess: RemappingPostEventAccessState

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
    statusDelayNanoseconds: UInt64 = 0,
    snapshotDelayNanoseconds: UInt64 = 0,
    postEventAccessDelayNanoseconds: UInt64 = 0,
    requestedPostEventAccess: RemappingPostEventAccessState = .granted
  ) {
    self.statusPayload = statusPayload
    self.snapshotPayload = snapshotPayload
    self.statusDelayNanoseconds = statusDelayNanoseconds
    self.snapshotDelayNanoseconds = snapshotDelayNanoseconds
    self.postEventAccessDelayNanoseconds = postEventAccessDelayNanoseconds
    self.requestedPostEventAccess = requestedPostEventAccess
  }

  func status() async throws -> ApplicationServiceStatusPayload {
    if statusDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: statusDelayNanoseconds) }
    return statusPayload
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

  func deviceInputState(for selector: RuntimeDeviceSelector) throws -> DeviceInputState? { nil }

  func remappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    if snapshotDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: snapshotDelayNanoseconds) }
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
  { snapshotPayload }

  func updateRemappingProfile(_ profile: RemappingProfile, expectedCurrent: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func importRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { snapshotPayload }

  func deleteRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    snapshotPayload
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

  func remappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    if postEventAccessDelayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: postEventAccessDelayNanoseconds)
    }
    return snapshotPayload.postEventAccess
  }

  func requestRemappingPostEventAccess() throws -> RemappingPostEventAccessState {
    requestedPostEventAccess
  }

  func compatibilityIdentity() throws -> CompatibilityIdentity { .sdl2_3 }

  func setCompatibilityIdentity(_ identity: CompatibilityIdentity) throws -> Bool { true }
}
