import Foundation
import IOKit
import Testing

@testable import OpenJoystickDriverKit

extension ControllerSessionTests {
  @Test
  func ds4LivenessLossNeutralizesAndRequiresFreshNeutralReport() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: 2),
      driver: DualShock4Driver(),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x28))
    clock.advance(by: 1_050_000_000)
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x48))
    #expect(output.snapshot().states.last?.pressed.isEmpty == true)

    await pipeline.feedHIDData(ds4USBReport(buttons: 0x08, timestamp: 3))
    #expect(await pipeline.inputState().isEffectivelyNeutral)
    await pipeline.stop()
  }

  @Test
  func freshHeldReportsDoNotRecoverRetiredDS4Output() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: 3),
      driver: DualShock4Driver(),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x08, rightStickX: 255, timestamp: 1))
    clock.advance(by: 1_050_000_000)

    await pipeline.feedHIDData(ds4USBReport(buttons: 0x08, rightStickX: 255, timestamp: 2))
    #expect(await pipeline.inputHealth().state == .waitingForNeutral)
    #expect(output.snapshot().stopped == [identifier])
    // Retiring releases the pipeline's input state too, as the other neutralize paths do.
    #expect(await pipeline.inputState().isEffectivelyNeutral)

    await pipeline.feedHIDData(ds4USBReport(buttons: 0x08, rightStickX: 255, timestamp: 3))
    #expect(await pipeline.inputHealth().state == .waitingForNeutral)
    #expect(await pipeline.inputHealth().recoveryCount == 0)

    await pipeline.feedHIDData(ds4USBReport(buttons: 0x08, timestamp: 4))
    #expect(await pipeline.inputHealth().state == .healthy)
    #expect(await pipeline.inputHealth().recoveryCount == 1)
    await pipeline.stop()
  }

  @Test
  func repeatedNonAdvancingDS4ReportsBecomeStaleAndRetireOnce() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: 4),
      driver: DualShock4Driver(),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    await pipeline.feedHIDData(ds4USBReport(buttons: 0x28, timestamp: 10))
    for _ in 0..<4 {
      clock.advance(by: 300_000_000)
      await pipeline.feedHIDData(ds4USBReport(buttons: 0x28, timestamp: 10))
    }

    #expect(await pipeline.inputHealth().state == .waitingForNeutral)
    #expect(await pipeline.inputHealth().failureReason == .freshnessNotAdvancing)
    #expect(output.snapshot().stopped == [identifier])
    await pipeline.stop()
  }

  @Test
  func missingDS4ReportsRetireOutputAndFreshNeutralRecovers() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: 5),
      driver: DualShock4Driver(),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    clock.advance(by: 1_100_000_000)
    await pipeline.evaluateIdleSleep()

    #expect(await pipeline.inputHealth().state == .waitingForNeutral)
    #expect(await pipeline.inputHealth().failureReason == .missingReports)
    #expect(output.snapshot().stopped == [identifier])

    await pipeline.feedHIDData(ds4USBReport(buttons: 0x08, timestamp: 1))
    #expect(await pipeline.inputHealth().state == .healthy)
    #expect(await pipeline.inputHealth().recoveryCount == 1)
    await pipeline.stop()
  }

  @Test
  func minimalBluetoothDS4ReportsKeepInputLivePastTheLivenessTimeout() async throws {
    let identifier = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let clock = ManualUptime()
    let output = ControllerSessionOutputProbe()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: 6),
      driver: DualShock4Driver(prefersBluetooth: true),
      dispatcher: output,
      uptimeNanoseconds: clock.now
    )
    await pipeline.start()
    // A native pad that macOS never switches to report 0x11 sends only the 10-byte minimal report.
    let neutral = Data([0x01, 0x80, 0x80, 0x80, 0x80, 0x08, 0x00, 0x00, 0x00, 0x00])
    let crossHeld = Data([0x01, 0x80, 0x80, 0x80, 0x80, 0x28, 0x00, 0x00, 0x00, 0x00])
    for _ in 0..<5 {
      clock.advance(by: 300_000_000)
      await pipeline.feedHIDData(neutral)
    }
    clock.advance(by: 300_000_000)
    await pipeline.feedHIDData(crossHeld)

    #expect(await pipeline.inputHealth().state == .healthy)
    #expect(await pipeline.inputState().pressed == [.faceSouth])
    await pipeline.stop()
  }

  func ds4USBReport(buttons: UInt8, rightStickX: UInt8 = 128, timestamp: UInt16 = 0) -> Data {
    var report = [UInt8](repeating: 0, count: 64)
    report[0] = 1
    report[1] = 128
    report[2] = 128
    report[3] = rightStickX
    report[4] = 128
    report[5] = buttons
    report[10] = UInt8(truncatingIfNeeded: timestamp)
    report[11] = UInt8(truncatingIfNeeded: timestamp >> 8)
    return Data(report)
  }
}
