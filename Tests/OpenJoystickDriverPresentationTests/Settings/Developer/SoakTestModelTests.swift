import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct SoakTestFormTests {
  @Test
  func formStartsAtValuesOfCommand() throws {
    let settings = try SoakTestForm().settings().get()

    #expect(
      settings
        == SoakTestSettings(
          seconds: 60,
          intervalMilliseconds: 1_000,
          residentLimitMiB: 0,
          footprintLimitMiB: 512
        )
    )
  }

  @Test
  func limitsBecomeHealthPolicyWhereZeroMeansNoLimit() throws {
    var form = SoakTestForm()
    form.residentLimit = "300"
    form.footprintLimit = "0"
    let policy = try form.settings().get().policy

    #expect(policy.maximumResidentBytes == 300 * 1_048_576)
    #expect(policy.maximumPhysicalFootprintBytes == nil)
  }

  @Test
  func textThatIsNotWholeNumberNamesItsField() {
    var form = SoakTestForm()
    form.interval = "fast"

    #expect(form.settings() == .failure(.notANumber(.interval)))
    form.interval = "1.5"
    #expect(form.settings() == .failure(.notANumber(.interval)))
    form.interval = ""
    #expect(form.settings() == .failure(.notANumber(.interval)))
  }

  @Test
  func everyFieldIsHeldToRangeOfItsOption() {
    let outOfRange: [(SoakTestField, String)] = [
      (.seconds, "0"), (.seconds, "86401"), (.interval, "99"), (.interval, "60001"),
      (.residentLimit, "-1"), (.residentLimit, "65537"), (.footprintLimit, "65537"),
    ]
    for (field, text) in outOfRange {
      var form = SoakTestForm()
      switch field {
      case .seconds: form.seconds = text
      case .interval: form.interval = text
      case .residentLimit: form.residentLimit = text
      case .footprintLimit: form.footprintLimit = text
      }
      #expect(form.settings() == .failure(.outOfRange(field)), "\(field) \(text)")
    }
    var edges = SoakTestForm()
    edges.seconds = "1"
    edges.interval = "60000"
    edges.residentLimit = "65536"
    #expect((try? edges.settings().get()) != nil)
  }

  @Test
  func runOfTooManySamplesIsRefused() {
    var form = SoakTestForm()
    form.seconds = "86400"
    form.interval = "100"

    #expect(form.settings() == .failure(.tooManySamples(864_001)))
  }

  @Test
  func problemMessageNamesFieldAndItsRange() {
    let label = OJDLocalized.string(SoakTestField.interval.labelKey)

    #expect(
      SoakTestProblem.outOfRange(.interval).message
        == OJDLocalized.formatted("ui.developer.soakOutOfRange", label, 100, 60_000)
    )
    #expect(SoakTestProblem.outOfRange(.interval).message.contains(label))
  }
}

@Suite
@MainActor
struct SoakTestModelTests {
  private final class Recorder: @unchecked Sendable {
    var processIDs: [Int32] = []
    var settings: [SoakTestSettings] = []
  }

  private static func snapshot(
    _ availability: DiagnoseServiceSnapshot.Availability
  )
    -> DiagnoseServiceSnapshot
  {
    DiagnoseServiceSnapshot(
      availability: availability,
      status: nil,
      virtualDiagnostics: nil,
      frameTimings: nil,
      listenerFailure: .absent
    )
  }

  private static func summary(
    residentBytes: UInt64,
    policy: RuntimeHealthPolicy = .standard
  ) throws -> RuntimeHealthSummary {
    let samples = (0..<7).map { index in
      RuntimeHealthSample(
        elapsedNanoseconds: UInt64(index) * 10_000_000_000,
        residentBytes: residentBytes,
        physicalFootprintBytes: residentBytes,
        cumulativeCPUNanoseconds: UInt64(index) * 1_000_000,
        fileDescriptorCount: 10,
        threadCount: 4
      )
    }
    return try #require(
      ApplicationServiceRuntimeHealthAnalyzer.summarize(samples, policy: policy)
    )
  }

  private static func model(
    availability: DiagnoseServiceSnapshot.Availability = .running,
    processID: Int32? = 4_242,
    recorder: Recorder = Recorder(),
    sample: @escaping @Sendable (Int32, SoakTestSettings) async throws -> RuntimeHealthSummary
  ) -> SoakTestModel {
    SoakTestModel(
      source: SoakTestModel.Source(
        snapshot: { snapshot(availability) },
        processIdentifier: { processID },
        sample: { processID, settings in
          recorder.processIDs.append(processID)
          recorder.settings.append(settings)
          return try await sample(processID, settings)
        }
      )
    )
  }

  private func finish(_ model: SoakTestModel) async {
    model.start()
    while model.isRunning { await Task.yield() }
  }

  @Test
  func stableRunPassesAndSamplesServiceWithEnteredSettings() async throws {
    let recorder = Recorder()
    let summary = try Self.summary(residentBytes: 50 * 1_048_576)
    let model = Self.model(recorder: recorder) { _, _ in summary }
    model.form.seconds = "90"
    model.form.interval = "500"
    model.form.footprintLimit = "256"

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.id == "runtime-health")
    #expect(row.status == .pass)
    #expect(recorder.processIDs == [4_242])
    #expect(
      recorder.settings
        == [
          SoakTestSettings(
            seconds: 90,
            intervalMilliseconds: 500,
            residentLimitMiB: 0,
            footprintLimitMiB: 256
          )
        ]
    )
  }

  @Test
  func limitThatServiceExceedsFails() async throws {
    let policy = RuntimeHealthPolicy(residentLimitMiB: 0, footprintLimitMiB: 10)
    let summary = try Self.summary(residentBytes: 50 * 1_048_576, policy: policy)
    let model = Self.model { _, _ in summary }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .fail)
  }

  @Test
  func stoppedServiceIsSkippedWithoutSampling() async {
    let recorder = Recorder()
    let model = Self.model(availability: .stopped, recorder: recorder) { _, _ in
      throw CancellationError()
    }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .skip)
    #expect(recorder.processIDs.isEmpty)
  }

  @Test
  func serviceWithoutProcessIsSkipped() async {
    let model = Self.model(processID: nil) { _, _ in throw CancellationError() }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .skip)
  }

  @Test
  func samplingFailureIsShownAsFailure() async {
    let model = Self.model { _, _ in throw RuntimeHealthSamplingError.processUnavailable(4_242) }

    await finish(model)

    guard case .finished(let row) = model.state else {
      Issue.record("Expected a finished run")
      return
    }
    #expect(row.status == .fail)
    #expect(row.detail == RuntimeHealthSamplingError.processUnavailable(4_242).errorDescription)
  }

  @Test
  func invalidSettingsDoNotStartRun() {
    let recorder = Recorder()
    let model = Self.model(recorder: recorder) { _, _ in throw CancellationError() }
    model.form.seconds = "0"

    model.start()

    #expect(model.state == .idle)
    #expect(model.problem == .outOfRange(.seconds))
    #expect(recorder.processIDs.isEmpty)
  }

  @Test(.timeLimit(.minutes(1)))
  func stoppingRunCancelsSamplerAndShowsEntryAgain() async {
    let probe = SoakSamplerProbe()
    let model = Self.model(sample: probe.sample)

    model.start()
    await probe.waitUntilSampling()
    #expect(model.isRunning)
    model.cancel()
    await probe.waitUntilCancelled()

    #expect(model.state == .idle)
  }

  @Test
  func stoppingWithoutRunLeavesResultInPlace() async throws {
    let summary = try Self.summary(residentBytes: 50 * 1_048_576)
    let model = Self.model { _, _ in summary }
    await finish(model)

    model.cancel()

    guard case .finished = model.state else {
      Issue.record("Expected the result to stay")
      return
    }
  }
}

/// A soak sampler that suspends until its task is cancelled, and reports when it started and when
/// it saw the cancellation.
final class SoakSamplerProbe: @unchecked Sendable {
  private let sampling: AsyncStream<Void>
  private let samplingContinuation: AsyncStream<Void>.Continuation
  private let cancelled: AsyncStream<Void>
  private let cancelledContinuation: AsyncStream<Void>.Continuation

  init() {
    (sampling, samplingContinuation) = AsyncStream.makeStream()
    (cancelled, cancelledContinuation) = AsyncStream.makeStream()
  }

  var sample: @Sendable (Int32, SoakTestSettings) async throws -> RuntimeHealthSummary {
    { [self] _, _ in
      try await withTaskCancellationHandler {
        samplingContinuation.yield()
        try await Task.sleep(nanoseconds: UInt64.max / 2)
        throw CancellationError()
      } onCancel: {
        cancelledContinuation.yield()
      }
    }
  }

  func waitUntilSampling() async {
    var iterator = sampling.makeAsyncIterator()
    _ = await iterator.next()
  }

  func waitUntilCancelled() async {
    var iterator = cancelled.makeAsyncIterator()
    _ = await iterator.next()
  }
}
