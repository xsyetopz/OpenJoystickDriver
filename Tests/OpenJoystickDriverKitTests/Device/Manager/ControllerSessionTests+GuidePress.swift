import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

extension ControllerSessionTests {
  /// A USB DualShock 3 that has sent no input since its session started waits for a press of its
  /// PS button; once it has sent input, a silence is missing reports again.
  @Test
  func aSixaxisWithNoInputYetWaitsForAGuidePress() async {
    let identifier = LogicalControllerID(vendorID: 0x054C, productID: 0x0268)
    let clock = ManualUptime()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: SixaxisDriver(),
      dispatcher: ControllerSessionOutputProbe(),
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    clock.advance(by: 1_100_000_000)
    await pipeline.evaluateIdleSleep()
    #expect(await pipeline.inputHealth().failureReason == .guideNotPressed)

    await pipeline.feedHIDData(ProtocolPacketFixtures.DS3.inputReport())
    #expect(await pipeline.inputHealth().state == .healthy)
    clock.advance(by: 1_100_000_000)
    await pipeline.evaluateIdleSleep()
    #expect(await pipeline.inputHealth().failureReason == .missingReports)
    await pipeline.stop()
  }

  /// A session that has read no input is awaiting input, with no failure reason, until its first
  /// input report.
  @Test
  func aSessionIsAwaitingInputUntilItsFirstInputReport() async {
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x054C, productID: 0x0268),
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: SixaxisDriver(),
      dispatcher: ControllerSessionOutputProbe(),
      uptimeNanoseconds: ManualUptime().now
    )
    await pipeline.start()
    let awaiting = await pipeline.inputHealth()
    #expect(awaiting.state == .awaitingInput)
    #expect(awaiting.failureReason == nil)

    await pipeline.feedHIDData(ProtocolPacketFixtures.DS3.inputReport())
    #expect(await pipeline.inputHealth().state == .healthy)
    await pipeline.stop()
  }

  /// A report with no input that arrives after the timeout ends a session that never had input,
  /// so there is no input to wait for neutral from and the recovery is not one.
  @Test
  func aSixaxisThatNeverSentInputIsStaleNotWaitingForNeutral() async {
    let identifier = LogicalControllerID(vendorID: 0x054C, productID: 0x0268)
    let clock = ManualUptime()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 6, interfaceNumber: nil)),
      driver: SixaxisDriver(),
      dispatcher: ControllerSessionOutputProbe(),
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    clock.advance(by: 1_100_000_000)
    await pipeline.feedHIDData(Data([0x01]))
    let waiting = await pipeline.inputHealth()
    #expect(waiting.state == .stale)
    #expect(waiting.failureReason == .guideNotPressed)

    await pipeline.feedHIDData(ProtocolPacketFixtures.DS3.inputReport(buttons: (0, 0, true)))
    await pipeline.feedHIDData(ProtocolPacketFixtures.DS3.inputReport())
    let started = await pipeline.inputHealth()
    #expect(started.state == .healthy)
    #expect(started.recoveryCount == 0)
    await pipeline.stop()
  }
}
