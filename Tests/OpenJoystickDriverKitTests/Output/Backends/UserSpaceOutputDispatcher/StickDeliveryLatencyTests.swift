import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// Holds callers until `open()`; `waitForEntry()` returns once the first caller is held.
private actor HoldGate {
  private var opened = false
  private var entered = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func hold() async {
    entered = true
    for waiter in enteredWaiters { waiter.resume() }
    enteredWaiters.removeAll()
    if !opened { await withCheckedContinuation { waiters.append($0) } }
  }

  func waitForEntry() async {
    if !entered { await withCheckedContinuation { enteredWaiters.append($0) } }
  }

  func open() {
    opened = true
    for waiter in waiters { waiter.resume() }
    waiters.removeAll()
  }
}

/// Holds the first native send until the test opens it; every later send completes at once.
///
/// A held send stands for one slow `IOHIDUserDeviceHandleReportWithTimeStamp` call.
private final class FirstSendHeldBackend: VirtualDeviceBackend,
  @unchecked Sendable
{
  /// The test reads only the reports sent; it answers no host request.
  func activate(hostReports _: UserSpaceHostReportHandler) {}

  private let gate = HoldGate()
  private let lock = NSLock()
  private var reports: [[UInt8]] = []
  private var sends = 0
  private var closes = 0

  func send(_ report: [UInt8]) async {
    let isFirst = lock.withLock {
      defer { sends += 1 }
      return sends == 0
    }
    if isFirst { await gate.hold() }
    lock.withLock { reports.append(report) }
  }

  func close() { lock.withLock { closes += 1 } }

  func waitForHeldSend() async { await gate.waitForEntry() }
  func openHeldSend() async { await gate.open() }
  func snapshot() -> (reports: [[UInt8]], closes: Int) { lock.withLock { (reports, closes) } }
}

/// Records every dispatched event and holds the first one whose left stick is off center until
/// the test opens it, as a slow virtual publication would.
private final class FirstStickDispatchHeldRecorder: OutputDispatcher, @unchecked Sendable {
  private let gate = HoldGate()
  private let lock = NSLock()
  private var events: [ControllerEvent] = []
  private var held = false
  private var suppressed = false

  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  func dispatch(
    _ event: ControllerEvent,
    from _: LogicalControllerID
  ) async {
    let holds = lock.withLock {
      guard !held, event.state.leftStick != .center else { return false }
      held = true
      return true
    }
    if holds { await gate.hold() }
    lock.withLock { events.append(event) }
  }

  func activateOutput(for _: LogicalControllerID) {}

  func waitForHeldDispatch() async { await gate.waitForEntry() }
  func openHeldDispatch() async { await gate.open() }
  func dispatchedCount() -> Int { lock.withLock { events.count } }
  /// The dispatched events whose left stick is off center, in order.
  func stickEvents() -> [ControllerEvent] {
    lock.withLock { events.filter { $0.state.leftStick != .center } }
  }
}

/// Measures how stick reports reach the virtual device when a native send is slower than the
/// controller's report interval (REQ-23).
///
/// The service handles HID events in one loop that awaits each input report's publication
/// (`DeviceManager+HIDDetection.swift`). These tests drive that loop's batching, its
/// `DeviceManager.EventBatches` and `inputReportsFollowedByLaterReport(in:)`, over the real
/// pipeline, `UserSpaceOutputDispatcher`, and `UserSpaceReportSender`. The Service target's
/// `AutomaticUserSpaceOutputDispatcher` is not reachable from Kit tests.
@Suite(.timeLimit(.minutes(2)))
struct StickDeliveryLatencyTests {
  private static let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
  private static let connectionID = UUID()
  private static let format = ContinuitySnapshotReportFormat()

  /// The left stick X a `ContinuitySnapshotReportFormat` report carries.
  private static func leftStickX(_ report: [UInt8]) -> Int16 {
    Int16(bitPattern: UInt16(report[4]) | UInt16(report[5]) << 8)
  }

  /// An input report whose bytes `ScriptedBatches` parses; empty bytes carry no input.
  private static func report(_ bytes: [UInt8], connectionID: UUID = connectionID) -> HIDDeviceEvent
  {
    .inputReport(
      address: .ioKit(locationID: 1, interfaceNumber: nil),
      connectionID: connectionID,
      reportID: 0,
      data: Data(bytes)
    )
  }

  private static func pipeline(
    _ batches: [[InputChange]],
    dispatcher: UserSpaceOutputDispatcher
  ) -> DevicePipeline {
    DevicePipeline(
      identifier: identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches(batches),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
  }

  /// Feeds batch 0, waits until its native send is held, queues `burst`, then releases the send.
  ///
  /// `burst` defaults to every other batch. It queues while the send is held, and the consumer
  /// loop drains after the release. The result is read before `stop()`, whose neutral report and
  /// close are not part of the burst.
  private static func deliverBurst(
    _ batches: [[InputChange]],
    burst: [HIDDeviceEvent]? = nil,
    format: any VirtualGamepadReportFormat = format
  ) async -> (reports: [[UInt8]], closes: Int) {
    let backend = FirstSendHeldBackend()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in backend },
      format: format
    )
    let pipeline = pipeline(batches, dispatcher: dispatcher)
    await pipeline.start()
    let events = DeviceManager.EventBatches<HIDDeviceEvent>()
    let consumer = Task {
      while let batch = await events.next() {
        let followed = DeviceManager.inputReportsFollowedByLaterReport(in: batch)
        for (index, event) in batch.enumerated() {
          guard case .inputReport(_, _, _, let data) = event else { continue }
          _ = await pipeline.feedHIDData(data, laterReportQueued: followed.contains(index))
        }
      }
    }
    events.append(report([0]))
    await backend.waitForHeldSend()
    for event in burst ?? (1..<batches.count).map({ report([UInt8($0)]) }) {
      events.append(event)
    }
    events.finish()
    await backend.openHeldSend()
    await consumer.value
    let result = backend.snapshot()
    await pipeline.stop()
    await dispatcher.close()
    return result
  }

  /// Upstream backlog: ten stick positions arrive while one send is in flight.
  ///
  /// Once that send completes, the newest position must be next, within about one send time, and
  /// no older position may follow a newer one. Holds for the report format of each persona.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func newestStickPositionFollowsTheSlowSendWithoutStaleBacklog(
    persona: VirtualHIDProfileID
  ) async {
    let format = RecordingReportFormat(persona: persona)
    let positions: [Float] = (0..<10).map { 0.05 + Float($0) * 0.09 }
    let result = await Self.deliverBurst(
      positions.map { [.leftStick(x: $0, y: 0)] },
      format: format
    )
    let values = result.reports.compactMap { format.state(of: $0)?.leftStickX }
    let newest = values.max()
    let afterHeld = values.dropFirst()
    let staleBeforeNewest = afterHeld.prefix { $0 != newest }.count

    #expect(values.last == newest, "delivered stick X \(values)")
    #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 }, "reordered: \(values)")
    #expect(
      staleBeforeNewest == 0,
      "\(staleBeforeNewest) stale positions published after the slow send: \(values)"
    )
    #expect(result.closes == 0)
  }

  /// Every button edge inside a burst reaches the virtual device in order; a coalescing fix must
  /// keep this green, for the report format of each persona.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func everyButtonEdgeInsideABurstIsDelivered(persona: VirtualHIDProfileID) async {
    let format = RecordingReportFormat(persona: persona)
    let batches: [[InputChange]] = [
      [.leftStick(x: 0.1, y: 0)], [.press(.south)], [.leftStick(x: 0.2, y: 0)],
      [.release(.south)], [.leftStick(x: 0.3, y: 0)], [.press(.south)],
      [.release(.south)], [.leftStick(x: 0.4, y: 0)],
    ]
    let result = await Self.deliverBurst(batches, format: format)
    let south = result.reports.compactMap { format.state(of: $0).map { $0.buttons & 1 == 1 } }
    var edges: [Bool] = []
    for (previous, next) in zip([false] + south, south) where previous != next {
      edges.append(next)
    }

    #expect(edges == [true, false, true, false], "south per report: \(south)")
    #expect(result.reports.last.flatMap { format.state(of: $0)?.leftStickX } == Int16(0.4 * 32_767))
  }

  /// A burst far longer than the sender's queue (bounded and newest-wins, sized by
  /// `frameQueueCapacity`, default 64) behind a slow send neither closes the device nor
  /// delivers stale positions; the burst collapses to its newest position.
  @Test(arguments: VirtualHIDProfileID.allCases)
  func longBurstKeepsTheDeviceOpenAndEndsOnTheNewestPosition(
    persona: VirtualHIDProfileID
  ) async {
    let format = RecordingReportFormat(persona: persona)
    // Starts off neutral, so the first position is published and its send is held.
    let positions: [Float] = (1...100).map { Float($0) / 100 }
    let result = await Self.deliverBurst(
      positions.map { [.leftStick(x: $0, y: 0)] },
      format: format
    )

    #expect(result.closes == 0)
    #expect(result.reports.compactMap { format.state(of: $0)?.leftStickX } == [327, 32_767])
  }

  /// A frame that finds the queue full of host replies fails as superseded, so the dispatcher
  /// returns without closing the device, and the next frame still publishes.
  @Test
  func frameBehindAQueueOfHostRepliesLeavesTheDeviceOpen() async throws {
    let backend = FirstSendHeldBackend()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in backend },
      format: Self.format
    )
    func state(_ x: Int16) -> ControllerState {
      var state = ControllerState.neutral
      state.leftStick = StickPosition(x: BipolarValue(x), y: .center)
      return state
    }
    func deliver(_ x: Int16) async throws {
      try await dispatcher.deliver(
        input: state(x),
        from: Self.identifier,
        remappedState: nil
      )
    }
    let first = Task { try await deliver(16_000) }
    await backend.waitForHeldSend()
    let entry = try await dispatcher.entry(for: Self.identifier)
    let capacity = VirtualGamepadReportMapping.frameQueueCapacity(for: Self.identifier)
    let replies = (0..<capacity).map { _ in entry.sender.submit { [[0xAA]] } }

    try await deliver(29_000)

    await backend.openHeldSend()
    try await first.value
    for reply in replies { try await reply.value() }
    try await deliver(Int16.max)
    let result = backend.snapshot()
    await dispatcher.close()

    #expect(result.closes == 0)
    #expect(result.reports.last.map(Self.leftStickX) == 32_767)
  }

  /// A last queued report that carries no input still publishes the newest stick position the
  /// reports before it left undispatched.
  @Test
  func positionLeftForAnEmptyLastReportIsPublished() async {
    let batches: [[InputChange]] = [
      [.leftStick(x: 0.1, y: 0)], [.leftStick(x: 0.5, y: 0)], [.leftStick(x: 0.9, y: 0)],
    ]
    let burst = [Self.report([1]), Self.report([2]), Self.report([])]
    let result = await Self.deliverBurst(batches, burst: burst)

    #expect(result.reports.map(Self.leftStickX) == [3_276, 29_490])
  }

  /// Only a later report of the same connection supersedes an input report, and any other event
  /// between them keeps both.
  @Test
  func onlyALaterReportOfTheSameConnectionSupersedesAReport() {
    let other = UUID()
    let batch: [HIDDeviceEvent] = [
      Self.report([1]), Self.report([1], connectionID: other), Self.report([2]),
      .ownershipChanged(
        address: .ioKit(locationID: 1, interfaceNumber: nil),
        ownership: .exclusive
      ), Self.report([3]),
      Self.report([4], connectionID: other), Self.report([5]),
    ]

    #expect(DeviceManager.inputReportsFollowedByLaterReport(in: batch) == [0, 4])
  }

  /// Events appended while the consumer is busy arrive as one ordered batch; finishing returns
  /// what is pending first, then nil.
  @Test
  func eventBatchesHandOverEverythingPendingInOrder() async {
    let batches = DeviceManager.EventBatches<Int>()
    for value in 1...3 { batches.append(value) }
    let first = await batches.next()
    batches.append(4)
    batches.finish()
    batches.append(5)
    let second = await batches.next()
    let end = await batches.next()

    #expect(first == [1, 2, 3])
    #expect(second == [4])
    #expect(end == nil)
  }

  /// Design hypothesis 1: an unchanged state is not published again, at the pipeline and at the
  /// dispatcher, so a resting stick produces no reports.
  @Test
  func unchangedStickStateIsPublishedOnce() async {
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in backend },
      format: Self.format
    )
    let pipeline = Self.pipeline([[.leftStick(x: 0.5, y: 0)], []], dispatcher: dispatcher)
    await pipeline.start()
    _ = await pipeline.feedHIDData(Data([0]))
    for _ in 0..<5 { _ = await pipeline.feedHIDData(Data([1])) }
    let event = ControllerEvent([.leftStick(x: 0.5, y: 0)])
    for _ in 0..<5 { await dispatcher.dispatch(event, from: Self.identifier) }
    let published = backend.publishedReports().count
    await pipeline.stop()
    await dispatcher.close()

    #expect(published == 1)
  }

  /// The mean cost of one stick report through `DevicePipeline.feedHIDData` and the dispatcher.
  ///
  /// The backend is instant. The bound is loose on purpose; the measured mean is in the message.
  @Test
  func oneStickReportCostsFarLessThanAReportInterval() async {
    let count = 1_000
    let distinct = 200
    let positions: [Float] = (0..<distinct).map { Float($0) / Float(distinct) }
    let backend = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in backend },
      format: Self.format
    )
    let pipeline = Self.pipeline(
      positions.map { [.leftStick(x: $0, y: 0)] } + [[.leftStick(x: -1, y: 0)]],
      dispatcher: dispatcher
    )
    await pipeline.start()
    // Creates the virtual device before timing starts.
    _ = await pipeline.feedHIDData(Data([UInt8(distinct)]))
    let elapsed = await ContinuousClock().measure {
      for index in 0..<count { _ = await pipeline.feedHIDData(Data([UInt8(index % distinct)])) }
    }
    let published = backend.publishedReports().count
    await pipeline.stop()
    await dispatcher.close()
    let totalMicroseconds =
      Double(elapsed.components.seconds) * 1_000_000
      + Double(elapsed.components.attoseconds) / 1_000_000_000_000
    let perReport = totalMicroseconds / Double(count)

    #expect(published == count + 1)
    #expect(perReport < 20_000, "mean per-report cost \(perReport) us over \(count) reports")
  }

  /// A merged input's motion samples go out with the input that replaces it, so motion
  /// processing still sees every sample.
  @Test
  func mergedInputsKeepEveryMotionSample() async {
    let samples = (1...2).map { Self.motionSample(counter: UInt32($0)) }
    let batches: [[InputChange]] = [
      [.leftStick(x: 0.1, y: 0)], [.leftStick(x: 0.2, y: 0), .motion(samples[0])],
      [.leftStick(x: 0.3, y: 0), .motion(samples[1])],
    ]
    let recorder = FirstStickDispatchHeldRecorder()
    let pipeline = DevicePipeline(
      identifier: Self.identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches(batches),
      dispatcher: recorder,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await recorder.openHeldDispatch()
    await pipeline.start()
    // Fed one after another, as the detection loop does; report 1 is followed by report 2.
    _ = await pipeline.feedHIDData(Data([0]))
    _ = await pipeline.feedHIDData(Data([1]), laterReportQueued: true)
    _ = await pipeline.feedHIDData(Data([2]))
    let events = recorder.stickEvents()
    await pipeline.stop()

    #expect(events.count == 2)
    #expect(events.last?.motion == samples)
  }

  /// A controller a remapping route consumes gets every queued report, since its bindings derive
  /// button edges from analog thresholds that a merged report would skip.
  @Test
  func remappedControllerReceivesEveryQueuedStickReport() async {
    let recorder = NativeEventRecorder()
    let pipeline = DevicePipeline(
      identifier: Self.identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches([
        [.leftStick(x: 0.1, y: 0)], [.leftStick(x: 0.9, y: 0)], [.leftStick(x: 0.1, y: 0)],
      ]),
      dispatcher: recorder,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await pipeline.start()
    _ = await pipeline.feedHIDData(Data([0]))
    _ = await pipeline.feedHIDData(Data([1]), laterReportQueued: true)
    _ = await pipeline.feedHIDData(Data([2]))
    let xs = recorder.states.map(\.leftStick.x.rawValue)
    await pipeline.stop()

    #expect(xs.prefix(3) == [3_276, 29_490, 3_276], "left stick X per dispatch: \(xs)")
  }

  /// An input held for a later report is dropped when the session is suspended, so a report with
  /// no input after the resume does not replay the stick position from before it.
  @Test
  func suspendDropsTheHeldInput() async {
    let recorder = FirstStickDispatchHeldRecorder()
    let pipeline = DevicePipeline(
      identifier: Self.identifier,
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: OutputCharacterizationTests.ScriptedBatches([
        [.leftStick(x: 0.1, y: 0)], [.leftStick(x: 0.9, y: 0)],
      ]),
      dispatcher: recorder,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )
    await recorder.openHeldDispatch()
    await pipeline.start()
    _ = await pipeline.feedHIDData(Data([0]))
    _ = await pipeline.feedHIDData(Data([1]), laterReportQueued: true)
    #expect(await pipeline.suspendControllerSession())
    #expect(await pipeline.resumeControllerSession())
    _ = await pipeline.feedHIDData(Data())
    let xs = recorder.stickEvents().map(\.state.leftStick.x.rawValue)
    await pipeline.stop()

    #expect(xs == [3_276], "left stick X per dispatch: \(xs)")
  }

  /// The service's detection loop, fed by a HID backend, publishes only the newest of the stick
  /// reports queued behind a slow dispatch.
  @Test
  func detectionLoopPublishesOnlyTheNewestQueuedStickReport() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let recorder = FirstStickDispatchHeldRecorder()
    let manager = DeviceManager(
      dispatcher: recorder,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let connection = Self.gamepadConnection()
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await manager.ensureHIDDetectionState(for: .granted)
    await backend.waitForAttempt(1)
    await backend.yield(.connected(connection: connection, ownership: .exclusive), attempt: 1)
    await waitUntil("manager.pipelines is not empty") { await !manager.pipelines.isEmpty }
    try #require(await !manager.pipelines.isEmpty)

    await backend.yield(Self.gamepadReport(leftX: 0xA0, connection: connection), attempt: 1)
    await recorder.waitForHeldDispatch()
    for leftX: UInt8 in [0xB0, 0xC0, 0xD0, 0xE0, 0xF0] {
      await backend.yield(Self.gamepadReport(leftX: leftX, connection: connection), attempt: 1)
    }
    // The detection loop's reader takes the queued reports before the dispatch completes.
    await backend.waitUntilConsumed(attempt: 1)
    await recorder.openHeldDispatch()
    await waitUntil("two stick events dispatched") { recorder.stickEvents().count >= 2 }
    // The loop handles events in order, so a dispatched centered report shows that the loop
    // has handled every earlier report.
    let dispatchedBeforeCenter = recorder.dispatchedCount()
    await backend.yield(Self.gamepadReport(leftX: 0x80, connection: connection), attempt: 1)
    await waitUntil("centered report dispatched") {
      recorder.dispatchedCount() > dispatchedBeforeCenter
    }
    let xs = recorder.stickEvents().map(\.state.leftStick.x.rawValue)
    await manager.stop()

    #expect(xs.count == 2, "left stick X per dispatch: \(xs)")
    // 0xF0, the newest queued report: (0xF0 - 0x80) * 258.
    #expect(xs.last == 28_896, "left stick X per dispatch: \(xs)")
  }

  /// Finishing wakes a waiting consumer with nil, and so does cancelling it.
  @Test
  func eventBatchesEndAWaitingConsumer() async {
    let finished = DeviceManager.EventBatches<Int>()
    let waiting = Task { await finished.next() }
    await waitUntil("the consumer waits for events") { finished.hasWaitingConsumer }
    finished.finish()

    let cancelled = DeviceManager.EventBatches<Int>()
    let cancelledWait = Task { await cancelled.next() }
    await waitUntil("the second consumer waits for events") { cancelled.hasWaitingConsumer }
    cancelledWait.cancel()

    #expect(await waiting.value == nil)
    #expect(await cancelledWait.value == nil)
  }

  private static func motionSample(counter: UInt32) -> ControllerMotionSample {
    .engineSpace(
      timestamp: ControllerSampleTimestamp(
        rawCounter: counter,
        monotonic: MonotonicTimestamp(nanoseconds: UInt64(counter)),
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: UInt64(counter),
        basis: .hostEstimate
      ),
      gyroDegreesPerSecond: ControllerMotionVector(x: Double(counter), y: 0, z: 0),
      accelerationG: ControllerMotionVector(x: 0, y: 0, z: 1)
    )
  }

  static let gamepadLocationID: UInt32 = 0x0031_0000

  /// A generic HID gamepad, parsed through `GamepadHIDDescriptor`.
  static func gamepadConnection() -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x3537,
        productID: 0x100B,
        productName: "GameSir",
        transportProperty: "USB",
        physicalLocationIdentifier: gamepadLocationID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            hostTransport: .usb,
            accessBackend: .hid,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ]
      ),
      routingAddress: .ioKit(locationID: gamepadLocationID, interfaceNumber: nil)
    )
  }

  /// A report of that gamepad with the left stick X at `leftX` and every other control at rest.
  static func gamepadReport(
    leftX: UInt8,
    connection: HIDDeviceConnection
  ) -> HIDDeviceEvent {
    var report = [UInt8](repeating: 0, count: 64)
    report.replaceSubrange(0..<6, with: [0x12, leftX, 0x80, 0x80, 0x80, 0x00])
    return .inputReport(
      address: .ioKit(locationID: gamepadLocationID, interfaceNumber: nil),
      connectionID: connection.connectionID,
      reportID: 0x12,
      data: Data(report)
    )
  }
}
