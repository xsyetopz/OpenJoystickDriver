import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The session of a GIP pad that announces nothing: it answers the power-on write with a status
/// frame and input, and then reports only when a control changes.
struct GIPSessionTests {
  private static let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 1,
    vendorID: 0x2DC8,
    productID: 0x2027,
    locationID: 1,
    productName: "Wired Xbox pad"
  )

  private static let fastRecoveryPolicy = USBPipelineRecoveryPolicy(
    openRetryDelays: [1_000_000],
    reconnectBaseDelayNanoseconds: 1_000_000,
    reconnectMaximumDelayNanoseconds: 4_000_000,
    accessContentionDelayNanoseconds: 1_000_000
  )

  @Test
  func aPadThatSendsInputAndNoAnnounceDeliversItsFirstInput() async {
    let pad = SilentGIPPadSession()
    let dispatcher = InputRecordingDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x2DC8, productID: 0x2027),
      transport: .usb(device: Self.device),
      driver: GIPDriver(),
      dispatcher: dispatcher,
      usbTransportProvider: SilentGIPPadProvider(session: pad),
      usbRecoveryPolicy: Self.fastRecoveryPolicy
    )

    let startTask = Task { await pipeline.start() }
    await waitUntil("the first input is dispatched", deadline: 5) { dispatcher.inputCount > 0 }

    let events = await pad.events
    #expect(dispatcher.inputCount > 0)
    #expect(events.first == "read", "the input read is pending before the first write: \(events)")
    await pipeline.stop()
    await startTask.value
  }
}

/// Hands out one pad session.
private actor SilentGIPPadProvider: USBTransportProvider {
  private let session: SilentGIPPadSession

  init(session: SilentGIPPadSession) { self.session = session }

  func devices() -> [USBTransportDevice] { [] }

  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) -> any USBTransportSession { session }
}

/// A pad that sends no announce packet. Its status frame and first input go to the interrupt IN
/// read that is pending when it takes the power-on write; with no read pending they are lost, and
/// it sends nothing more until a control changes.
private actor SilentGIPPadSession: USBTransportSession {
  /// The writes and reads in order: `read`, or `write` and the command byte in hex.
  private(set) var events: [String] = []
  private var pending: (id: Int, continuation: CheckedContinuation<[UInt8], any Error>)?
  private var nextID = 0

  /// The status frame the pad sends first, then input with the south button down.
  private static let reply: [UInt8] =
    [0x03, 0x20, 0x01, 0x04, 0x80, 0x00, 0x00, 0x00] + [0x20, 0x00, 0x01, 0x20, 0x10, 0x00]
    + [UInt8](repeating: 0, count: 30)

  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }

  func write(endpoint _: UInt8, data: [UInt8], timeout _: UInt32) -> Int {
    events.append("write \(String(data[0], radix: 16))")
    if data[0] == 0x05, let waiting = pending {
      pending = nil
      waiting.continuation.resume(returning: Self.reply)
    }
    return data.count
  }

  func read(endpoint _: UInt8, length _: Int, timeout: UInt32) async throws -> [UInt8] {
    events.append("read")
    nextID += 1
    let id = nextID
    return try await withCheckedThrowingContinuation { continuation in
      pending = (id, continuation)
      Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
        self.expire(id)
      }
    }
  }

  private func expire(_ id: Int) {
    guard let waiting = pending, waiting.id == id else { return }
    pending = nil
    waiting.continuation.resume(throwing: USBTransportError.timeout)
  }
}

private final class InputRecordingDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false
  private let lock = NSLock()
  private var inputs = 0

  var inputCount: Int { lock.withLock { inputs } }

  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {
    lock.withLock { inputs += 1 }
  }

  func activateOutput(for _: LogicalControllerID) {}
}
