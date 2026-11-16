import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerActionFailureTests {
  private static func device(sessionToken: String) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "Bluetooth",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture(sessionToken)
    )
  }

  @Test
  func rejectedSuspendStaysVisibleForThatControllerAfterRefresh() async {
    // The stub gateway rejects session changes with `notFound`.
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)

    await viewModel.suspendController(Self.device(sessionToken: "pad-a"))

    #expect(await gateway.statusCallCount == 1)
    #expect(
      viewModel.controllerActionFailures == [
        token("pad-a"): RuntimePresentation.userFacingError(
          ApplicationServiceGatewayError.controllerSessionChangeRejected
        )
      ]
    )
  }

  @Test
  func failedWirelessDisconnectShowsLocalizedMessageWithoutServiceIdentifiers() async {
    let viewModel = RuntimeViewModel(gateway: GatewayStub())

    await viewModel.disconnectWirelessController(Self.device(sessionToken: "pad-b"))

    let failure = viewModel.controllerActionFailures[token("pad-b")]
    #expect(
      failure == OJDLocalized.string("ui.controllers.disconnectWireless.failure.notFound")
    )
    #expect(failure?.contains(WirelessControllerDisconnectFailure.notFound.rawValue) == false)
  }

  @Test
  func nextActionClearsControllersPreviousFailure() async {
    let viewModel = RuntimeViewModel(gateway: GatewayStub())
    viewModel.controllerActionFailures = [token("pad-c"): "earlier", token("pad-d"): "other"]

    await viewModel.resumeController(Self.device(sessionToken: "pad-c"))

    #expect(viewModel.controllerActionFailures[token("pad-c")] != "earlier")
    #expect(viewModel.controllerActionFailures[token("pad-d")] == "other")
  }
}
