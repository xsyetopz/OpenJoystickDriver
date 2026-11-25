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
  func padSendsInputAndNoAnnounceDeliversItsFirstInput() async {
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
    await waitUntil("the first input is dispatched") { dispatcher.inputCount > 0 }

    let events = await pad.events
    #expect(dispatcher.inputCount > 0)
    #expect(events.first == "read", "the input read is pending before the first write: \(events)")
    await pipeline.stop()
    await startTask.value
  }

  @Test
  func startupSelectsAudioAlternateSettingZeroBeforeTheFirstWrite() async {
    let pad = SilentGIPPadSession()
    let (pipeline, dispatcher) = Self.pipeline(for: pad)

    let startTask = Task { await pipeline.start() }
    await waitUntil("the first input is dispatched") { dispatcher.inputCount > 0 }

    let events = await pad.events
    let setInterface = events.firstIndex(of: "control 01 0b 0000 0001")
    let firstWrite = events.firstIndex { $0.hasPrefix("write") }
    #expect(setInterface != nil, "SET_INTERFACE(1, 0) is sent: \(events)")
    #expect((setInterface ?? .max) < (firstWrite ?? .max), "it precedes the writes: \(events)")
    await pipeline.stop()
    await startTask.value
  }

  @Test
  func padThatDropsWritesUntilItsTogglesResetDeliversInputAfterRecovery() async {
    let pad = SilentGIPPadSession(dropsWritesUntilResync: true)
    let (pipeline, dispatcher) = Self.pipeline(for: pad)

    let startTask = Task { await pipeline.start() }
    await waitUntil("the first input is dispatched") {
      dispatcher.inputCount > 0
    }

    let events = await pad.events
    #expect(dispatcher.inputCount > 0)
    let outReset = events.firstIndex(of: "resync 2")
    let inReset = events.firstIndex { $0.hasPrefix("resync 8") }
    #expect(outReset != nil && inReset != nil, "both endpoints are reset: \(events)")
    let resync = inReset ?? .max
    let rearmed = events[min(resync, events.endIndex)...].firstIndex(of: "read") ?? .max
    let resent = events[min(resync, events.endIndex)...].firstIndex(of: "write 5") ?? .max
    #expect(rearmed < resent, "a read is pending before POWER ON is resent: \(events)")
    await pipeline.stop()
    await startTask.value
  }

  @Test
  func readsHaveADeadlineOnlyUntilThePadFirstReports() async {
    let pad = SilentGIPPadSession()
    let (pipeline, dispatcher) = Self.pipeline(for: pad)

    let startTask = Task { await pipeline.start() }
    await waitUntil("a read follows the first input") {
      let timeouts = await pad.readTimeouts
      return dispatcher.inputCount > 0 && timeouts.count >= 2
    }

    let timeouts = await pad.readTimeouts
    #expect(timeouts.first == 1_000, "the armed read waits for the silent window: \(timeouts)")
    #expect(timeouts.dropFirst().allSatisfy { $0 == 0 }, "no later deadline: \(timeouts)")
    await pipeline.stop()
    await startTask.value
  }

  @Test(arguments: [
    (window: UInt64?.none, since: UInt64?.some(0), now: UInt64(5), expected: UInt32(0)),
    (window: 1_000_000_000, since: nil, now: 5, expected: 0),
    (window: 1_000_000_000, since: 0, now: 0, expected: 1_000),
    (window: 1_000_000_000, since: 0, now: 400_500_000, expected: 600),
    (window: 1_000_000_000, since: 0, now: 2_000_000_000, expected: 1),
  ])
  func inputReadTimeoutCoversTheRestOfTheSilentWindow(
    window: UInt64?,
    since: UInt64?,
    now: UInt64,
    expected: UInt32
  ) {
    let timeout = DevicePipeline.usbInputReadTimeoutMilliseconds(
      window: window,
      silentSince: since,
      now: now
    )

    #expect(timeout == expected)
  }

  private static func pipeline(
    for pad: SilentGIPPadSession
  ) -> (DevicePipeline, InputRecordingDispatcher) {
    let dispatcher = InputRecordingDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 0x2DC8, productID: 0x2027),
      transport: .usb(device: device),
      driver: GIPDriver(),
      dispatcher: dispatcher,
      usbTransportProvider: SilentGIPPadProvider(session: pad),
      usbRecoveryPolicy: fastRecoveryPolicy
    )
    return (pipeline, dispatcher)
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
///
/// With `dropsWritesUntilResync`, its OUT data toggle disagrees with the host's until the
/// endpoint is resynchronized, so it drops every write before that.
private actor SilentGIPPadSession: USBTransportSession {
  /// The transfers in order: `read`, `write` and the command byte, `resync` and the endpoint, or
  /// `control` with bmRequestType, bRequest, wValue and wIndex, all in hex.
  private(set) var events: [String] = []
  /// The timeout of each read in order, in milliseconds; 0 waits with no deadline.
  private(set) var readTimeouts: [UInt32] = []
  private var pending: (id: Int, continuation: CheckedContinuation<[UInt8], any Error>)?
  private var nextID = 0
  private var outToggleInSync: Bool

  init(dropsWritesUntilResync: Bool = false) { outToggleInSync = !dropsWritesUntilResync }

  /// The status frame the pad sends first, then input with the south button down.
  private static let reply: [UInt8] =
    [0x03, 0x20, 0x01, 0x04, 0x80, 0x00, 0x00, 0x00] + [0x20, 0x00, 0x01, 0x20, 0x10, 0x00]
    + [UInt8](repeating: 0, count: 30)

  func controlTransfer(_ request: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    func hex(_ value: some BinaryInteger, digits: Int) -> String {
      let text = String(value, radix: 16)
      return String(repeating: "0", count: max(0, digits - text.count)) + text
    }
    events.append(
      "control \(hex(request.requestType, digits: 2)) \(hex(request.request, digits: 2))"
        + " \(hex(request.value, digits: 4)) \(hex(request.index, digits: 4))"
    )
    throw USBTransportError.notSupported
  }

  func resynchronizeEndpoint(_ endpoint: UInt8, timeout _: UInt32) {
    events.append("resync \(String(endpoint, radix: 16))")
    if endpoint & 0x80 == 0 { outToggleInSync = true }
    expire(nextID)
  }

  func write(endpoint _: UInt8, data: [UInt8], timeout _: UInt32) -> Int {
    events.append("write \(String(data[0], radix: 16))")
    if outToggleInSync, data[0] == 0x05, let waiting = pending {
      pending = nil
      waiting.continuation.resume(returning: Self.reply)
    }
    return data.count
  }

  func read(endpoint _: UInt8, length _: Int, timeout: UInt32) async throws -> [UInt8] {
    events.append("read")
    readTimeouts.append(timeout)
    nextID += 1
    let id = nextID
    return try await withCheckedThrowingContinuation { continuation in
      pending = (id, continuation)
      guard timeout > 0 else { return }
      Task {
        try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
        self.expire(id)
      }
    }
  }

  /// Ends the pending read, as closing a pipe does.
  func close() {
    guard let waiting = pending else { return }
    pending = nil
    waiting.continuation.resume(throwing: USBTransportError.disconnected)
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
