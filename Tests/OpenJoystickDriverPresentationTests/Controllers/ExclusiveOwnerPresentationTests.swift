import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ExclusiveOwnerPresentationTests {
  private let owner = USBExclusiveOwner(processID: 11070, name: "steam_osx")

  private func device(
    ownership: HIDInputOwnership,
    owner: USBExclusiveOwner?,
    source: DeviceDiscoverySource = .rawUSB
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "GameSir G7 SE",
      vendorID: 0x3537,
      productID: 0x1010,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: source,
      hidInputOwnership: ownership,
      inputOwner: owner,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("held-device")
    )
  }

  @Test
  func detailNamesHolder() {
    let facts = ControllerDetailFacts.general(
      for: device(ownership: .ownedByAnotherClient, owner: owner)
    )
    let held = facts.first { $0.kind == .exclusiveOwner }
    #expect(held?.label == OJDLocalized.string("ui.controllers.exclusiveOwner"))
    #expect(
      held?.value
        == .text(
          OJDLocalized.formatted("status.controllerOwner.named", "steam_osx", "11070")
        )
    )
    #expect(
      !ControllerDetailFacts.general(for: device(ownership: .exclusive, owner: nil))
        .contains { $0.kind == .exclusiveOwner }
    )
  }

  @Test
  func heldControllerShowsNoInputHealth() {
    let held = ControllerDetailFacts.general(
      for: device(ownership: .ownedByAnotherClient, owner: owner)
    )
    #expect(!held.contains { $0.kind == .inputHealth })
    #expect(
      ControllerDetailFacts.general(for: device(ownership: .exclusive, owner: nil))
        .contains { $0.kind == .inputHealth }
    )
  }

  @Test
  func detailSaysWhenPauseHoldsController() {
    var paused = device(ownership: .exclusive, owner: nil)
    paused.paused = true
    let fact = ControllerDetailFacts.general(for: paused).first { $0.kind == .paused }
    #expect(fact?.label == OJDLocalized.string("ui.controllers.paused.label"))
    #expect(fact?.value == .text(OJDLocalized.string("ui.controllers.paused.value")))
    #expect(
      !ControllerDetailFacts.general(for: device(ownership: .exclusive, owner: nil))
        .contains { $0.kind == .paused }
    )
  }

  @Test
  func detailSaysWhenMacOSAlsoListsController() {
    let listed = ApplicationServiceDeviceDescription.fixture(
      id: "listed",
      hidInputOwnership: .exclusive,
      duplicateExposureRisk: .systemGameController
    )
    let fact = ControllerDetailFacts.general(for: listed).first { $0.kind == .alsoListedBySystem }
    #expect(fact?.label == OJDLocalized.string("ui.controllers.alsoListedBySystem"))
    #expect(fact?.value == .text(OJDLocalized.string("status.controllerAlsoListedBySystem")))
    #expect(
      !ControllerDetailFacts.general(for: device(ownership: .exclusive, owner: nil))
        .contains { $0.kind == .alsoListedBySystem }
    )
  }
}
