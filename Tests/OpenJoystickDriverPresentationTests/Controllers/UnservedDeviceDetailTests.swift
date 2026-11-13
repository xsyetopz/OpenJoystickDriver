import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

/// The detail of a connected device that OJD does not serve: its state and the Draft Record
/// action for a HID pad.
struct UnservedDeviceDetailTests {
  private static let gamepad = PhysicalInterfaceSignature(
    interfaceClass: 3,
    interfaceSubclass: 0,
    interfaceProtocol: 0,
    hostTransport: .usb,
    accessBackend: .hid,
    hidLayout: HIDLayoutSummary(
      hasGamePadOrJoystickCollection: true,
      primaryUsage: HIDUsageSignature(usagePage: 1, usage: 5),
      reportDescriptor: Data(GamepadHIDDescriptor.descriptor)
    )
  )

  private static func unbound(
    _ reason: ProtocolBindingReason,
    backend: DeviceAccessBackend,
    interfaces: [PhysicalInterfaceSignature] = [],
    productID: UInt16 = 0x1010
  ) -> ApplicationServiceUnboundDevice {
    ApplicationServiceUnboundDevice(
      vendorID: 0x3537,
      productID: productID,
      connection: "USB",
      accessBackend: backend,
      reason: reason,
      rejectedCandidates: [],
      interfaces: interfaces.map(ProtocolBindingResult.InterfaceSummary.init)
    )
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

  @Test
  func detailOffersDraftRecordOnlyForHIDPad() {
    let pad = RuntimeUnservedDevice(
      Self.unbound(.descriptorContractMismatch, backend: .hid, interfaces: [Self.gamepad])
    )
    #expect(pad.offersDraft)
    #expect(pad.modelID == ControllerModelID(vendorID: 0x3537, productID: 0x1010))
    #expect(!RuntimeUnservedDevice(Self.unbound(.noProtocolMatch, backend: .rawUSB)).offersDraft)
    #expect(!RuntimeUnservedDevice(Self.unbound(.noProtocolMatch, backend: .hid)).offersDraft)
  }

  @Test
  func draftOneRecordDraftBuilds() throws {
    let model = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
    let pad = PhysicalDevice(vendorID: 0x1234, productID: 0x5678, interfaces: [Self.gamepad])
    let draft = try #require(ControllerRecordDrafting.unservedDraft(model: model) { _, _ in pad })
    #expect(draft.family == .hidDescriptor)
    #expect(ControllerRecordDrafting.unservedDraft(model: model) { _, _ in nil } == nil)
  }

  @Test
  @MainActor
  func draftRecordAsksWhereToSaveDraft() {
    let model = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
    let pad = PhysicalDevice(vendorID: 0x1234, productID: 0x5678, interfaces: [Self.gamepad])
    let actions = ControllerDetailActions()
    actions.draftUnserved(model: model) { _, _ in pad }
    #expect(actions.pendingSave?.fileName == "1234-5678.plist")
    #expect(actions.notice == nil)
  }

  @Test
  @MainActor
  func draftRecordFailureBecomesNotice() {
    let model = ControllerModelID(vendorID: 0x1234, productID: 0x5678)
    let actions = ControllerDetailActions()
    actions.draftUnserved(model: model) { _, _ in nil }
    #expect(actions.pendingSave == nil)
    #expect(actions.notice?.isError == true)
    #expect(
      actions.notice?.text
        == OJDLocalized.formatted("ui.controllers.draftRecordFromSDL.noPad", model.description)
    )
  }

  @Test
  @MainActor
  func selectingUnservedDeviceReplacesSelectedController() async {
    let device = testPad(sessionToken: "unserved-select")
    let unserved = Self.unbound(.noProtocolMatch, backend: .rawUSB)
    let gateway = GatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [device],
        unboundDevices: [unserved],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      )
    )
    let runtime = RuntimeViewModel(gateway: gateway)
    await runtime.refresh()
    let screen = ControllersViewModel(runtime: runtime)
    screen.synchronizeSelection()
    #expect(screen.selectedUnserved == nil)

    let entry = RuntimeUnservedDevice(unserved)
    screen.select(unserved: entry)
    #expect(screen.selectedUnserved == entry)
    #expect(screen.selectedDevice == nil)

    screen.select(device)
    #expect(screen.selectedUnserved == nil)
    #expect(screen.selectedDevice?.sessionToken == device.sessionToken)
  }
}
