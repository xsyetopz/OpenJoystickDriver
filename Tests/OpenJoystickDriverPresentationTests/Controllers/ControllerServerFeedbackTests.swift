import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerServerFeedbackTests {
  private static func device(
    recordServer: ControllerServer = .system
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x2DC8,
      productID: 0x301B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .systemGamepad,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: recordServer,
      recordAccessRoute: .system,
      sessionToken: .fixture("device-feedback")
    )
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

  private static func shownServer(_ viewModel: RuntimeViewModel) -> ControllerServer? {
    guard case .available(let status) = viewModel.statusState else { return nil }
    return status.devices.first?.recordServer
  }

  @Test
  func anAcceptedToggleRefreshesUntilTheStatusCarriesTheNewOwnership() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    let toggle = Task { await viewModel.setControllerServer(.ojd, for: Self.device()) }
    await gateway.waitForStatusCall(count: 3)
    await gateway.setStatusPayload(Self.status([Self.device(recordServer: .ojd)]))
    await toggle.value

    #expect(Self.shownServer(viewModel) == .ojd)
    #expect(await gateway.statusCallCount <= 4)
  }

  @Test
  func thePickerShowsTheChosenServerUntilTheServiceConfirmsIt() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    let toggle = Task { await viewModel.setControllerServer(.ojd, for: Self.device()) }
    await gateway.waitForStatusCall(count: 2)
    #expect(viewModel.shownControllerServer(for: Self.device()) == .ojd)
    await gateway.setStatusPayload(Self.status([Self.device(recordServer: .ojd)]))
    await toggle.value

    #expect(viewModel.shownControllerServer(for: Self.device(recordServer: .ojd)) == .ojd)
    #expect(viewModel.pendingControllerServers.isEmpty)
  }

  @Test
  func thePickerReturnsToTheRecordWhenTheChangeIsNotConfirmed() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerServer(.ojd, for: Self.device())

    #expect(viewModel.shownControllerServer(for: Self.device()) == .system)
  }

  @Test
  func thePickerReturnsToTheRecordWhenTheServiceRefuses() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setServerFailure(.noRecord)
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerServer(.ojd, for: Self.device())

    #expect(viewModel.shownControllerServer(for: Self.device()) == .system)
  }

  @Test
  func anAcceptedToggleStopsRefreshingAfterTwoSeconds() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerServer(.ojd, for: Self.device())

    #expect(Self.shownServer(viewModel) == .system)
    #expect(await gateway.statusCallCount == 11)
  }

  @Test
  func aRefusedToggleRefreshesOnce() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setServerFailure(.noRecord)
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.setControllerServer(.ojd, for: Self.device())

    #expect(await gateway.statusCallCount == 1)
  }

  @Test(
    arguments: [
      (ControllerServerFailure.rawUSB, String?.none, OJDLocalized.string("error.E2023.message")),
      (.notNative, nil, OJDLocalized.string("error.E2023.message")),
      (.noRecord, nil, OJDLocalized.string("ui.controllers.server.noRecord")),
      (.invalidRequest, nil, OJDLocalized.string("ui.controllers.invalidRequest")),
      (
        .invalidRecord, "bad record",
        OJDLocalized.string("ui.controllers.server.invalidRecord") + " bad record"
      ),
      (
        .persistenceFailed, "disk full",
        OJDLocalized.string("ui.controllers.server.persistenceFailed") + " disk full"
      ),
    ]
  )
  func eachRefusalShowsItsOwnText(
    failure: ControllerServerFailure,
    detail: String?,
    expected: String
  ) async {
    let gateway = GatewayStub()
    await gateway.setServerFailure(failure, detail: detail)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setControllerServer(.ojd, for: device)

    let message = viewModel.controllerServerFailures[RuntimeControllerModel(device)]
    #expect(message == expected)
  }

  @Test
  func theControlIsRunningUntilTheServiceConfirmsAndAnotherChoiceIsIgnored() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()
    #expect(!viewModel.isControllerServerRequestRunning(for: device))

    let first = Task { await viewModel.setControllerServer(.ojd, for: device) }
    await gateway.waitForStatusCall(count: 2)
    #expect(viewModel.isControllerServerRequestRunning(for: device))
    await viewModel.setControllerServer(.system, for: device)
    await gateway.setStatusPayload(Self.status([Self.device(recordServer: .ojd)]))
    await first.value

    #expect(await gateway.serverRequests.map(\.server) == [.ojd])
    #expect(!viewModel.isControllerServerRequestRunning(for: device))
  }

  @Test
  func aRefusalStaysBelowThePickerUntilTheNextChoiceStarts() async {
    let gateway = GatewayStub(statusPayload: Self.status([Self.device()]))
    await gateway.setServerFailure(.noRecord)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()
    let model = RuntimeControllerModel(device)

    await viewModel.setControllerServer(.ojd, for: device)
    #expect(
      viewModel.controllerServerFailures[model]
        == OJDLocalized.string("ui.controllers.server.noRecord")
    )
    #expect(viewModel.controllerActionFailures[device.sessionToken.rawValue] == nil)

    await gateway.setServerFailure(nil)
    await viewModel.setControllerServer(.ojd, for: device)
    #expect(viewModel.controllerServerFailures[model] == nil)
  }

  @Test
  func aModelWithoutARecordOffersNoChoiceAndSaysWhy() {
    let viewModel = RuntimeViewModel(gateway: GatewayStub())
    #expect(
      viewModel.controllerServerUnavailableReason(hasRecord: false)
        == OJDLocalized.string("ui.controllers.server.noRecord")
    )
    #expect(viewModel.controllerServerUnavailableReason(hasRecord: true) == nil)
  }

  @Test(
    arguments: [
      ("ui.controllers.server.noRecord", OJDLocalized.string("ui.controllers.server.noRecord")),
      (
        "ui.controllers.server.invalidRecord",
        OJDLocalized.string("ui.controllers.server.invalidRecord")
      ),
      (
        "ui.controllers.server.persistenceFailed",
        OJDLocalized.string("ui.controllers.server.persistenceFailed")
      ),
    ]
  )
  func eachNewTextIsLocalized(key: String, text: String) {
    #expect(text != key)
  }
}
