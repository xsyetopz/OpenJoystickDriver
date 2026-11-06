import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct DiagnosticsServiceTests {
  @Test
  func aVirtualDeviceErrorShowsItsMessageOnce() {
    let status = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .error("Missing entitlement")
    )
    let check = DiagnosticsService.virtualDeviceCheck(
      DiagnoseServiceSnapshot(
        availability: .running,
        status: status,
        virtualDiagnostics: nil,
        frameTimings: nil,
        listenerFailure: .absent
      )
    )

    #expect(
      check == DiagnoseCheck("virtual-device", .fail, "virtual gamepad error: Missing entitlement")
    )
  }

  private func snapshot(devices: [ApplicationServiceDeviceDescription]?) -> DiagnoseServiceSnapshot
  {
    DiagnoseServiceSnapshot(
      availability: devices == nil ? .stopped : .running,
      status: devices.map {
        ApplicationServiceStatusPayload(
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: $0,
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .error("")
        )
      },
      virtualDiagnostics: nil,
      frameTimings: nil,
      listenerFailure: .absent
    )
  }

  @Test
  func aRejectedSDLLineWarnsUnderItsCode() {
    let pad = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      name: "Test Pad",
      bindingResult: .sdlRejectedFixture("no element for button b99")
    )
    let check = DiagnosticsService.inputMappingCheck(snapshot(devices: [pad]))
    #expect(check.id == "input-mapping" && check.status == .warn)
    #expect(check.detail.contains("Test Pad"))
    #expect(check.detail.contains("no element for button b99"))
    #expect(check.detail.contains("(E5008)"))
  }

  @Test
  func theInputMappingCheckPassesWithoutARejectionAndSkipsWithoutAStatus() {
    let pad = ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    #expect(DiagnosticsService.inputMappingCheck(snapshot(devices: [pad])).status == .pass)
    #expect(DiagnosticsService.inputMappingCheck(snapshot(devices: nil)).status == .skip)
  }
}
