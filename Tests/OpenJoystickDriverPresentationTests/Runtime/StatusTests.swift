import Combine
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.serialized)
struct StatusTests {
  @Test
  func translatesStatus() async {
    let device = testPad(sessionToken: "device-7")
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
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
    #expect(RuntimePresentation.keyboardSystemSymbolName(.a) == nil)
  }

  @Test
  func statusReadinessWaitsForPostEventAccess() async {
    let device = testPad(sessionToken: "device-8")
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
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
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
    #expect(status.readiness == .needsAttention)
  }

  @Test
  func liveStatusRefreshPublishesControllerDisconnectionWithoutLoadingTheUI() async {
    let device = testPad(sessionToken: "device-live")
    let connected = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [device],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
    let disconnected = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
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

  @Test
  func liveStatusFailureRetainsLastKnownControllerState() async {
    let device = testPad(sessionToken: "device-retained")
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
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
    #expect(status.devices.map(\.sessionToken.rawValue) == [device.sessionToken.rawValue])
    #expect(await MainActor.run { viewModel.liveStatusError } != nil)

    await gateway.setStatusShouldFail(false)
    await viewModel.refreshLiveStatus()

    #expect(await MainActor.run { viewModel.liveStatusError } == nil)
  }

  @Test
  @MainActor
  func controllersScreenRepublishesRuntimeStatusChanges() async {
    let gateway = GatewayStub()
    let runtime = RuntimeViewModel(gateway: gateway)
    let controllers = ControllersViewModel(runtime: runtime)
    var invalidations = 0
    let observation = controllers.objectWillChange.sink { invalidations += 1 }

    await runtime.refresh()

    #expect(invalidations > 0)
    withExtendedLifetime(observation) {}
  }

  @Test
  @MainActor
  func controllerInventoryRefreshQueuesASequentialTrailingRequest() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let viewModel = RuntimeViewModel(gateway: gateway)

    let first = Task { await viewModel.refreshControllerInventory() }
    await gateway.waitForStatusCall(count: 1)
    let second = Task { await viewModel.refreshControllerInventory() }
    await gateway.resumeNextStatusRead()
    await gateway.waitForStatusCall(count: 2)
    await gateway.resumeNextStatusRead()
    await first.value
    await second.value

    #expect(await gateway.statusCallCount == 2)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    #expect(await gateway.remappingSnapshotCallCount == 0)
  }

  @Test
  @MainActor
  func inventoryRefreshQueuedDuringLiveRefreshRunsAtTheTrailingEdge() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let viewModel = RuntimeViewModel(gateway: gateway)

    let liveRefresh = Task { await viewModel.refreshLiveStatus() }
    await gateway.waitForStatusCall(count: 1)
    let inventoryRefresh = Task { await viewModel.refreshControllerInventory() }

    #expect(await gateway.statusCallCount == 1)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    await gateway.resumeNextStatusRead()
    await gateway.waitForStatusCall(count: 2)
    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    let ds4 = ApplicationServiceDeviceDescription(
      name: "DualShock 4",
      vendorID: 0x054C,
      productID: 0x09CC,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "Bluetooth",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("ds4-bluetooth")
    )
    await gateway.setStatusPayload(
      ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [ds4],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )
    await gateway.resumeNextStatusRead()
    _ = await liveRefresh.value
    await inventoryRefresh.value
    #expect(await gateway.statusCallCount == 2)
    guard case .available(let status) = viewModel.statusState else {
      Issue.record("Expected the trailing inventory to publish available status")
      return
    }
    #expect(status.devices.map(\.sessionToken.rawValue) == [ds4.sessionToken.rawValue])
  }

  @Test
  @MainActor
  func controllersAndMenuBarUseTheSameScopedRefreshCoordinator() async {
    let gateway = GatewayStub()
    await gateway.setStatusReadsAreGated(true)
    let runtime = RuntimeViewModel(gateway: gateway)
    let controllers = ControllersViewModel(runtime: runtime)
    let menuBar = MenuBarViewModel(runtime: runtime)

    controllers.refresh()
    await gateway.waitForStatusCall(count: 1)
    let menuRefresh = Task { await menuBar.refreshLiveStatus() }

    #expect(await gateway.maximumConcurrentStatusCalls == 1)
    await gateway.resumeNextStatusRead()
    await gateway.waitForStatusCall(count: 2)
    await gateway.resumeNextStatusRead()
    _ = await menuRefresh.value
    #expect(await gateway.statusCallCount == 2)
  }

  @Test
  @MainActor
  func unchangedLiveStatusRefreshDoesNotRepublishObservableState() async {
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

  @Test
  @MainActor
  func livePollingDoesNotCancelTheFullProfilesRefresh() async {
    let gateway = GatewayStub(statusReadDelayNanoseconds: 100_000_000)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let fullRefresh = Task { await viewModel.refresh() }
    await gateway.waitForStatusCall(count: 1)

    await viewModel.refreshLiveStatus()
    await fullRefresh.value

    guard case .available = viewModel.remappingState else {
      Issue.record("Expected profiles to finish loading")
      return
    }
  }

  @Test
  @MainActor
  func liveStatusRefreshPublishesActiveProfileChanges() async {
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

  @Test
  func statusReadinessIgnoresPostEventAccessWithoutActiveMappings() async {
    let device = testPad(sessionToken: "device-9")
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
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

  @Test
  func statusReadinessRemainsUnknownBeforeRemappingSnapshot() {
    let payload = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
    let presentation = RuntimeStatusPresentation(payload: payload, postEventAccess: .granted)

    #expect(presentation.requiresPostEventAccess == nil)
    #expect(presentation.readiness == .needsAttention)
  }

  @Test
  func controllersPageListsAnUnservedDeviceWithTheSentenceOfItsReason() {
    func unbound(_ reason: ProtocolBindingReason) -> ApplicationServiceUnboundDevice {
      ApplicationServiceUnboundDevice(
        vendorID: 0x3537,
        productID: 0x1010,
        connection: "USB",
        accessBackend: .rawUSB,
        reason: reason,
        rejectedCandidates: [],
        interfaces: []
      )
    }
    func presentation(_ reason: ProtocolBindingReason) -> RuntimeStatusPresentation {
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: [],
          unboundDevices: [unbound(reason)],
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready")
        )
      )
    }

    let held = presentation(.deviceInUse).unservedDevices
    #expect(held.map(\.identity) == ["3537:1010"])
    #expect(held.map(\.explanation) == [OJDLocalized.string("ui.controllers.deviceInUse")])
    #expect(held.map(\.nextStep) == [OJDLocalized.string("ui.controllers.deviceInUse.nextStep")])
    #expect(held.first?.explanation.isEmpty == false)
    #expect(
      presentation(.configurationUnreadable).unservedDevices.map(\.explanation) == [
        OJDLocalized.string("ui.controllers.configurationUnreadable")
      ]
    )
    // Every reason is listed with its sentence and next step.
    for reason in ProtocolBindingReason.allCases {
      let listed = presentation(reason).unservedDevices
      #expect(listed.map(\.explanation) == [OJDLocalized.string(reason.explanationKey)])
      #expect(listed.map(\.nextStep) == [OJDLocalized.string(reason.nextStepKey)])
      #expect(listed.first?.explanation != reason.explanationKey)
    }
    // The listing survives the updates that rebuild the presentation.
    #expect(
      presentation(.deviceInUse).applyingPermissions(
        RuntimePermissionSummary(inputRead: .granted, inputInject: .granted)
      ).unservedDevices == held
    )
  }

  @Test
  func deviceCountLabelCountsUnservedDevices() {
    let unserved = ApplicationServiceUnboundDevice(
      vendorID: 0x2DC8,
      productID: 0x310A,
      connection: "USB",
      accessBackend: .rawUSB,
      reason: .deviceInUse,
      rejectedCandidates: [],
      interfaces: []
    )
    func presentation(served: [ApplicationServiceDeviceDescription]) -> RuntimeStatusPresentation {
      RuntimeStatusPresentation(
        payload: ApplicationServiceStatusPayload(
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: served,
          unboundDevices: [unserved],
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready")
        )
      )
    }

    #expect(presentation(served: []).deviceCountLabel == RuntimePresentation.deviceCountLabel(1))
    #expect(
      presentation(served: [testPad(sessionToken: "device-served")]).deviceCountLabel
        == RuntimePresentation.deviceCountLabel(2)
    )
  }

  @Test
  func controllersPageTitlesAnUnservedDeviceWithItsNameNotItsIDs() {
    func title(_ name: String?, _ reason: ProtocolBindingReason) -> String {
      RuntimeUnservedDevice(
        ApplicationServiceUnboundDevice(
          vendorID: 0x2DC8,
          productID: 0x310A,
          name: name,
          connection: "USB",
          accessBackend: .rawUSB,
          reason: reason,
          rejectedCandidates: [],
          interfaces: []
        )
      ).title
    }
    #expect(
      title("8BitDo Ultimate 2C Wireless Controller", .deviceInUse)
        == "8BitDo Ultimate 2C Wireless Controller"
    )
    // The product string of an idle dongle is "IDLE"; the receiver has its own title.
    #expect(
      title("IDLE", .noControllerLinked) == OJDLocalized.string("ui.controllers.wirelessReceiver")
    )
    #expect(
      title(nil, .noControllerLinked) == OJDLocalized.string("ui.controllers.wirelessReceiver")
    )
    #expect(title(nil, .deviceInUse) == "2dc8:310a")
  }

  private func testPad(sessionToken: String) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture(sessionToken)
    )
  }
}
