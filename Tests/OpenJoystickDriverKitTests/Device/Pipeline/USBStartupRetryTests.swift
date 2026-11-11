import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A session start whose handshake keeps failing is retried with a growing delay and given up
/// after a fixed count (#55), and the last error stays on the controller.
struct USBStartupRetryTests {
  private static let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 1,
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 1
  )

  @Test
  func stopsRetryingAfterTheFixedNumberOfFailedHandshakes() async {
    let provider = FailingHandshakeProvider()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x3537, productID: 0x1010),
      transport: .usb(device: Self.device),
      driver: FailingStartupDriver(),
      dispatcher: LoggingOutputDispatcher(),
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1_000_000],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 4_000_000,
        accessContentionDelayNanoseconds: 1_000_000,
        maximumHandshakeFailures: 3
      )
    )

    let startTask = Task { await pipeline.start() }
    await waitUntil("three handshakes") { await provider.openAttempts() >= 3 }
    try? await Task.sleep(nanoseconds: 100_000_000)

    #expect(await provider.openAttempts() == 3)
    #expect(await pipeline.usbSessionStartFailed)
    #expect(await pipeline.startupOutputStatus == "failed: \(USBTransportError.inputOutput)")
    await pipeline.stop()
    await startTask.value
  }
}

private final class FailingStartupDriver: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  func parse(report _: Data, receivedAt _: MonotonicTimestamp) -> ControllerEvent? { nil }
  func startupWrites() -> [PhysicalOutputWrite] {
    [
      .usb(
        PhysicalUSBOutputPacket(endpoint: 0x01, bytes: [0x05, 0x20], timeoutMilliseconds: 2_000)
      )
    ]
  }
}

private actor FailingHandshakeProvider: USBTransportProvider {
  private var attempts = 0

  func devices() -> [USBTransportDevice] { [] }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) -> any USBTransportSession {
    attempts += 1
    return FailingWriteSession()
  }

  func openAttempts() -> Int { attempts }
}

private actor FailingWriteSession: USBTransportSession {
  var inputOwnership: HIDInputOwnership { .exclusive }

  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint _: UInt8, data _: [UInt8], timeout _: UInt32) throws -> Int {
    throw USBTransportError.inputOutput
  }

  func read(endpoint _: UInt8, length _: Int, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.timeout
  }
}
