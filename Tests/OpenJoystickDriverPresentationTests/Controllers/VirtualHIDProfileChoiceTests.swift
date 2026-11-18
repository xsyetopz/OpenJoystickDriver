import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// What the Virtual HID profile pop-up shows: the kind in force, the stored kind when it differs,
/// a notice when a choice sends nothing, and only the kinds the service accepts.
@MainActor
struct VirtualHIDProfileChoiceTests {
  private static let model = RuntimeControllerModel(vendorID: 0x1234, productID: 0x5678)

  private static func device(
    profile: ApplicationServiceVirtualHIDProfileStatus? = nil
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      physicalOwnership: .unknown,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("choice")
    )
    device.virtualHIDProfile = profile
    return device
  }

  private static func status(
    inForce: VirtualHIDProfileID?,
    stored: VirtualHIDProfileID?,
    scope: VirtualHIDProfileOverrideScope? = nil
  ) -> ApplicationServiceVirtualHIDProfileStatus {
    ApplicationServiceVirtualHIDProfileStatus(
      profile: inForce,
      source: stored == nil ? .automatic : .override,
      override: stored,
      overrideScope: scope,
      unavailable: false
    )
  }

  @Test
  func kindInForceAndStoredKindNamedWhenTheyDiffer() {
    let device = Self.device(profile: Self.status(inForce: .generic, stored: .sdlCompatible))
    #expect(
      VirtualHIDProfileKinds.inForceText(for: device)
        == OJDLocalized.formatted(
          "ui.virtualProfile.inForce",
          VirtualHIDProfileID.generic.identity.productName,
          VirtualHIDProfileID.sdlCompatible.identity.productName
        )
    )
  }

  @Test
  func noKindInForceNamedAsNone() {
    let device = Self.device(profile: Self.status(inForce: nil, stored: .sdlCompatible))
    #expect(
      VirtualHIDProfileKinds.inForceText(for: device)
        == OJDLocalized.formatted(
          "ui.virtualProfile.inForce",
          OJDLocalized.string("ui.virtualProfile.none"),
          VirtualHIDProfileID.sdlCompatible.identity.productName
        )
    )
  }

  @Test
  func nothingSaidWhenStoredKindInForceOrNoneStored() {
    let same = Self.device(profile: Self.status(inForce: .generic, stored: .generic))
    let automatic = Self.device(profile: Self.status(inForce: .generic, stored: nil))
    #expect(VirtualHIDProfileKinds.inForceText(for: same) == nil)
    #expect(VirtualHIDProfileKinds.inForceText(for: automatic) == nil)
    #expect(VirtualHIDProfileKinds.inForceText(for: Self.device()) == nil)
  }

  @Test
  func listHoldsAcceptedKindsAndStoredKindServiceWouldNotAccept() {
    let accepted = VirtualHIDProfileKinds.accepted(for: Self.device())
    #expect(!accepted.isEmpty)
    #expect(VirtualHIDProfileKinds.offered(for: Self.device()) == accepted)

    let refused = VirtualHIDProfileID.allCases.filter { !accepted.contains($0) }
    for stored in refused {
      let device = Self.device(profile: Self.status(inForce: nil, stored: stored))
      #expect(VirtualHIDProfileKinds.offered(for: device) == accepted + [stored])
    }
    for stored in accepted {
      let device = Self.device(profile: Self.status(inForce: stored, stored: stored))
      #expect(VirtualHIDProfileKinds.offered(for: device) == accepted)
    }
  }

  @Test
  func choosingStoredKindShowsNothingChanged() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(profile: Self.status(inForce: .generic, stored: .generic))

    await viewModel.chooseVirtualHIDProfile(.generic, scope: .model, for: device)

    #expect(
      viewModel.virtualHIDProfileOverrideStates[Self.model]?.notice
        == OJDLocalized.string("ui.virtualProfile.unchanged")
    )
    #expect(await gateway.overrideRequests.isEmpty)
  }

  @Test
  func choosingAutomaticWhenNothingStoredShowsNothingChanged() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.chooseVirtualHIDProfile(nil, scope: .model, for: Self.device())

    #expect(
      viewModel.virtualHIDProfileOverrideStates[Self.model]?.notice
        == OJDLocalized.string("ui.virtualProfile.unchanged")
    )
    #expect(await gateway.overrideRequests.isEmpty)
  }

  @Test
  func automaticForUnitWhoseModelHoldsOverrideSaysSo() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(
      profile: Self.status(inForce: .generic, stored: .generic, scope: .model)
    )

    await viewModel.chooseVirtualHIDProfile(nil, scope: .unit, for: device)

    #expect(
      viewModel.virtualHIDProfileOverrideStates[Self.model]?.notice
        == OJDLocalized.string("ui.virtualProfile.otherScopeHolds.model")
    )
    #expect(await gateway.overrideRequests.isEmpty)
  }

  @Test
  func automaticForModelWhoseUnitHoldsOverrideSaysSo() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(
      profile: Self.status(inForce: .generic, stored: .generic, scope: .unit)
    )

    await viewModel.chooseVirtualHIDProfile(nil, scope: .model, for: device)

    #expect(
      viewModel.virtualHIDProfileOverrideStates[Self.model]?.notice
        == OJDLocalized.string("ui.virtualProfile.otherScopeHolds.unit")
    )
    #expect(await gateway.overrideRequests.isEmpty)
  }

  @Test
  func choiceChangesSomethingSentInChosenScopeAndClearsNotice() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(profile: Self.status(inForce: .generic, stored: .generic))

    await viewModel.chooseVirtualHIDProfile(.generic, scope: .model, for: device)
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.notice != nil)

    await viewModel.chooseVirtualHIDProfile(.sdlCompatible, scope: .unit, for: device)

    let requests = await gateway.overrideRequests
    #expect(requests.count == 1)
    #expect(requests.first?.profile == .sdlCompatible)
    #expect(viewModel.virtualHIDProfileOverrideStates[Self.model]?.notice == nil)
  }
}
