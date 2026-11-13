import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct DiagnosticsServiceTests {
  @Test
  func virtualDeviceErrorShowsItsMessageOnce() {
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
  func rejectedSDLLineWarnsUnderItsCode() {
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
  func inputMappingCheckPassesWithoutRejectionAndSkipsWithoutStatus() {
    let pad = ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    #expect(DiagnosticsService.inputMappingCheck(snapshot(devices: [pad])).status == .pass)
    #expect(DiagnosticsService.inputMappingCheck(snapshot(devices: nil)).status == .skip)
  }

  @Test
  func diagnoseWarnsOnPlaceholderSwitchSerial() {
    let pad = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      vendorID: 0x057E,
      productID: 0x2009,
      serialNumber: "000000000001"
    )
    let check = DiagnosticsService.switchSerialCheck(
      snapshot(devices: [pad]),
      records: .bundled
    )
    #expect(check.id == "switch-placeholder-serial" && check.status == .warn)
    #expect(check.detail.contains("057E:2009"))
    #expect(check.detail.contains("000000000001"))
  }

  @Test
  func diagnosePassesOtherSwitchSerial() {
    let genuine = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      vendorID: 0x057E,
      productID: 0x2009,
      serialNumber: "98:B6:E9:00:00:01"
    )
    let none = ApplicationServiceDeviceDescription.fixture(
      id: "pad-2",
      vendorID: 0x057E,
      productID: 0x2009
    )
    let check = DiagnosticsService.switchSerialCheck(
      snapshot(devices: [genuine, none]),
      records: .bundled
    )
    #expect(check.status == .pass)
  }

  @Test
  func diagnoseSkipsWithoutSwitchIdentity() {
    let other = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      serialNumber: "000000000001"
    )
    let skipped = DiagnosticsService.switchSerialCheck(
      snapshot(devices: [other]),
      records: .bundled
    )
    #expect(skipped.status == .skip)
    #expect(
      DiagnosticsService.switchSerialCheck(snapshot(devices: nil), records: .bundled).status
        == .skip
    )
  }

  @Test
  func diagnoseSkipsWhenRecordHasNoPlaceholderSerial() throws {
    let record = try ControllerRecordSet.makeRecord(
      OrderedJSON(foundation: [
        "apiVersion": "openjoystickdriver/v1alpha3",
        "kind": "Controller",
        "vendorID": 0x057E,
        "productID": 0x2009,
        "modes": [["id": "default", "protocol": ["family": "NintendoSwitch1"]]],
      ]),
      layers: [:]
    )
    let records = ControllerRecordSet(records: [record.model: record], userFiles: [])
    let pad = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      vendorID: 0x057E,
      productID: 0x2009,
      serialNumber: "000000000001"
    )
    let check = DiagnosticsService.switchSerialCheck(snapshot(devices: [pad]), records: records)
    #expect(check.status == .skip)
  }
}
