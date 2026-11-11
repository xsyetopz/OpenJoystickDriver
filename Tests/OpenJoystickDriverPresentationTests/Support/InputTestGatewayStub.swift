import Combine
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct RecordedRumble: Equatable, Sendable {
  let selector: ControllerReference
  let left: UInt8
  let right: UInt8
  let leftTrigger: UInt8
  let rightTrigger: UInt8
  let durationMilliseconds: Int
}

enum InputTestGatewayError: Error { case outputFailed }

actor InputTestGatewayStub: InputTestDeviceGateway {
  func motionCalibration(
    for selector: ControllerReference,
    command: RemappingMotionCalibrationCommand?
  ) throws -> RemappingMotionCalibrationStatus {
    throw RemappingMotionCalibrationError.motionUnavailable
  }
  var inputSequence: [ControllerState?]
  var inputDelayNanoseconds: UInt64
  var outputDelayNanoseconds: UInt64
  var inputCalls = 0
  var cancelledInputCalls = 0
  var activeInputCalls = 0
  var maximumConcurrentInputCalls = 0
  var inputSelectors: [ControllerReference] = []
  var rumbleCalls: [RecordedRumble] = []
  var playerCalls: [(ControllerReference, PhysicalPlayerIndicator)] = []
  var colorCalls: [(ControllerReference, UInt8, UInt8, UInt8)] = []
  var colorReleaseCalls: [(ControllerReference, UUID)] = []
  var brightnessCalls: [(ControllerReference, UInt8)] = []
  var outputResult = true
  var outputThrows = false
  var activeOutputCalls = 0
  var maximumConcurrentOutputCalls = 0

  init(
    inputSequence: [ControllerState?] = [],
    inputDelayNanoseconds: UInt64 = 0,
    outputDelayNanoseconds: UInt64 = 0
  ) {
    self.inputSequence = inputSequence
    self.inputDelayNanoseconds = inputDelayNanoseconds
    self.outputDelayNanoseconds = outputDelayNanoseconds
  }

  func controllerState(for selector: ControllerReference) async throws -> ControllerState? {
    inputCalls += 1
    activeInputCalls += 1
    maximumConcurrentInputCalls = max(maximumConcurrentInputCalls, activeInputCalls)
    inputSelectors.append(selector)
    defer { activeInputCalls -= 1 }
    if inputDelayNanoseconds > 0 {
      do { try await Task.sleep(nanoseconds: inputDelayNanoseconds) } catch {
        cancelledInputCalls += 1
        throw error
      }
    }
    guard !inputSequence.isEmpty else { return nil }
    return inputSequence.removeFirst()
  }

  /// Records each command in the call list of its kind; stop-rumble is the all-zero rumble of
  /// 0 ms the model sent before the single output command.
  func sendControllerOutput(
    _ command: ControllerOutputCommand,
    for selector: ControllerReference
  ) async throws -> ControllerOutputResult {
    try await beginOutputCall()
    defer { finishOutputCall() }
    switch command {
    case .setRumble(let intensities, let duration):
      if outputThrows { throw InputTestGatewayError.outputFailed }
      guard case .milliseconds(let durationMilliseconds) = duration else {
        throw InputTestGatewayError.outputFailed
      }
      rumbleCalls.append(
        RecordedRumble(
          selector: selector,
          left: intensities.lowFrequency.byte,
          right: intensities.highFrequency.byte,
          leftTrigger: intensities.leftTrigger.byte,
          rightTrigger: intensities.rightTrigger.byte,
          durationMilliseconds: durationMilliseconds
        )
      )
    case .stopRumble:
      if outputThrows { throw InputTestGatewayError.outputFailed }
      rumbleCalls.append(
        RecordedRumble(
          selector: selector,
          left: 0,
          right: 0,
          leftTrigger: 0,
          rightTrigger: 0,
          durationMilliseconds: 0
        )
      )
    case .setPlayerIndicator(let indicator): playerCalls.append((selector, indicator))
    case .setLightBrightness(let brightness): brightnessCalls.append((selector, brightness.byte))
    case .setRGB, .setAdaptiveTrigger, .speaker: throw InputTestGatewayError.outputFailed
    }
    return ControllerOutputResult(outputResult ? .delivered : .writeFailed)
  }

  func previewColor(
    for selector: ControllerReference,
    token _: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    try await beginOutputCall()
    defer { finishOutputCall() }
    colorCalls.append((selector, red, green, blue))
    return outputResult
  }

  func releaseColorPreview(for selector: ControllerReference, token: UUID) async throws -> Bool {
    await Task.yield()
    colorReleaseCalls.append((selector, token))
    return outputResult
  }

  func counts() -> (
    input: Int, cancelled: Int, maximumConcurrentInput: Int, maximumConcurrentOutput: Int,
    rumble: Int, player: Int, color: Int, brightness: Int
  ) {
    (
      inputCalls, cancelledInputCalls, maximumConcurrentInputCalls, maximumConcurrentOutputCalls,
      rumbleCalls.count, playerCalls.count, colorCalls.count, brightnessCalls.count
    )
  }

  func setOutputResult(_ result: Bool) { outputResult = result }
  func setOutputThrows(_ value: Bool) { outputThrows = value }
  func setOutputDelay(_ nanoseconds: UInt64) { outputDelayNanoseconds = nanoseconds }

  func waitForActiveOutputCall() async {
    await waitUntil("an output call is active") { activeOutputCalls > 0 }
  }

  func waitForInputCalls(_ expectedCount: Int) async {
    await waitUntil("\(expectedCount) input calls are made") { inputCalls >= expectedCount }
  }

  func waitForRumbleCalls(_ expectedCount: Int) async {
    await waitUntil("\(expectedCount) rumble calls are made") {
      rumbleCalls.count >= expectedCount
    }
  }

  private func beginOutputCall() async throws {
    activeOutputCalls += 1
    maximumConcurrentOutputCalls = max(maximumConcurrentOutputCalls, activeOutputCalls)
    if outputDelayNanoseconds > 0 {
      do { try await Task.sleep(nanoseconds: outputDelayNanoseconds) } catch {
        // Callers install their cleanup defer only after this helper returns successfully.
        activeOutputCalls -= 1
        throw error
      }
    }
  }

  private func finishOutputCall() { activeOutputCalls -= 1 }
}
