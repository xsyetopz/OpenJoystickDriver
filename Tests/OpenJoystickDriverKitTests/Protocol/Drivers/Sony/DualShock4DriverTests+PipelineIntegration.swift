import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension DualShock4DriverTests {
  @Test
  func testObservedDS4RightStickYShortfallRemainsVisible() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    let events = try parser.parseReport(makeDS4Report(rightStickY: 8))
    let expectedRightStick = InputChange.rightStick(x: 0, y: -120.0 / 128.0)

    #expect(events.contains(expectedRightStick))
  }
  @Test
  func testControllerStateExposesTheDS4Hat() async {
    let dispatcher = CapturingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1356, productID: 2508),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: DualShock4Driver(),
      dispatcher: dispatcher
    )
    await pipeline.start()
    await pipeline.feedHIDData(makeDS4Report())

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x00))
    #expect(await pipeline.inputState().hat == .north)

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x03))
    #expect(await pipeline.inputState().hat == .southEast)

    await pipeline.feedHIDData(makeDS4Report())
    #expect(await pipeline.inputState().hat == .neutral)
    #expect(await pipeline.inputState().pressed.isEmpty)
  }

  @Test
  func testPipelineSnapshotsPowerWithoutDispatchingItAsInput() async {
    let dispatcher = CapturingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1356, productID: 2508),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: DualShock4Driver(),
      dispatcher: dispatcher
    ) { 0 }
    await pipeline.start()

    await pipeline.feedHIDData(makeDS4Report(status: 0x1B))

    #expect(
      await pipeline.currentPower
        == ControllerConnectionState.Power(
          charging: .full,
          battery: BatteryLevel(percentage: 100...100),
          wiredPower: true
        )
    )
    // The report is dispatched for its motion sample; power is not an input control.
    #expect(dispatcher.events.map(\.state) == [.neutral])
    #expect(dispatcher.events.first?.motion.count == 1)
  }

  @Test
  func testRegistryMapsDS4V2IdentityToDualShock4Driver() throws {
    let model = ControllerModelID(vendorID: 1356, productID: 2508)
    let profile = try #require(ProtocolDriverRegistry().record(for: model))

    #expect(profile.physicalProtocolID == .sonyDualShock4 && profile.physicalProtocolVariant == nil)
    #expect(try catalogParser(model) is DualShock4Driver)
  }
}
