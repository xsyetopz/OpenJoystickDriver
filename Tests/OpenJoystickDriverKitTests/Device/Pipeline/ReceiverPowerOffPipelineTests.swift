import Foundation
import OpenJoystickDriverTestSupport
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// The power-off packet of a receiver slot on a real USB pipeline: a deliberate stop sends it
/// before the handle closes, and a lost session does not.
struct ReceiverPowerOffPipelineTests {
  private typealias Receiver = ProtocolPacketFixtures.XUSBReceiver

  let identifier = LogicalControllerID(vendorID: 0x045E, productID: 0x0719, locationID: 7)
  let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 1,
    vendorID: 0x045E,
    productID: 0x0719,
    locationID: 7
  )
  let powerOff: [UInt8] = XUSBDriverTests.powerOffBytes

  private func makePipeline(sessions: [RecoveryUSBSession]) throws -> DevicePipeline {
    let description = try ProtocolDescriptionFixture.decode(
      family: .xboxXUSB,
      #""rawUSB": true, "defaults": {"receiverPowerOff": "#
        + #"{"bytes": "00 00 08 C0 00 00 00 00 00 00 00 00", "variants": ["Receiver"]}}"#
    )
    return DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: XUSBDriver(isWirelessReceiver: true, description: description),
      dispatcher: RecoveryOutputDispatcher(),
      startupPlayerIndicator: .player1,
      usbTransportProvider: RecoveryUSBProvider(sessions: sessions),
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 1_000_000
      )
    )
  }

  @Test
  func stopSendsThePowerOffPacketOnceBeforeTheHandleCloses() async throws {
    let session = RecoveryUSBSession(
      readResults: [.success([UInt8](Receiver.presenceConnected))],
      readError: .timeout
    )
    let pipeline = try makePipeline(sessions: [session])
    let start = Task { await pipeline.start() }
    await waitUntil("the player LED is written") { await session.writeCount == 2 }

    await pipeline.stop()
    await start.value

    #expect(await session.writes.filter { $0 == powerOff }.count == 1)
    #expect(await session.writes.last == powerOff)
    #expect(await session.closeCount == 1)
  }

  @Test
  func stopWithoutAConnectedControllerSendsNoPowerOff() async throws {
    let session = RecoveryUSBSession(readError: .timeout)
    let pipeline = try makePipeline(sessions: [session])
    let start = Task { await pipeline.start() }
    await waitUntil("the inquiry is written") { await session.writeCount == 1 }

    await pipeline.stop()
    await start.value

    #expect(await !session.writes.contains(powerOff))
  }

  @Test
  func aLostSessionClosesWithoutThePowerOffPacket() async throws {
    let lost = RecoveryUSBSession(
      readResults: [.success([UInt8](Receiver.presenceConnected))],
      readError: .disconnected
    )
    let next = RecoveryUSBSession(readError: .timeout)
    let pipeline = try makePipeline(sessions: [lost, next])
    let start = Task { await pipeline.start() }
    await waitUntil("the lost session is closed") { await lost.closeCount == 1 }

    #expect(await !lost.writes.contains(powerOff))
    await pipeline.stop()
    await start.value
  }
}
