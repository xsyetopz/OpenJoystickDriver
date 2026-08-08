import SwifterKit
import Testing

@testable import OpenJoystickDriverRelay

struct RuntimeTests {
  @Test func startsSubmitsCountsAndStops() async throws {
    let host = RelayHost()
    let submitter = RelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: host)

    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())
    let delivered = await runtime.submit([HIDReport(bytes: [1], type: .input)])
    let stats = await runtime.statsSnapshot()
    let native = await runtime.runtimeStatisticsSnapshot()
    await runtime.setEnabled(false, revision: 2)

    #expect(delivered == 1)
    #expect(stats.attempts == 1)
    #expect(stats.successes == 1)
    #expect(stats.failures == 0)
    #expect(stats.connectionAttempts == 1)
    #expect(stats.connectionSuccesses == 1)
    #expect(native?.inputReportSuccesses == 1)
    #expect(await host.stopCount > 0)
    #expect(await submitter.reports.count == 1)
  }

  @Test func retriesOneShotDiscoveryWithBoundedBackoff() async throws {
    let host = RelayHost(failuresBeforeStart: 1)
    let runtime = DriverKitRelayRuntime(submitter: RelaySubmitter(), host: host)

    await runtime.setEnabled(true, revision: 1)
    try await Task.sleep(nanoseconds: 300_000_000)
    #expect(await runtime.waitUntilConnected())
    let stats = await runtime.statsSnapshot()
    await runtime.setEnabled(false, revision: 2)

    #expect(stats.connectionAttempts == 2)
    #expect(stats.connectionSuccesses == 1)
    #expect(stats.connectionFailures == 1)
  }

  @Test func rapidEnableUpdatesConvergeToLatestRevision() async {
    let runtime = DriverKitRelayRuntime(submitter: RelaySubmitter(), host: RelayHost())

    async let disable: Void = runtime.setEnabled(false, revision: 1)
    async let enable: Void = runtime.setEnabled(true, revision: 2)
    _ = await (disable, enable)

    #expect(await runtime.isEnabled)
    await runtime.setEnabled(false, revision: 3)
  }

  @Test func rapidDisableUpdatesConvergeToLatestRevision() async {
    let runtime = DriverKitRelayRuntime(submitter: RelaySubmitter(), host: RelayHost())

    async let enable: Void = runtime.setEnabled(true, revision: 1)
    async let disable: Void = runtime.setEnabled(false, revision: 2)
    _ = await (enable, disable)

    #expect(await !runtime.isEnabled)
  }

  @Test func disableStopsInFlightBatchAfterCurrentSubmission() async {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    let batch = Task {
      await runtime.submit([
        HIDReport(bytes: [1], type: .input), HIDReport(bytes: [2], type: .input),
        HIDReport(bytes: [3], type: .input),
      ])
    }
    await submitter.waitUntilFirstSubmissionStarts()
    let disabling = Task { await runtime.setEnabled(false, revision: 2) }
    for _ in 0..<1_000 {
      if await !runtime.isEnabled { break }
      await Task.yield()
    }
    await submitter.resumeFirstSubmission()

    #expect(await batch.value == 1)
    await disabling.value
    #expect(await submitter.reports.map(\.bytes) == [[1]])
  }

  @Test func submissionFailureKeepsConnectionCountersExactAndFormatsIOReturn() async {
    let error = DriverKitError(kind: .ioReturn(Int32(bitPattern: 0xE000_02CD)), operation: "submit")
    let runtime = DriverKitRelayRuntime(
      submitter: FailingRelaySubmitter(error: error),
      host: RelayHost()
    )
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    #expect(await runtime.submit([HIDReport(bytes: [1], type: .input)]) == 0)
    for _ in 0..<100 { await Task.yield() }
    let stats = await runtime.statsSnapshot()
    await runtime.setEnabled(false, revision: 2)

    #expect(stats.failures == 1)
    #expect(stats.lastErrorHex == "0xe00002cd")
    #expect(stats.connectionFailures == 0)
  }

  @Test func connectionFailureFormatsIndependentIOReturn() async {
    let error = DriverKitError(kind: .ioReturn(Int32(bitPattern: 0xE000_02C0)), operation: "open")
    let runtime = DriverKitRelayRuntime(
      submitter: RelaySubmitter(),
      host: FailingRelayHost(error: error)
    )
    await runtime.setEnabled(true, revision: 1)
    for _ in 0..<1_000 {
      if await runtime.statsSnapshot().connectionFailures > 0 { break }
      await Task.yield()
    }
    await runtime.setEnabled(false, revision: 2)
    let stats = await runtime.statsSnapshot()

    #expect(stats.lastConnectionErrorHex == "0xe00002c0")
    #expect(stats.lastErrorHex == nil)
  }

  @Test func overlappingDisableRequestsShareOneShutdownBeforeLatestEnable() async {
    let host = SuspendedStopRelayHost()
    let runtime = DriverKitRelayRuntime(submitter: RelaySubmitter(), host: host)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    let firstDisable = Task { await runtime.setEnabled(false, revision: 2) }
    await host.waitUntilStopStarts()
    let secondDisable = Task { await runtime.setEnabled(false, revision: 3) }
    await runtime.setEnabled(true, revision: 4)
    #expect(await runtime.isEnabled)
    #expect(await host.stopCount == 1)

    await host.resumeStop()
    await firstDisable.value
    await secondDisable.value
    #expect(await runtime.waitUntilConnected())
    #expect(await host.startCount == 2)
    await runtime.setEnabled(false, revision: 5)
    await host.resumeStop()
  }

  @Test func delayedSubmissionFailureCannotMaskNextSupervisorFailure() async {
    let connectionError = DriverKitError(
      kind: .ioReturn(Int32(bitPattern: 0xE000_02C0)),
      operation: "run"
    )
    let host = SequencedRelayHost(secondRunError: connectionError)
    let submitter = DelayedFailingRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: host)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    let submission = Task { await runtime.submit([HIDReport(bytes: [1], type: .input)]) }
    await submitter.waitUntilSubmissionStarts()
    await runtime.setEnabled(false, revision: 2)
    await runtime.setEnabled(true, revision: 3)
    #expect(await runtime.waitUntilConnected())
    await submitter.resumeWithFailure()
    _ = await submission.value
    await host.allowSecondRunFailure()
    for _ in 0..<1_000 {
      if await runtime.statsSnapshot().connectionFailures > 0 { break }
      await Task.yield()
    }
    let stats = await runtime.statsSnapshot()

    #expect(stats.connectionFailures == 1)
    #expect(stats.lastConnectionErrorHex == "0xe00002c0")
    #expect(stats.failures == 1)
    await runtime.setEnabled(false, revision: 4)
  }
}

enum RelayTestError: Error { case discovery }

actor RelayHost: DriverKitRelayHosting {
  private var failuresBeforeStart: Int
  private var stopped = false
  private(set) var stopCount = 0

  init(failuresBeforeStart: Int = 0) { self.failuresBeforeStart = failuresBeforeStart }

  func start() throws -> String {
    if failuresBeforeStart > 0 {
      failuresBeforeStart -= 1
      throw RelayTestError.discovery
    }
    stopped = false
    return "connected fake|1"
  }

  func run() async throws { while !stopped { try await Task.sleep(nanoseconds: 1_000_000) } }

  func stop() {
    stopped = true
    stopCount += 1
  }
}

actor FailingRelayHost: DriverKitRelayHosting {
  let error: DriverKitError

  init(error: DriverKitError) { self.error = error }
  func start() throws -> String { throw error }
  func run() async throws { await Task.yield() }
  func stop() {}
}

actor RelaySubmitter: DriverKitRelaySubmitting {
  private(set) var reports: [HIDReport] = []

  func submit(_ report: HIDReport) { reports.append(report) }
  func statistics() -> HIDRuntimeStatistics {
    HIDRuntimeStatistics(
      inputReportAttempts: UInt64(reports.count),
      inputReportSuccesses: UInt64(reports.count),
      inputReportFailures: 0
    )
  }
}

actor FailingRelaySubmitter: DriverKitRelaySubmitting {
  let error: DriverKitError

  init(error: DriverKitError) { self.error = error }
  func submit(_ report: HIDReport) throws { throw error }
  func statistics() -> HIDRuntimeStatistics {
    HIDRuntimeStatistics(inputReportAttempts: 1, inputReportSuccesses: 0, inputReportFailures: 1)
  }
}

actor SuspendedRelaySubmitter: DriverKitRelaySubmitting {
  private(set) var reports: [HIDReport] = []
  private var firstContinuation: CheckedContinuation<Void, Never>?

  func submit(_ report: HIDReport) async {
    reports.append(report)
    if reports.count == 1 { await withCheckedContinuation { firstContinuation = $0 } }
  }

  func waitUntilFirstSubmissionStarts() async { while reports.isEmpty { await Task.yield() } }

  func resumeFirstSubmission() {
    firstContinuation?.resume()
    firstContinuation = nil
  }

  func statistics() -> HIDRuntimeStatistics {
    HIDRuntimeStatistics(
      inputReportAttempts: UInt64(reports.count),
      inputReportSuccesses: UInt64(reports.count),
      inputReportFailures: 0
    )
  }
}

actor SuspendedStopRelayHost: DriverKitRelayHosting {
  private var stopped = false
  private var stopContinuation: CheckedContinuation<Void, Never>?
  private(set) var startCount = 0
  private(set) var stopCount = 0

  func start() -> String {
    startCount += 1
    stopped = false
    return "connected suspended-stop|\(startCount)"
  }

  func run() async throws { while !stopped { try await Task.sleep(nanoseconds: 1_000_000) } }

  func stop() async {
    stopped = true
    stopCount += 1
    if stopCount == 1 { await withCheckedContinuation { stopContinuation = $0 } }
  }

  func waitUntilStopStarts() async { while stopCount == 0 { await Task.yield() } }

  func resumeStop() {
    stopContinuation?.resume()
    stopContinuation = nil
  }
}

actor SequencedRelayHost: DriverKitRelayHosting {
  private let secondRunError: DriverKitError
  private var stopped = false
  private var runCount = 0
  private var secondRunCanFail = false

  init(secondRunError: DriverKitError) { self.secondRunError = secondRunError }

  func start() -> String {
    stopped = false
    return "connected sequence"
  }

  func run() async throws {
    runCount += 1
    if runCount == 1 {
      while !stopped { try await Task.sleep(nanoseconds: 1_000_000) }
      return
    }
    while !secondRunCanFail { await Task.yield() }
    throw secondRunError
  }

  func stop() { stopped = true }
  func allowSecondRunFailure() { secondRunCanFail = true }
}

actor DelayedFailingRelaySubmitter: DriverKitRelaySubmitting {
  private var continuation: CheckedContinuation<Void, Never>?
  private var started = false

  func submit(_ report: HIDReport) async throws {
    started = true
    await withCheckedContinuation { continuation = $0 }
    throw DriverKitError(kind: .serviceUnavailable, operation: "submit")
  }

  func waitUntilSubmissionStarts() async { while !started { await Task.yield() } }

  func resumeWithFailure() {
    continuation?.resume()
    continuation = nil
  }

  func statistics() -> HIDRuntimeStatistics {
    HIDRuntimeStatistics(inputReportAttempts: 1, inputReportSuccesses: 0, inputReportFailures: 1)
  }
}
