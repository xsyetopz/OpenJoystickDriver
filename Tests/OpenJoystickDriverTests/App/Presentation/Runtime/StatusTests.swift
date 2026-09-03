import Combine
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct StatusTests {
  @Test func unresolvedPermissionStatesNeedUserAction() {
    #expect(RuntimePresentation.permissionLabel(.unknown) == "Needs attention")
    #expect(RuntimePresentation.permissionLabel(.denied) == "Needs attention")
  }

  @Test func translatesStatus() async throws {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-7"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()
    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.readiness == .ready)
    #expect(status.deviceCountLabel == "1 controller connected")
    #expect(status.compatibilityLabel == "SDL2/3")
    #expect(RuntimePresentation.sourceLabel(.button(.south)) == "A / Cross")
    #expect(
      RuntimePresentation.destinationLabel(.keyboard(key: .a, modifiers: [.command, .shift]))
        == "Command + Shift + A"
    )
  }

  @Test func statusReadinessWaitsForPostEventAccess() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-8"
    )
    let profile = makeProfile(name: "Mapped")
    let activeProfile = ApplicationServiceRemappingActiveProfilePayload(
      vendorID: profile.device.vendorID,
      productID: profile.device.productID,
      profileID: profile.id,
      profileName: profile.name,
      applicationScope: profile.applicationScope
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      snapshotPayload: snapshot(
        profiles: [profile],
        activeProfiles: [activeProfile],
        postEventAccess: .notAuthorized
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == true)
    #expect(status.postEventAccessLabel == "Needs attention")
    #expect(status.readiness == .needsAttention)
  }

  @Test func liveStatusRefreshPublishesControllerDisconnectionWithoutLoadingTheUI() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-live"
    )
    let connected = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [device],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    )
    let disconnected = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    )
    let gateway = GatewayStub(statusPayload: connected)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    await viewModel.refresh()
    await gateway.setStatusPayload(disconnected)

    await viewModel.refreshLiveStatus()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected live status to remain available")
      return
    }
    #expect(status.devices.isEmpty)
  }

  @Test func liveStatusFailureRetainsLastKnownControllerState() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-retained"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      )
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    await viewModel.refresh()
    await gateway.setStatusShouldFail(true)

    await viewModel.refreshLiveStatus()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected the last available status to remain visible")
      return
    }
    #expect(status.devices.map(\.runtimeIdentifier) == [device.runtimeIdentifier])
  }

  @Test @MainActor func controllerInventoryRefreshIsScopedAndCoalescesConcurrentRequests() async {
    let gateway = GatewayStub(statusReadDelayNanoseconds: 100_000_000)
    let viewModel = RuntimeViewModel(gateway: gateway)

    async let first: Void = viewModel.refreshControllerInventory()
    try? await Task.sleep(nanoseconds: 10_000_000)
    async let second: Void = viewModel.refreshControllerInventory()
    _ = await (first, second)

    #expect(await gateway.statusCallCount == 1)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    #expect(await gateway.remappingSnapshotCallCount == 0)
  }

  @Test @MainActor func unchangedLiveStatusRefreshDoesNotRepublishObservableState() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    await viewModel.refresh()
    var invalidations = 0
    let observation = viewModel.objectWillChange.sink { invalidations += 1 }

    let statusChanged = await viewModel.refreshLiveStatus()

    #expect(!statusChanged)
    #expect(invalidations == 0)
    withExtendedLifetime(observation) {}
  }

  @Test @MainActor func livePollingDoesNotCancelTheFullProfilesAndIdentityRefresh() async {
    let gateway = GatewayStub(statusReadDelayNanoseconds: 100_000_000)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let fullRefresh = Task { await viewModel.refresh() }
    await Task.yield()

    await viewModel.refreshLiveStatus()
    await fullRefresh.value

    guard case .available = viewModel.remappingState else {
      Issue.record("Expected profiles to finish loading")
      return
    }
    guard case .available = viewModel.compatibilityState else {
      Issue.record("Expected controller identity to finish loading")
      return
    }
  }

  @Test @MainActor func liveStatusRefreshPublishesActiveProfileChanges() async {
    let profile = makeProfile(name: "Desktop")
    let gateway = GatewayStub(snapshotPayload: snapshot(profiles: [profile]))
    let viewModel = RuntimeViewModel(gateway: gateway)
    await viewModel.refresh()
    let activeProfile = ApplicationServiceRemappingActiveProfilePayload(
      vendorID: 0x1234,
      productID: 0x5678,
      profileID: profile.id,
      profileName: profile.name,
      applicationScope: .global
    )
    await gateway.setSnapshotPayload(snapshot(profiles: [profile], activeProfiles: [activeProfile]))

    let statusChanged = await viewModel.refreshLiveStatus()

    guard case .available(let current) = viewModel.remappingState else {
      Issue.record("Expected the remapping snapshot to remain available")
      return
    }
    #expect(statusChanged)
    #expect(current.activeProfiles.map(\.profileID) == [profile.id])
  }

  @Test func statusReadinessIgnoresPostEventAccessWithoutActiveMappings() async {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: "session-device-9"
    )
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      snapshotPayload: snapshot(profiles: [], postEventAccess: .notAuthorized)
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.refresh()

    let statusState = await MainActor.run { viewModel.statusState }
    guard case .available(let status) = statusState else {
      Issue.record("Expected an available status")
      return
    }
    #expect(status.postEventAccess == .notAuthorized)
    #expect(status.requiresPostEventAccess == false)
    #expect(status.readiness == .ready)
  }

  @Test func statusReadinessRemainsUnknownBeforeRemappingSnapshot() {
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    )
    let presentation = RuntimeStatusPresentation(payload: payload, postEventAccess: .granted)

    #expect(presentation.requiresPostEventAccess == nil)
    #expect(presentation.readiness == .needsAttention)
  }
}
