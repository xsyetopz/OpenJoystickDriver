import Foundation
import SwiftUSB
import Testing

@testable import OpenJoystickDriverKit

struct DevicePipelineSleepTests {
  @Test
  func testSleepingPipelineKeepsPhysicalInputStateButStopsVirtualDispatch() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000,
      idleMonitorIntervalNanoseconds: 10_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([2]))

    try? await Task.sleep(nanoseconds: 80_000_000)

    let dispatchCountBeforeSleepInput = dispatcher.dispatchCount
    await pipeline.feedHIDData(Data([3]))

    #expect(dispatcher.dispatchCount == dispatchCountBeforeSleepInput)
    #expect(abs(pipeline.inputState().leftStickX - 0.8) < 0.001)
  }

  @Test

  func testForegroundGateNeutralizesOutputAndWaitsForNeutralBeforeResuming() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a)])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a)])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([2]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a)])

    await pipeline.feedHIDData(Data([4]))
    #expect(
      dispatcher.flattenedEvents
        == [.buttonPressed(.a), .buttonReleased(.a), .buttonPressed(.b)]
    )
  }

  @Test
  func testForegroundGateRearmsAfterFirstPostFocusChangeWithoutFullNeutral() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([3]))
    #expect(dispatcher.flattenedEvents == [.leftStickChanged(x: 0.8, y: 0)])

    await pipeline.setExternalOutputAllowed(false)
    #expect(
      dispatcher.flattenedEvents
        == [.leftStickChanged(x: 0.8, y: 0), .leftStickChanged(x: 0, y: 0)]
    )

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([5]))
    #expect(
      dispatcher.flattenedEvents
        == [.leftStickChanged(x: 0.8, y: 0), .leftStickChanged(x: 0, y: 0)]
    )

    await pipeline.feedHIDData(Data([4]))
    #expect(
      dispatcher.flattenedEvents
        == [.leftStickChanged(x: 0.8, y: 0), .leftStickChanged(x: 0, y: 0), .buttonPressed(.b)]
    )
  }

  @Test
  func testRepeatedAllowedSignalDoesNotRearmForegroundGate() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([4]))

    #expect(dispatcher.flattenedEvents == [.buttonPressed(.b)])
  }

  @Test
  func testPipelineSuppressesContradictoryDuplicateAndInvalidParserEvents() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([9]))
    await pipeline.feedHIDData(Data([11]))
    #expect(dispatcher.flattenedEvents.isEmpty)

    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([10]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a)])
  }

  @Test
  func testStopNeutralizesForwardedButtonState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.stop()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a)])
  }

  @Test
  func testStopNeutralizesForwardedDpadAndAxesState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 100, productID: 200),
      transport: .hid(locationID: 1),
      parser: ScriptedInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([6]))
    await pipeline.feedHIDData(Data([3]))
    await pipeline.stop()
    try? await Task.sleep(nanoseconds: 20_000_000)

    #expect(
      dispatcher.flattenedEvents == [
        .dpadChanged(.north),
        .leftStickChanged(x: 0.8, y: 0),
        .dpadChanged(.neutral),
        .leftStickChanged(x: 0, y: 0),
      ]
    )
  }

  @Test
  func testInputConnectionLifecycleDefersAndStopsOutput() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 10462, productID: 4418),
      transport: .hid(locationID: 1),
      parser: ScriptedLifecycleInputParser(),
      dispatcher: dispatcher,
      usbContext: nil,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    #expect(await pipeline.hidShutdownFeatureReports().isEmpty)

    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.flattenedEvents.isEmpty)

    let connectReports = await pipeline.feedHIDData(Data([7]))
    #expect(dispatcher.batches == [[]])
    #expect(connectReports == [PhysicalHIDOutputReport(reportID: 0, bytes: [0xAA])])

    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a)])
    let shutdownReports = await pipeline.hidShutdownFeatureReports()
    #expect(shutdownReports == [PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB])])

    let disconnectReports = await pipeline.feedHIDData(Data([8]))
    #expect(dispatcher.flattenedEvents == [.buttonPressed(.a), .buttonReleased(.a)])
    #expect(disconnectReports == [PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB])])
    #expect(await pipeline.hidShutdownFeatureReports().isEmpty)
    #expect(dispatcher.stoppedIdentifiers == [DeviceIdentifier(vendorID: 10462, productID: 4418)])
  }

}

private final class ScriptedInputParser: InputParser, @unchecked Sendable {
  func performHandshake(handle: USBDeviceHandle?) async throws {
    await Task.yield()
  }

  func parse(data: Data) throws -> [ControllerEvent] {
    switch data.first {
    case 1:
      return [.buttonPressed(.a)]
    case 2:
      return [.buttonReleased(.a)]
    case 3:
      return [.leftStickChanged(x: 0.8, y: 0)]
    case 4:
      return [.buttonPressed(.b)]
    case 5:
      return [.leftStickChanged(x: 0.6, y: 0)]
    case 6:
      return [.dpadChanged(.north)]
    case 9:
      return [.buttonPressed(.a), .buttonReleased(.a)]
    case 10:
      return [.buttonPressed(.a), .buttonPressed(.a)]
    case 11:
      return [.leftStickChanged(x: .nan, y: .infinity)]
    default:
      return []
    }
  }
}


private final class ScriptedLifecycleInputParser: InputParser, ControllerInputConnectionLifecycle,
  HIDStartupFeatureReportProvider, HIDShutdownFeatureReportProvider, @unchecked Sendable
{
  private var connected = false
  private var pendingState: ControllerInputConnectionState?

  var requiresInputConnectionBeforeOutput: Bool { true }

  func hidStartupFeatureReports() -> [PhysicalHIDOutputReport] {
    [PhysicalHIDOutputReport(reportID: 0, bytes: [0xAA])]
  }

  func hidShutdownFeatureReports() -> [PhysicalHIDOutputReport] {
    [PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB])]
  }

  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let state = pendingState
    pendingState = nil
    return state
  }

  func performHandshake(handle: USBDeviceHandle?) async throws {
    await Task.yield()
  }

  func parse(data: Data) throws -> [ControllerEvent] {
    switch data.first {
    case 7:
      connected = true
      pendingState = .connected
      return []
    case 8:
      connected = false
      pendingState = .disconnected
      return []
    case 1 where connected:
      return [.buttonPressed(.a)]
    default:
      return []
    }
  }
}

private final class RecordingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  private let lock = NSLock()
  private var recordedBatches: [[ControllerEvent]] = []
  private var recordedStops: [DeviceIdentifier] = []

  var batches: [[ControllerEvent]] {
    lock.withLock { recordedBatches }
  }

  var stoppedIdentifiers: [DeviceIdentifier] {
    lock.withLock { recordedStops }
  }

  var dispatchCount: Int {
    lock.withLock { recordedBatches.count }
  }

  var flattenedEvents: [ControllerEvent] {
    lock.withLock { recordedBatches.flatMap { $0 } }
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) {
    lock.withLock {
      recordedBatches.append(events)
    }
  }
}

extension RecordingOutputDispatcher: ControllerLifecycleListener {
  func controllerDidStop(_ identifier: DeviceIdentifier) {
    lock.withLock {
      recordedStops.append(identifier)
    }
  }
}
