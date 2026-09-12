#if canImport(SwiftUI)
  import Foundation
  import OpenJoystickDriverKit
  import Testing

  @testable import OpenJoystickDriver

  @MainActor struct MotionCalibrationStateTests {
    @Test func unavailableMotionClearsBusyStateAndProvidesRecoveryGuidance() async {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(RuntimeDeviceSelector(vendorID: 1, productID: 2, runtimeIdentifier: "first"))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      await gateway.fail()
      await request.value
      #expect(model.status == nil)
      #expect(!model.isBusy)
      #expect(model.errorMessage == OJDLocalized.string(
        "motion.calibration.motionUnavailable",
        fallback: "Enable a remapping profile for this controller "
          + "and check that motion is available."
      ))
    }

    @Test func discardedSelectionIgnoresLateCalibrationResult() async throws {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      model.select(RuntimeDeviceSelector(vendorID: 1, productID: 2, runtimeIdentifier: "first"))
      let request = Task { await model.refresh() }
      await gateway.waitForRequest()
      #expect(model.isBusy)
      model.select(nil)
      try await gateway.finish()
      await request.value
      #expect(model.status == nil)
      #expect(model.errorMessage == nil)
      #expect(!model.isBusy)
    }

    @Test func selectedControllerReceivesCalibrationStatus() async throws {
      let gateway = DelayedMotionCalibrationGateway()
      let model = MotionCalibrationViewModel(gateway: gateway)
      let selector = RuntimeDeviceSelector(vendorID: 1, productID: 2, runtimeIdentifier: "second")
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

  private actor DelayedMotionCalibrationGateway: MotionCalibrationGateway {
    var command: RemappingMotionCalibrationCommand?
    var selector: RuntimeDeviceSelector?
    private var pending: CheckedContinuation<RemappingMotionCalibrationStatus, any Error>?
    private var observer: CheckedContinuation<Void, Never>?

    func motionCalibration(
      for selector: RuntimeDeviceSelector,
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

    func fail() {
      pending?.resume(throwing: RemappingMotionCalibrationError.motionUnavailable)
      pending = nil
    }
  }
#endif
