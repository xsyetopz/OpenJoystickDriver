import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverRelay

struct OutputTests {
  @Test func unstableNotificationUsesDriverKitOwnerName() {
    #expect(
      DriverKitOutputDispatcher.unstableNotification.rawValue
        == "OpenJoystickDriver.DriverKitUnstable"
    )
  }

  @Test func enableBridgeCoalescesStressAndAppliesLatestRequest() async {
    let runtime = DriverKitRelayRuntime(submitter: RelaySubmitter(), host: RelayHost())
    let bridge = DriverKitStateBridge { enabled, revision in
      await runtime.setEnabled(enabled, revision: revision)
    }
    var finalRevision: UInt64 = 0

    for index in 0..<5_000 { finalRevision = bridge.request(!index.isMultiple(of: 2)) }
    await bridge.wait(untilApplied: finalRevision)
    let metrics = bridge.metrics()

    #expect(await runtime.isEnabled)
    #expect(metrics.requestedRevision == 5_000)
    #expect(metrics.appliedRevision == 5_000)
    #expect(metrics.maximumConcurrentWorkers == 1)
    #expect(metrics.workerStarts < 5_000)
  }

  @Test func backendPublishesIntegrityRelayContract() {
    let backend: any VirtualControllerBackend = DriverKitOutputDispatcher()

    #expect(backend.backendID == .driverKitHID)
    #expect(backend.capabilities.isImplemented)
    #expect(backend.capabilities.isSystemWide)
    #expect(backend.capabilities.requiresEntitlement)
    #expect(!backend.capabilities.publishesConsumerGamepad)
    #expect(backend.capabilities.notes.contains("integrity relay"))
  }

  @Test func diagnosticProbeIsBoundedAndEndsNeutral() {
    let reports = DriverKitOutputDispatcher.diagnosticProbeReports(reportCount: 1_000)

    #expect(reports.count == 100)
    #expect(reports.allSatisfy { $0.count == GamepadHIDDescriptor.reportSize })
    #expect((reports[0][0] & 0x01) == 0x01)
    #expect(reports.last?.allSatisfy { $0 == 0 } == true)
  }

  @Test func concurrentDispatchIsOrderedCoalescedAndAlwaysUsesPrimaryReport() async {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    await pipeline.dispatch(events: [.buttonPressed(.a)])
    await submitter.waitUntilFirstSubmissionStarts()
    await pipeline.dispatch(events: [.buttonReleased(.a)])
    await pipeline.dispatch(events: [.buttonPressed(.guide)])
    await submitter.resumeFirstSubmission()
    await waitForReportCount(2, submitter: submitter)

    let reports = await submitter.reports
    #expect(reports.count == 2)
    #expect(reports.allSatisfy { $0.bytes.count == DriverKitRelayIdentity.reportSize })
    #expect(reports.allSatisfy { $0.options == 0 })
    #expect((reports[0].bytes[0] & 0x01) == 0x01)
    #expect((reports[1].bytes[0] & 0x01) == 0)
    #expect((reports[1].bytes[1] & 0x04) == 0x04)

    await pipeline.dispatch(events: [.buttonReleased(.guide)])
    await waitForReportCount(3, submitter: submitter)
    let release = await submitter.reports.last
    #expect(release?.bytes.count == DriverKitRelayIdentity.reportSize)
    #expect(release?.options == 0)
    #expect(((release?.bytes[1] ?? 0) & 0x04) == 0)
    await runtime.setEnabled(false, revision: 2)
  }

  @Test func mailboxOverloadKeepsOnePendingSnapshotAndOneWorker() async {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    await pipeline.dispatch(events: [.buttonPressed(.a)])
    await submitter.waitUntilFirstSubmissionStarts()
    for index in 0..<5_000 {
      let event: ControllerEvent =
        index.isMultiple(of: 2) ? .buttonPressed(.b) : .buttonReleased(.b)
      await pipeline.dispatch(events: [event])
    }
    let metrics = await pipeline.metrics()

    #expect(metrics.pendingReportCapacity == 1)
    #expect(metrics.maximumPendingReports == 1)
    #expect(metrics.coalescedReports >= 4_999)
    #expect(metrics.maximumConcurrentWorkers == 1)
    #expect(metrics.workerStarts == 1)
    #expect(metrics.diagnosticCapacity == 4)

    await submitter.resumeFirstSubmission()
    await waitForReportCount(2, submitter: submitter)
    await runtime.setEnabled(false, revision: 2)
  }

  @Test func queuedDiagnosticCompletesDuringContinuousReportRefill() async throws {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    await pipeline.dispatch(events: [.buttonPressed(.a)])
    await submitter.waitUntilFirstSubmissionStarts()
    let diagnostic = Task {
      await pipeline.submit(reports: [
        HIDReport(bytes: [UInt8](repeating: 9, count: 15), type: .input)
      ])
    }
    for index in 0..<5_000 {
      let event: ControllerEvent =
        index.isMultiple(of: 2) ? .buttonPressed(.b) : .buttonReleased(.b)
      await pipeline.dispatch(events: [event])
    }
    await submitter.resumeFirstSubmission()

    #expect(await diagnostic.value == 1)
    await waitForReportCount(3, submitter: submitter)
    let diagnosticReport = try #require(await submitter.reports.dropFirst().first)
    #expect(diagnosticReport.bytes == [UInt8](repeating: 9, count: 15))
    await runtime.setEnabled(false, revision: 2)
  }

  @Test func suppressionDropsQueuedStateAndResumeStartsNeutral() async throws {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    let suppression = DriverKitStateBridge(preservesTrueEdges: true) { value, revision in
      await pipeline.setSuppressed(value, revision: revision)
    }
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    await pipeline.dispatch(events: [.buttonPressed(.a)])
    await submitter.waitUntilFirstSubmissionStarts()
    await pipeline.dispatch(events: [.buttonPressed(.b)])
    _ = suppression.request(true)
    let resumedRevision = suppression.request(false)
    await suppression.wait(untilApplied: resumedRevision)
    await submitter.resumeFirstSubmission()
    await pipeline.dispatch(events: [])
    await waitForReportCount(2, submitter: submitter)

    let reports = await submitter.reports
    #expect(reports.count == 2)
    let resumed = try #require(reports.dropFirst().first)
    #expect(resumed.bytes == [UInt8](repeating: 0, count: DriverKitRelayIdentity.reportSize))
    await runtime.setEnabled(false, revision: 2)
  }

  @Test func cancelledQueuedDiagnosticResolvesWithoutWaitingForDrain() async {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    await pipeline.dispatch(events: [.buttonPressed(.a)])
    await submitter.waitUntilFirstSubmissionStarts()
    let diagnostic = Task {
      await pipeline.submit(reports: [
        HIDReport(bytes: [UInt8](repeating: 9, count: 15), type: .input)
      ])
    }
    await Task.yield()
    diagnostic.cancel()

    #expect(await diagnostic.value == 0)
    await submitter.resumeFirstSubmission()
    await runtime.setEnabled(false, revision: 2)
  }

  @Test func cancelledInFlightDiagnosticCannotMutateCountersAfterResponse() async {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    let completion = DiagnosticResult()
    let diagnostic = Task {
      let delivered = await pipeline.submit(reports: [
        HIDReport(bytes: [UInt8](repeating: 9, count: 15), type: .input)
      ])
      await completion.record(delivered)
      return delivered
    }
    await submitter.waitUntilFirstSubmissionStarts()
    diagnostic.cancel()
    for _ in 0..<100 { await Task.yield() }
    #expect(await completion.value == nil)
    await submitter.resumeFirstSubmission()
    #expect(await diagnostic.value == 1)
    let responseStats = await runtime.statsSnapshot()
    for _ in 0..<100 { await Task.yield() }
    let settledStats = await runtime.statsSnapshot()

    #expect(responseStats.attempts == 1)
    #expect(responseStats.successes == 1)
    #expect(settledStats.successes == responseStats.successes)
    await runtime.setEnabled(false, revision: 2)
  }

  @Test func suppressionWaitsForInFlightDiagnosticAndPreventsLateMutation() async {
    let submitter = SuspendedRelaySubmitter()
    let runtime = DriverKitRelayRuntime(submitter: submitter, host: RelayHost())
    let pipeline = DriverKitReportPipeline(runtime: runtime)
    await runtime.setEnabled(true, revision: 1)
    #expect(await runtime.waitUntilConnected())

    let diagnostic = Task {
      await pipeline.submit(reports: [
        HIDReport(bytes: [UInt8](repeating: 9, count: 15), type: .input)
      ])
    }
    await submitter.waitUntilFirstSubmissionStarts()
    await pipeline.setSuppressed(true, revision: 1)
    for _ in 0..<100 { await Task.yield() }
    await submitter.resumeFirstSubmission()
    #expect(await diagnostic.value == 1)
    let responseStats = await runtime.statsSnapshot()
    for _ in 0..<100 { await Task.yield() }
    let settledStats = await runtime.statsSnapshot()

    #expect(settledStats.successes == responseStats.successes)
    await runtime.setEnabled(false, revision: 2)
  }

  private func waitForReportCount(_ expected: Int, submitter: SuspendedRelaySubmitter) async {
    for _ in 0..<10_000 {
      if await submitter.reports.count >= expected { return }
      await Task.yield()
    }
  }
}

private actor DiagnosticResult {
  private(set) var value: Int?

  func record(_ value: Int) { self.value = value }
}
