import Foundation
import Testing

@testable import OpenJoystickDriverKit

private actor ReportSendGate {
  private var opened = false
  private var entered = false
  private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    entered = true
    enteredWaiters.forEach { $0.resume() }
    enteredWaiters.removeAll()
    if !opened { await withCheckedContinuation { waiters.append($0) } }
  }

  func waitForEntry() async {
    if !entered { await withCheckedContinuation { enteredWaiters.append($0) } }
  }

  func open() {
    opened = true
    waiters.forEach { $0.resume() }
    waiters.removeAll()
  }
}

private final class OrderedReportBackend: UserSpaceOutputDispatcher.VirtualDeviceBackend,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var reports: [[UInt8]] = []
  private var activeSends = 0
  private var maxActiveSends = 0
  private var closes = 0
  let gate: ReportSendGate?

  init(gate: ReportSendGate? = nil) { self.gate = gate }

  func send(_ report: [UInt8]) async {
    lock.withLock {
      activeSends += 1
      maxActiveSends = max(maxActiveSends, activeSends)
    }
    await gate?.wait()
    lock.withLock {
      reports.append(report)
      activeSends -= 1
    }
  }

  func close() { lock.withLock { closes += 1 } }
  func snapshot() -> (reports: [[UInt8]], maxActive: Int, closes: Int) {
    lock.withLock { (reports, maxActiveSends, closes) }
  }
}

private actor CancellableSendState {
  private var entered = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func markEntered() {
    entered = true
    waiters.forEach { $0.resume() }
    waiters.removeAll()
  }

  func waitForEntry() async { if !entered { await withCheckedContinuation { waiters.append($0) } } }
}

private final class CancellableReportBackend: UserSpaceOutputDispatcher.VirtualDeviceBackend,
  @unchecked Sendable
{
  let state = CancellableSendState()

  func send(_ report: [UInt8]) async throws {
    await state.markEntered()
    try await Task.sleep(nanoseconds: .max)
  }

  func close() {}
}

private actor NonCooperativeSendGate {
  private var entered = false
  private var released = false
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    entered = true
    entryWaiters.forEach { $0.resume() }
    entryWaiters.removeAll()
    if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
  }

  func waitForEntry() async {
    if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
  }

  func release() {
    released = true
    releaseWaiters.forEach { $0.resume() }
    releaseWaiters.removeAll()
  }
}

private final class NonCooperativeReportBackend: UserSpaceOutputDispatcher.VirtualDeviceBackend,
  @unchecked Sendable
{
  private let lock = NSLock()
  let gate = NonCooperativeSendGate()
  private var closes = 0

  func send(_ report: [UInt8]) async { await gate.wait() }
  func close() { lock.withLock { closes += 1 } }
  func closeCount() -> Int { lock.withLock { closes } }
}

/// A backend whose native teardown finishes only when its gate opens.
private final class SlowTeardownBackend: UserSpaceOutputDispatcher.VirtualDeviceBackend,
  @unchecked Sendable
{
  let gate = ReportSendGate()
  private let lock = NSLock()
  private var closes = 0

  func send(_ report: [UInt8]) async { await Task.yield() }
  func close() { lock.withLock { closes += 1 } }
  func waitUntilClosed() async { await gate.wait() }
  func closeCount() -> Int { lock.withLock { closes } }
}

private final class ActivityFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true
  func set(_ value: Bool) { lock.withLock { active = value } }
  func get() -> Bool { lock.withLock { active } }
}

/// Records the output commands a host report handler delivers.
private final class OutputRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var commands: [ControllerOutputCommand] = []
  private var sent: [Int] = []
  func append(_ command: ControllerOutputCommand, sent count: Int = 0) {
    lock.withLock {
      commands.append(command)
      sent.append(count)
    }
  }
  func snapshot() -> [ControllerOutputCommand] { lock.withLock { commands } }
  func sentCounts() -> [Int] { lock.withLock { sent } }
}

struct ReportSenderTests {
  @Test(.timeLimit(.minutes(1)))
  func hostSetReportReturnsAfterOrderedEnqueue() async throws {
    let gate = ReportSendGate()
    let backend = OrderedReportBackend(gate: gate)
    let input = UserSpaceInputReportState(format: try XboxGeckoHIDReportFormat())
    let entry = UserSpaceOutputDispatcher.Entry(backend: backend, inputReportState: input)
    let outputs = OutputRecorder()
    let isOpen: @Sendable () -> Bool = { true }
    let handler = UserSpaceHostReportHandler(
      identifier: DeviceIdentifier(vendorID: 1, productID: 2),
      input: input,
      sender: entry.sender,
      isOpen: isOpen,
      onOutput: { _, command in outputs.append(command) },
      onRumbleStatus: { _ in }
    )
    let blocking = entry.sender.submit { [[1]] }
    await gate.waitForEntry()

    _ = try handler.setReport(type: .output, reportID: 3, bytes: Self.xboxRumble(10, 20))
    _ = try handler.setReport(type: .output, reportID: 3, bytes: Self.xboxRumble(30, 40))
    #expect(outputs.snapshot().isEmpty)
    await gate.open()
    try await blocking.value()
    try await entry.sender.submit { [] }.value()

    #expect(
      outputs.snapshot() == [
        .consumerRumble(left: 10, right: 20), .consumerRumble(left: 30, right: 40),
      ]
    )
    await entry.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func suppressionBetweenReportsSkipsTheRemainingReportAndCanResume() async throws {
    let gate = ReportSendGate()
    let backend = OrderedReportBackend(gate: gate)
    let sender = UserSpaceReportSender()
    let activity = ActivityFlag()
    sender.attach(backend)
    let isActive: @Sendable () -> Bool = { activity.get() }
    let reports = sender.submit(whileActive: isActive) { [[1], [2]] }
    await gate.waitForEntry()
    activity.set(false)
    let barrier = sender.submit { [] }
    await gate.open()
    try await reports.value()
    try await barrier.value()
    #expect(backend.snapshot().reports == [[1]])
    activity.set(true)
    try await sender.submit(whileActive: isActive) { [[3]] }.value()
    #expect(backend.snapshot().reports == [[1], [3]])
    await sender.beginClose().value
  }

  @Test(.timeLimit(.minutes(1)))
  func eventsRepublishedStateAndHostOutputShareOneOrder() async throws {
    let gate = ReportSendGate()
    let backend = OrderedReportBackend(gate: gate)
    let format = try XboxGeckoHIDReportFormat()
    let input = UserSpaceInputReportState(format: format)
    let entry = UserSpaceOutputDispatcher.Entry(backend: backend, inputReportState: input)
    let first = entry.sender.submit { [input] in [input.update { $0.buttons = 1 }] }
    await gate.waitForEntry()
    let second = entry.sender.submit { [input] in [input.update { $0.buttons = 2 }] }
    let republished = entry.sender.submit { [input] in [input.currentReport()] }
    let sentBeforeOutput = OutputRecorder()
    let isOpen: @Sendable () -> Bool = { true }
    let handler = UserSpaceHostReportHandler(
      identifier: DeviceIdentifier(vendorID: 1, productID: 2),
      input: input,
      sender: entry.sender,
      isOpen: isOpen,
      onOutput: { _, command in
        sentBeforeOutput.append(command, sent: backend.snapshot().reports.count)
      },
      onRumbleStatus: { _ in }
    )
    let output = try handler.setReport(type: .output, reportID: 3, bytes: Self.xboxRumble(10, 20))
    await gate.open()
    try await first.value()
    try await second.value()
    try await republished.value()
    try await output.value()
    let snapshot = backend.snapshot()
    #expect(snapshot.maxActive == 1)
    try #require(snapshot.reports.count == 3)
    #expect(snapshot.reports[0] == format.buildInputReport(from: VirtualGamepadState(buttons: 1)))
    #expect(snapshot.reports[1] == format.buildInputReport(from: VirtualGamepadState(buttons: 2)))
    #expect(snapshot.reports[2] == snapshot.reports[1])
    #expect(sentBeforeOutput.sentCounts() == [3])
    await entry.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func closeRejectsQueuedWorkAndClosesBackendBeforeDrainingCurrentSend() async throws {
    let gate = ReportSendGate()
    let backend = OrderedReportBackend(gate: gate)
    let sender = UserSpaceReportSender()
    sender.attach(backend)
    let first = sender.submit { [[1]] }
    await gate.waitForEntry()
    let queued = sender.submit { [[2]] }
    let close = sender.beginClose()
    let repeatedClose = sender.beginClose()
    #expect(backend.snapshot().closes == 1)
    await #expect(throws: CancellationError.self) { try await sender.submit { [[3]] }.value() }
    await gate.open()
    try await first.value()
    await #expect(throws: CancellationError.self) { try await queued.value() }
    await close.value
    await repeatedClose.value
    #expect(backend.snapshot().reports == [[1]])
    #expect(backend.snapshot().closes == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func closeCancelsAStalledCurrentSend() async {
    let backend = CancellableReportBackend()
    let sender = UserSpaceReportSender()
    sender.attach(backend)
    _ = sender.submit { [[1]] }
    await backend.state.waitForEntry()

    await sender.beginClose().value
  }

  @Test(.timeLimit(.minutes(1)))
  func closeCompletesWhenNativeSendIgnoresCancellation() async {
    let backend = NonCooperativeReportBackend()
    let sender = UserSpaceReportSender()
    sender.attach(backend)
    _ = sender.submit { [[1]] }
    await backend.gate.waitForEntry()

    await sender.beginClose().value
    #expect(backend.closeCount() == 1)
    await backend.gate.release()
  }

  @Test(.timeLimit(.minutes(1)))
  func nativeSendThatNeverFinishesTimesOutAtTheDeadline() async {
    let backend = NonCooperativeReportBackend()
    let deadline: UInt64 = 50_000_000
    let sender = UserSpaceReportSender(nativeSendDeadlineNanoseconds: deadline)
    sender.attach(backend)
    let start = DispatchTime.now().uptimeNanoseconds

    await #expect(throws: UserSpaceReportSender.Failure.sendTimedOut) {
      try await sender.submit { [[1]] }.value()
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    #expect(elapsed >= deadline)
    #expect(elapsed < UserSpaceReportSender.defaultNativeSendDeadlineNanoseconds)
    #expect(backend.closeCount() == 1)

    await backend.gate.release()
    await sender.beginClose().value
  }

  @Test(.timeLimit(.minutes(1)))
  func closeCompletesOnlyAfterTheNativeDeviceHasBeenTornDown() async {
    let backend = SlowTeardownBackend()
    let sender = UserSpaceReportSender()
    sender.attach(backend)
    let finished = ActivityFlag()
    finished.set(false)

    let closing = Task {
      await sender.beginClose().value
      finished.set(true)
    }
    await backend.gate.waitForEntry()
    #expect(backend.closeCount() == 1)
    #expect(!finished.get())

    await backend.gate.open()
    await closing.value
    #expect(finished.get())
  }

  @Test(.timeLimit(.minutes(1)))
  func stalledControllerPublicationDoesNotBlockAnotherController() async throws {
    let gate = ReportSendGate()
    let stalledBackend = OrderedReportBackend(gate: gate)
    let readyBackend = OrderedReportBackend()
    let stalled = UserSpaceReportSender()
    let ready = UserSpaceReportSender()
    stalled.attach(stalledBackend)
    ready.attach(readyBackend)

    let blocked = stalled.submit { [[1]] }
    await gate.waitForEntry()
    try await ready.submit { [[2]] }.value()
    #expect(readyBackend.snapshot().reports == [[2]])

    await gate.open()
    try await blocked.value()
    await stalled.beginClose().value
    await ready.beginClose().value
  }

  /// An Xbox One rumble report (ID 3) for the main motors, lasting the default 250 ms.
  private static func xboxRumble(_ left: UInt8, _ right: UInt8) -> [UInt8] {
    [0x03, 0x0C, 0, 0, left, right, 25, 0, 0]
  }
}
