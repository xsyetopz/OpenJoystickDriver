import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
struct StickDeadzoneSettingTests {
  private static let model = ControllerModelID(vendorID: 0x2C22, productID: 0x2000)

  private static func device() -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: model.vendorID,
      productID: model.productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .exclusiveHID,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("device-deadzone")
    )
  }

  /// The setting of the bundled record for the model after the user record sets `value`.
  private static func setting(userValue value: Double?) throws -> StickDeadzoneSetting {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("StickDeadzoneSettingTests-\(UUID().uuidString)")
      .appendingPathComponent("Controllers", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    if let value {
      let change = try ControllerRecordWriter.change(
        .set(.stickDeadzone, value),
        for: .model(model),
        records: ControllerRecordSet.load(userDirectory: directory),
        directory: directory
      )
      try ControllerRecordWriter.write(change)
    }
    let record = try #require(ControllerRecordSet.load(userDirectory: directory).records[model])
    return StickDeadzoneSetting(record: record)
  }

  @Test
  func aModelWithoutAValueShowsNotSetAndStepsUpToTheLowestValue() throws {
    let setting = try Self.setting(userValue: nil)
    #expect(setting.value == nil)
    #expect(setting.text == OJDLocalized.string("status.notSet"))
    #expect(setting.increased == 0.01)
    #expect(setting.decreased == nil)
    #expect(!setting.canReset)
  }

  @Test
  func aUserValueShowsStepsAndCanBeReset() throws {
    let setting = try Self.setting(userValue: 0.08)
    #expect(setting.value == 0.08)
    #expect(setting.text == "0.08")
    #expect(setting.increased == 0.09)
    #expect(setting.decreased == 0.07)
    #expect(setting.canReset)
  }

  @Test
  func stepsStayInsideTheRangeARecordAccepts() throws {
    #expect(try Self.setting(userValue: 0.01).decreased == nil)
    #expect(try Self.setting(userValue: 0.99).increased == nil)
    #expect(try Self.setting(userValue: 0.02).decreased == 0.01)
    #expect(try Self.setting(userValue: 0.98).increased == 0.99)
  }

  @Test
  func lowestUserValueDecrementClears() throws {
    #expect(try Self.setting(userValue: 0.01).decrementClears)
    #expect(try Self.setting(userValue: 0.005).decrementClears)
    #expect(try !Self.setting(userValue: 0.02).decrementClears)
    #expect(try !Self.setting(userValue: nil).decrementClears)
  }

  @Test
  func aStepNeverMovesTheValueTheWrongWay() throws {
    let below = try Self.setting(userValue: 0.005)
    #expect(below.decreased == nil)
    #expect(below.increased == 0.015)
    let above = try Self.setting(userValue: 0.995)
    #expect(above.increased == nil)
    #expect(above.decreased == 0.985)
  }

  @Test
  func aStepKeepsTheValuesOffTheTwoDecimalGrid() throws {
    let setting = try Self.setting(userValue: 0.025)
    #expect(setting.increased == 0.035)
    #expect(setting.decreased == 0.015)
  }

  @Test(arguments: [0.07, nil])
  func aChangeCallsTheGatewayWithTheModelTheKeyAndTheValue(_ value: Double?) async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    let accepted = await viewModel.setStickDeadzone(value, for: device)

    let requests = await gateway.tuningRequests
    #expect(accepted)
    #expect(requests.count == 1)
    #expect(requests.first?.model == Self.model)
    #expect(requests.first?.key == .stickDeadzone)
    #expect(requests.first?.value == value)
    #expect(viewModel.controllerActionFailures[device.sessionToken.rawValue] == nil)
  }

  @Test
  func aRefusalShowsTheMessageWithTheServiceDetail() async {
    let gateway = GatewayStub()
    await gateway.setTuningFailure(.invalidRecord, detail: "stickDeadzone is out of range")
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    let accepted = await viewModel.setStickDeadzone(1.5, for: device)

    #expect(!accepted)
    #expect(
      viewModel.controllerActionFailures[device.sessionToken.rawValue]
        == OJDLocalized.string("ui.controllers.server.invalidRecord")
        + " stickDeadzone is out of range"
    )
  }

  @Test
  func removingAValueTheRecordDoesNotSetShowsTheNotSetMessage() async {
    let gateway = GatewayStub()
    await gateway.setTuningFailure(.notSet)
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device()

    await viewModel.setStickDeadzone(nil, for: device)

    #expect(
      viewModel.controllerActionFailures[device.sessionToken.rawValue]
        == OJDLocalized.string("ui.controllers.stickDeadzone.notSet")
    )
  }
}
