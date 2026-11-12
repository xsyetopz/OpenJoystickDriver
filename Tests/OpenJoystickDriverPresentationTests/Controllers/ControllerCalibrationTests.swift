import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct ControllerCalibrationTests {
  private static func device() -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x2C22,
      productID: 0x2000,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .exclusiveHID,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("dev-calibrate")
    )
  }

  private static let input = ControllerState(
    leftStick: StickPosition(x: BipolarValue(Int16.max / 10), y: .center),
    leftTrigger: UnipolarValue(UInt16.max / 2)
  )

  private static let output = ApplicationServiceVirtualOutputState(
    VirtualGamepadState(leftStickX: 0, leftTrigger: Int16.max / 2)
  )

  @Test
  func rowsCarryRawTunedAndDeadZone() throws {
    let rows = ControllerCalibrationRows.rows(
      input: Self.input,
      output: Self.output,
      deadZone: 0.2
    )
    #expect(rows.map(\.control) == ControllerCalibrationRow.Control.allCases)
    let stick = try #require(rows.first { $0.control == .leftStick })
    #expect(abs(stick.raw - 0.1) < 0.001)
    #expect(stick.tuned == 0)
    #expect(stick.deadZone == 0.2)
    let trigger = try #require(rows.first { $0.control == .leftTrigger })
    #expect(abs(trigger.raw - 0.5) < 0.001)
    #expect(abs(try #require(trigger.tuned) - 0.5) < 0.001)
    #expect(trigger.deadZone == nil)
  }

  @Test
  func tunedIsNilWithoutVirtualGamepad() {
    let rows = ControllerCalibrationRows.rows(input: Self.input, output: nil, deadZone: nil)
    #expect(rows.allSatisfy { $0.tuned == nil && $0.deadZone == nil })
  }

  @Test
  func virtualOutputStateRoundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode(Self.output)
    let decoded = try JSONDecoder().decode(ApplicationServiceVirtualOutputState.self, from: data)
    #expect(decoded == Self.output)
  }

  @Test
  func refreshReadsBothValuesFromTheGateway() async {
    let gateway = GatewayStub(inputState: Self.input)
    await gateway.setVirtualOutput(Self.output)
    let model = ControllerCalibrationModel()
    await model.refresh(device: Self.device(), deadZone: 0.2, gateway: gateway)
    #expect(model.rows.count == ControllerCalibrationRow.Control.allCases.count)
    #expect(model.rows.first?.tuned == 0)
  }

  @Test
  func refreshShowsNoRowsWithoutInput() async {
    let gateway = GatewayStub(inputState: nil)
    let model = ControllerCalibrationModel()
    await model.refresh(device: Self.device(), deadZone: nil, gateway: gateway)
    #expect(model.rows.isEmpty)
  }
}
