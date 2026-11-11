import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The Logitech F710 receiver in XInput mode (#48): after the user unplugs and replugs it, the
/// re-added service must start a session the same way the first arrival did and deliver input.
struct USBReplugTests {
  private let identifier = LogicalControllerID(
    vendorID: 0x046D,
    productID: 0xC21F,
    locationID: 7,
    interfaceNumber: 0
  )

  private func service(_ serviceID: UInt64) -> USBTransportDevice {
    USBTransportDevice(
      route: .rawUSB,
      serviceID: serviceID,
      vendorID: 0x046D,
      productID: 0xC21F,
      locationID: 7
    )
  }

  /// A wired-format Xbox 360 report with the A button held.
  private static let reportWithA: [UInt8] =
    [0x00, 0x14, 0x00, 0x10] + [UInt8](repeating: 0, count: 16)

  @Test
  func replugStartsTheSameSessionAndDeliversInput() async throws {
    let first = RecoveryUSBSession(
      readResults: [.success(Self.reportWithA)],
      readError: .timeout
    )
    let second = RecoveryUSBSession(
      readResults: [.success(Self.reportWithA)],
      readError: .timeout
    )
    let provider = RecoveryUSBProvider(sessions: [first, second], devices: [service(1)])
    let dispatcher = RecoveryOutputDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: RecoveryHIDBackend()),
      usbTransportProvider: provider
    )

    await manager.start()
    await waitUntil("the first session delivers input") {
      dispatcher.dispatchedStates.contains { $0.pressed.contains(.south) }
    }
    #expect(await manager.connectedLogicalControllerIDs() == [identifier])
    let firstWrites = await first.writes
    let firstEndpoints = await first.writeEndpoints
    let deliveredBeforeReplug = dispatcher.dispatchedStates.count

    await provider.setDevices([])
    // The manager drops the pipeline before its stop closes the session.
    await waitUntil("the removed controller is dropped and its session closed") {
      let dropped = await manager.pipelines.isEmpty
      let closed = await first.closeCount > 0
      return dropped && closed
    }
    #expect(await first.closeCount == 1)

    await provider.setDevices([service(2)])
    await waitUntil("the second session delivers input") {
      dispatcher.dispatchedStates.count > deliveredBeforeReplug
        && dispatcher.dispatchedStates.suffix(
          dispatcher.dispatchedStates.count - deliveredBeforeReplug
        ).contains { $0.pressed.contains(.south) }
    }

    #expect(await manager.connectedLogicalControllerIDs() == [identifier])
    #expect(await second.writes == firstWrites)
    #expect(await second.writeEndpoints == firstEndpoints)
    #expect(await second.readCount > 0)
    #expect(await provider.openedDevices == [service(1), service(2)])
    let pipeline = try #require(await manager.pipelines[identifier])
    #expect(await pipeline.usbSessionStartFailed == false)
    await manager.stop()
  }
}
