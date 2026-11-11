#if canImport(SwiftUI)
  import Foundation
  import OpenJoystickDriverKit
  import OpenJoystickDriverTestSupport
  import Testing

  @testable import OpenJoystickDriverPresentation

  @MainActor
  struct MotionCalibrationStateTests {
    @Test
    func unavailableMotionClearsBusyStateAndProvidesRecoveryGuidance() async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail()
      await request.value
      #expect(model.status == nil)
      #expect(!model.isBusy)
      #expect(
        model.errorMessage
          == OJDLocalized.string(
            "ui.motion.calibration.motionUnavailable"
          )
      )
    }

    @Test(arguments: [
      ApplicationServiceRemappingRPCError.Code.motionGyroNotSelected,
      .motionProfileInactive,
      .motionSessionChanged,
    ])
    func serviceRefusalShowsTheExplanationOfItsCode(
      code: ApplicationServiceRemappingRPCError.Code
    ) async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail(ApplicationServiceRemappingRPCError(code: code, message: "service text"))
      await request.value
      #expect(model.errorMessage == code.errorCode.localizedExplanation)
    }

    @Test
    func serviceMotionUnavailableGivesTheRecoveryGuidance() async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail(
        ApplicationServiceRemappingRPCError(code: .motionUnavailable, message: "service text")
      )
      await request.value
      #expect(
        model.errorMessage == OJDLocalized.string("ui.motion.calibration.motionUnavailable")
      )
    }

    @Test
    func discardedSelectionIgnoresLateCalibrationResult() async throws {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let request = Task { await model.perform(.start) }
      await gateway.waitForRequest()
      #expect(model.isBusy)
      model.select(nil)
      try await gateway.finish()
      await request.value
      #expect(model.status == nil)
      #expect(model.errorMessage == nil)
      #expect(!model.isBusy)
    }

    @Test
    func selectedControllerReceivesCalibrationStatus() async throws {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      let selector = ControllerReference.session(.fixture("second"))
      model.select(selector)
      let request = Task { await model.perform(.start) }
      await gateway.waitForRequest()
      await model.perform(.reset)
      #expect(await gateway.command == .start)
      #expect(await gateway.selector == selector)
      try await gateway.finish()
      await request.value
      #expect(model.status?.isCollecting == true)
      #expect(model.status?.hasMotionBaseline == true)
      #expect(!model.isBusy)
    }
  }

  extension MotionCalibrationStateTests {
    private static func status(
      baseline: Bool,
      collecting: Bool
    ) throws
      -> RemappingMotionCalibrationStatus
    {
      try JSONDecoder().decode(
        RemappingMotionCalibrationStatus.self,
        from: Data(
          """
          {"hasMotionBaseline":\(baseline),"isCollecting":\(collecting),
            "offsetDegreesPerSecond":{"x":0,"y":0,"z":0}}
          """.utf8
        )
      )
    }

    @Test
    func statusRefreshesOnlyWhileTheBaselineIsMissingOrSamplesAreCollected() throws {
      let waiting = try Self.status(baseline: false, collecting: false)
      let collecting = try Self.status(baseline: true, collecting: true)
      let settled = try Self.status(baseline: true, collecting: false)
      #expect(MotionCalibrationViewModel.needsRefresh(status: waiting, errorMessage: nil))
      #expect(MotionCalibrationViewModel.needsRefresh(status: collecting, errorMessage: nil))
      #expect(!MotionCalibrationViewModel.needsRefresh(status: settled, errorMessage: nil))
      #expect(!MotionCalibrationViewModel.needsRefresh(status: nil, errorMessage: nil))
      #expect(!MotionCalibrationViewModel.needsRefresh(status: waiting, errorMessage: "failed"))
    }

    @Test
    func refreshLoopReadsUntilCalibrationSettlesThenStops() async throws {
      let gateway = ScriptedMotionCalibrationGateway(results: [
        .success(try Self.status(baseline: false, collecting: false)),
        .success(try Self.status(baseline: true, collecting: true)),
        .success(try Self.status(baseline: true, collecting: false)),
      ])
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let sleeps = SleepCounter()
      await model.refreshWhileCalibrating { nanoseconds in
        sleeps.record(nanoseconds)
      }
      #expect(await gateway.reads == 3)
      #expect(
        sleeps.values
          == Array(repeating: MotionCalibrationViewModel.refreshIntervalNanoseconds, count: 2)
      )
      #expect(model.status?.isCollecting == false)
    }

    @Test
    func failedReadStopsTheLoopAndKeepsTheError() async {
      let gateway = ScriptedMotionCalibrationGateway(results: [
        .failure(RemappingMotionCalibrationError.motionUnavailable)
      ])
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      await model.refreshWhileCalibrating { _ in Issue.record("no retry after a failure") }
      #expect(await gateway.reads == 1)
      #expect(model.errorMessage == OJDLocalized.string("ui.motion.calibration.motionUnavailable"))
    }
  }

  extension MotionCalibrationStateTests {
    @Test
    func aStatusReadDoesNotMarkTheModelBusy() async throws {
      let gateway = QueuedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let poll = Task { await model.refresh() }
      await gateway.waitForRequests(1)
      #expect(!model.isBusy)
      await gateway.answer(0, with: .success(try Self.status(baseline: true, collecting: false)))
      await poll.value
      #expect(model.status?.hasMotionBaseline == true)
    }

    @Test
    func aCommandDuringAReadIsPerformedAndTheStaleReadIsIgnored() async throws {
      let gateway = QueuedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let poll = Task { await model.refresh() }
      await gateway.waitForRequests(1)
      let command = Task { await model.perform(.start) }
      await gateway.waitForRequests(2)
      #expect(await gateway.commands == [nil, .start])
      #expect(model.isBusy)
      await gateway.answer(1, with: .success(try Self.status(baseline: true, collecting: true)))
      await command.value
      await gateway.answer(0, with: .success(try Self.status(baseline: false, collecting: false)))
      await poll.value
      #expect(model.status?.isCollecting == true)
      #expect(model.status?.hasMotionBaseline == true)
      #expect(!model.isBusy)
    }

    @Test
    func aReadThatStartedDuringACommandCannotOverwriteItsResult() async throws {
      let gateway = QueuedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(ControllerReference.session(.fixture("first")))
      let command = Task { await model.perform(.start) }
      await gateway.waitForRequests(1)
      let poll = Task { await model.refresh() }
      await gateway.waitForRequests(2)
      await gateway.answer(0, with: .success(try Self.status(baseline: true, collecting: true)))
      await command.value
      await gateway.answer(1, with: .success(try Self.status(baseline: false, collecting: false)))
      await poll.value
      #expect(model.status?.isCollecting == true)
    }
  }

  private actor QueuedMotionCalibrationGateway: MotionCalibrationGateway {
    private var continuations: [CheckedContinuation<RemappingMotionCalibrationStatus, any Error>] =
      []
    private(set) var commands: [RemappingMotionCalibrationCommand?] = []
    private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func motionCalibration(
      for _: ControllerReference,
      command: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus {
      commands.append(command)
      return try await withCheckedThrowingContinuation { continuation in
        continuations.append(continuation)
        if let waiter, commands.count >= waiter.count {
          self.waiter = nil
          waiter.continuation.resume()
        }
      }
    }

    func waitForRequests(_ count: Int) async {
      guard commands.count < count else { return }
      await withCheckedContinuation { waiter = (count, $0) }
    }

    func answer(_ index: Int, with result: Result<RemappingMotionCalibrationStatus, any Error>) {
      continuations[index].resume(with: result)
    }
  }

  private final class SleepCounter: @unchecked Sendable {
    private(set) var values: [UInt64] = []
    func record(_ value: UInt64) { values.append(value) }
  }

  private actor ScriptedMotionCalibrationGateway: MotionCalibrationGateway {
    private var results: [Result<RemappingMotionCalibrationStatus, any Error>]
    private(set) var reads = 0

    init(results: [Result<RemappingMotionCalibrationStatus, any Error>]) { self.results = results }

    // swiftlint:disable async_without_await
    func motionCalibration(
      for _: ControllerReference,
      command _: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus {
      reads += 1
      return try results.removeFirst().get()
    }
    // swiftlint:enable async_without_await
  }

  private actor DelayedMotionCalibrationGateway: MotionCalibrationGateway {
    var command: RemappingMotionCalibrationCommand?
    var selector: ControllerReference?
    private var pending: CheckedContinuation<RemappingMotionCalibrationStatus, any Error>?
    private var observer: CheckedContinuation<Void, Never>?

    func motionCalibration(
      for selector: ControllerReference,
      command: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus {
      self.selector = selector
      self.command = command
      return try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        observer?.resume()
        observer = nil
      }
    }

    func waitForRequest() async {
      if pending != nil { return }
      await withCheckedContinuation { observer = $0 }
    }

    func finish() throws {
      let data = Data(
        """
        {"hasMotionBaseline":true,"isCollecting":true,
          "offsetDegreesPerSecond":{"x":0,"y":0,"z":0}}
        """.utf8
      )
      let status = try JSONDecoder().decode(RemappingMotionCalibrationStatus.self, from: data)
      pending?.resume(returning: status)
      pending = nil
    }

    func fail(_ error: any Error = RemappingMotionCalibrationError.motionUnavailable) {
      pending?.resume(throwing: error)
      pending = nil
    }
  }
#endif
