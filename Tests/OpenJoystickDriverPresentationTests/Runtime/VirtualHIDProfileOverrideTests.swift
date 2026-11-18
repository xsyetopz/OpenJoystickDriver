import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct VirtualHIDProfileOverrideTests {
  private static let model = RuntimeControllerModel(vendorID: 0x1234, productID: 0x5678)

  private static func device(
    sessionToken: String = "device-override",
    profile: ApplicationServiceVirtualHIDProfileStatus? = nil,
    protocolBinding: ProtocolBindingID = ProtocolBindingID(.hidDescriptor),
    ownership: ControllerOwnershipObservation = .unknown
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: protocolBinding,
      connection: "USB",
      discoverySource: .rawUSB,
      physicalOwnership: ownership,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture(sessionToken)
    )
    device.virtualHIDProfile = profile
    return device
  }

  private static func status(
    _ devices: [ApplicationServiceDeviceDescription]
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    )
  }

  @Test
  func settingProfileSendsControllerSelectorAndRefreshesInventoryOnce() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)

    let requests = await gateway.overrideRequests
    #expect(requests.count == 1)
    #expect(requests.first?.profile == .generic)
    #expect(
      requests.first?.selector
        == ControllerReference.session(.fixture("device-override"))
    )
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
    #expect(await gateway.statusCallCount == 1)
  }

  @Test
  func automaticResetsOverride() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(nil, for: Self.device())

    let requests = await gateway.overrideRequests
    #expect(requests.count == 1)
    #expect(requests.first?.profile == nil)
  }

  @Test
  func serviceFailureIsShownForThatModelAndKeepsItsDetail() async {
    let gateway = GatewayStub(overrideFailure: .activationFailed(detail: "backend timed out"))
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(.sdlCompatible, for: Self.device())

    let state = viewModel.virtualHIDProfileOverrideStates[Self.model]
    #expect(state?.inFlight == false)
    #expect(state?.failure?.contains("backend timed out") == true)
    let otherModel = RuntimeControllerModel(vendorID: 0x1234, productID: 0x0001)
    #expect(viewModel.virtualHIDProfileOverrideStates[otherModel] == nil)
  }

  @Test
  func storedButUnappliedFailuresReadDifferentlyFromUnstoredOnes() {
    let stored = [
      RuntimePresentation.virtualHIDProfileOverrideFailure(.outputDisabled),
      RuntimePresentation.virtualHIDProfileOverrideFailure(.overrideRejectedByController),
    ]
    let unstored = [
      RuntimePresentation.virtualHIDProfileOverrideFailure(.unknownProfile),
      RuntimePresentation.virtualHIDProfileOverrideFailure(.persistenceFailed),
    ]
    #expect(stored.allSatisfy { $0.contains("is stored") })
    #expect(unstored.allSatisfy { $0.contains("Nothing was stored") })
    #expect(Set(stored + unstored).count == 4)
    #expect(
      RuntimePresentation.virtualHIDProfileOverrideFailure(.overrideFileKept(path: "/a/stick.json"))
        .contains("/a/stick.json")
    )
  }

  @Test
  func laterSuccessClearsModelFailure() async {
    let gateway = GatewayStub(overrideFailure: .persistenceFailed)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.failure != nil)

    await gateway.setOverrideFailure(nil)
    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)

    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
  }

  @Test
  func gatewayErrorIsShownAsModelFailure() async {
    let gateway = GatewayStub()
    await gateway.setOverrideError(.timeout)
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(nil, for: Self.device())

    let state = viewModel.virtualHIDProfileOverrideStates[Self.model]
    #expect(state?.inFlight == false)
    #expect(
      state?.failure == RuntimePresentation.userFacingError(ApplicationServiceClientError.timeout)
    )
  }

  @Test
  func requestStaysInFlightWithItsChoiceAndIgnoresRepeatsUntilItFinishes() async {
    let gateway = GatewayStub()
    await gateway.gateOverrideRequests()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    let request = Task { await viewModel.setVirtualHIDProfileOverride(.generic, for: device) }
    await waitUntil("the override request reaches the gateway") {
      await !gateway.overrideRequests.isEmpty
    }

    let state = viewModel.virtualHIDProfileOverrideStates[Self.model]
    #expect(state?.inFlight == true)
    #expect(state?.request == .set(.generic))
    #expect(state?.request?.requested == .generic)
    await viewModel.setVirtualHIDProfileOverride(nil, for: device)
    #expect(await gateway.overrideRequests.count == 1)

    await gateway.releaseOverrideRequests()
    await request.value

    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
  }

  @Test
  func padsOfSameModelShareInFlightRequestAndItsFailure() async {
    let gateway = GatewayStub(overrideFailure: .controllerNotFound)
    await gateway.gateOverrideRequests()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let first = Self.device(sessionToken: "pad-1")
    let second = Self.device(sessionToken: "pad-2")

    let request = Task { await viewModel.setVirtualHIDProfileOverride(nil, for: first) }
    await waitUntil("the override request reaches the gateway") {
      await !gateway.overrideRequests.isEmpty
    }

    let secondState = viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(second)]
    #expect(secondState?.inFlight == true)
    #expect(secondState?.request == .reset)
    await viewModel.setVirtualHIDProfileOverride(.generic, for: second)
    #expect(await gateway.overrideRequests.count == 1)

    await gateway.releaseOverrideRequests()
    await request.value

    let failure = viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(second)]?.failure
    #expect(failure != nil)
    #expect(
      failure == viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(first)]?.failure
    )
  }

  @Test
  func overrideIssuedDuringFullRefreshEndsWithFreshStatus() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setStatusReadsAreGated(true)
    let viewModel = RuntimeViewModel(gateway: gateway)

    let refresh = Task { await viewModel.refresh() }
    await gateway.waitForStatusCall(count: 1)
    let request = Task {
      await viewModel.setVirtualHIDProfileOverride(.generic, for: Self.device())
    }
    await waitUntil("the override request reaches the gateway") {
      await !gateway.overrideRequests.isEmpty
    }

    // The full refresh read began before the override and returns the old status.
    await gateway.resumeNextStatusRead()
    await refresh.value
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.inFlight == true)

    await gateway.waitForStatusCall(count: 2)
    let overridden = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: .override,
      override: .generic,
      unavailable: false
    )
    await gateway.setStatusPayload(Self.status([Self.device(profile: overridden)]))
    await gateway.resumeNextStatusRead()
    await request.value

    #expect(await gateway.statusCallCount == 2)
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model] == nil)
    guard case .available(let status) = viewModel.statusState else {
      Issue.record("Expected the refreshed status to be available")
      return
    }
    #expect(status.devices.first?.virtualHIDProfile?.override == .generic)
  }

  @Test
  func failuresOfDisconnectedModelsAreDropped() async {
    let gateway = GatewayStub(
      statusPayload: Self.status([Self.device()]),
      overrideFailure: .serverStopped
    )
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setVirtualHIDProfileOverride(.generic, for: Self.device())
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.failure != nil)

    await gateway.setStatusPayload(Self.status([]))
    await viewModel.refreshControllerInventory()

    #expect(viewModel.virtualHIDProfileOverrideStates.isEmpty)
  }

  @Test
  func overrideStoreProblemsAppearInStatusSummary() {
    let status = RuntimeStatusPresentation(
      payload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [],
        virtualHIDProfileOverrideError: "unsupported-schema"
      )
    )

    let messages = status.virtualHIDProfileOverrideStoreMessages
    #expect(messages.count == 1)
    #expect(messages.first?.contains("unsupported-schema") == true)
  }

  @Test
  func publishedIdentityComesFromLiveVirtualHIDProfile() {
    var xbox = Self.device(
      profile: ApplicationServiceVirtualHIDProfileStatus(
        profile: .sdlCompatible,
        source: .override,
        override: .sdlCompatible,
        unavailable: false
      )
    )
    xbox.publication = ApplicationServicePublicationStatus.published(target: .sdlCompatible)
    #expect(xbox.publishedIdentityLabel.contains("045E:0B0C"))
    #expect(xbox.publishedIdentityPresentation.glyphFamily == .xbox)

    let unpublished = Self.device(ownership: .systemGamepad)
    #expect(unpublished.publishedVirtualProfile == nil)
    #expect(
      unpublished.publishedIdentityLabel
        == OJDLocalized.string("platform.macos.ui.controllers.systemGamepadNotPublished")
    )
  }

  @Test
  func automaticLiveProfileIsPublishedIdentityInEveryPlace() throws {
    var pad = Self.device(
      profile: ApplicationServiceVirtualHIDProfileStatus(
        profile: .sdlCompatible,
        source: .automatic,
        override: nil,
        unavailable: false
      )
    )
    pad.publication = ApplicationServicePublicationStatus.published(target: .sdlCompatible)

    let label = VirtualHIDProfileID.sdlCompatible.identity.publishedUSBIdentityLabel
    #expect(pad.publishedIdentityLabel == label)
    #expect(pad.publishedIdentityLabel != RuntimePresentation.noVirtualHIDProfileLabel)
    let name = try #require(pad.publishedVirtualProfile?.productName)
    #expect(
      ControllerDetailFacts.automaticProfileLabel(pad)
        == OJDLocalized.formatted("ui.virtualProfile.automaticSelected", name)
    )
    #expect(
      pad.publishedIdentityPresentation == VirtualHIDProfileID.sdlCompatible.identity.presentation
    )
  }

  @Test
  func unpublishedControllerShowsItsPhysicalFamilyIcon() {
    var sixaxis = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.sonySixaxis, variant: .usb),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .systemGamepad,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("session-native")
    )
    sixaxis.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .sdlCompatible,
      source: .automatic,
      override: nil,
      unavailable: false
    )
    sixaxis.publication = ApplicationServicePublicationStatus.notPublished(.systemGamepad)

    #expect(sixaxis.publishedIdentityPresentation == .playstation)
    #expect(sixaxis.publishedIdentityPresentation.glyphFamily != .xbox)
  }

  @Test
  func publishedStatusWithoutSelectionShowsPhysicalIdentity() {
    var pad = Self.device(
      protocolBinding: ProtocolBindingID(.sonySixaxis, variant: .usb),
      ownership: .systemGamepad
    )
    pad.publication = ApplicationServicePublicationStatus.published(target: .sdlCompatible)

    #expect(pad.publishedVirtualProfile == nil)
    #expect(!pad.presentedIdentity.publishesVirtualDevice)
    #expect(pad.presentedIdentity.presentation == .playstation)
    #expect(
      pad.presentedIdentity.label
        == OJDLocalized.string("platform.macos.ui.controllers.systemGamepadNotPublished")
    )
  }

  @Test
  func inputTestShowsListGlyphsOrGenericOnesWithoutController() {
    #expect(InputTestView.presentation(of: nil) == .generic)
    let pad = Self.device(protocolBinding: ProtocolBindingID(.sonySixaxis, variant: .usb))
    #expect(InputTestView.presentation(of: pad) == pad.publishedIdentityPresentation)
  }

  @Test
  func iconAndLabelComeFromOnePresentedIdentity() {
    let profile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .sdlCompatible,
      source: .override,
      override: .sdlCompatible,
      unavailable: false
    )
    let cases: [(ApplicationServicePublicationStatus?, published: Bool)] = [
      (nil, false),
      (ApplicationServicePublicationStatus.notPublished(.noInputYet), false),
      (ApplicationServicePublicationStatus.failed("send failed"), false),
      (ApplicationServicePublicationStatus.published(target: .sdlCompatible), true),
    ]
    for (publication, published) in cases {
      for ownership in ControllerOwnershipObservation.allCases {
        // The service never reports a published device for a controller the policy routes to no
        // virtual device.
        if published, ownership.isServedBySystem || ownership == .upstreamVirtualDevice {
          continue
        }
        var pad = Self.device(
          profile: profile,
          protocolBinding: ProtocolBindingID(.sonySixaxis, variant: .usb),
          ownership: ownership
        )
        pad.publication = publication
        let identity = pad.presentedIdentity

        #expect(identity.publishesVirtualDevice == published)
        #expect(pad.publishedIdentityPresentation == identity.presentation)
        #expect(pad.publishedIdentityLabel == identity.label)
        if published {
          #expect(identity.presentation.glyphFamily == .xbox)
          #expect(identity.label.contains("045E:0B0C"))
        } else {
          #expect(identity.presentation == .playstation)
          #expect(!identity.label.contains("045E:0B0C"))
          let expected =
            ownership.isServedBySystem
            ? OJDLocalized.string("platform.macos.ui.controllers.systemGamepadNotPublished")
            : RuntimePresentation.noVirtualHIDProfileLabel
          #expect(identity.label == expected)
        }
      }
    }
  }
}
