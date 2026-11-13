import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerServerPickerTests {
  private static func device(
    physicalOwnership: ControllerOwnershipObservation = .exclusiveHID,
    recordServer: ControllerServer = .system,
    accessRoute: ControllerAccessRoute = .system
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x3537,
      productID: 0x100B,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: accessRoute == .system ? .hid : .rawUSB,
      physicalOwnership: physicalOwnership,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: recordServer,
      recordAccessRoute: accessRoute,
      sessionToken: .fixture("device-server")
    )
  }

  @Test(
    arguments: [
      (
        ControllerOwnershipObservation.systemGamepad, ControllerServer.system,
        ControllerAccessRoute.system, true
      ),
      (.exclusiveHID, .ojd, .system, true),
      (.systemGamepad, .ojd, .system, true),
      (.exclusiveHID, .system, .system, false),
      (.systemHIDVisible, .system, .system, false),
      (.systemGamepad, .system, .rawAccess, false),
      (.exclusiveRawUSB, .ojd, .rawAccess, false),
    ]
  )
  func pickerShowsOnlyForNativeOrOJDOwnedHIDController(
    physicalOwnership: ControllerOwnershipObservation,
    recordServer: ControllerServer,
    accessRoute: ControllerAccessRoute,
    shown: Bool
  ) {
    let device = Self.device(
      physicalOwnership: physicalOwnership,
      recordServer: recordServer,
      accessRoute: accessRoute
    )

    #expect(ControllerServerPicker.isShown(for: device) == shown)
  }

  @Test(arguments: [ControllerServer.ojd, .system])
  func changeCallsGatewayWithModelIdentityAndValue(_ server: ControllerServer) async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(physicalOwnership: .systemGamepad)

    await viewModel.setControllerServer(server, for: device)

    let requests = await gateway.serverRequests
    #expect(requests.count == 1)
    #expect(requests.first?.model == ControllerModelID(vendorID: 0x3537, productID: 0x100B))
    #expect(requests.first?.server == server)
    #expect(viewModel.controllerServerFailures[RuntimeControllerModel(device)] == nil)
  }

  @Test
  func refusalShowsE2023WithServiceDetail() async {
    let gateway = GatewayStub()
    await gateway.setServerFailure(.invalidRecord, detail: "bad record")
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(physicalOwnership: .systemGamepad)

    await viewModel.setControllerServer(.ojd, for: device)

    let message = viewModel.controllerServerFailures[RuntimeControllerModel(device)]
    #expect(viewModel.controllerActionFailures[device.sessionToken.rawValue] == nil)
    #expect(message == OJDLocalized.string("ui.controllers.server.invalidRecord") + " bad record")
  }
}
