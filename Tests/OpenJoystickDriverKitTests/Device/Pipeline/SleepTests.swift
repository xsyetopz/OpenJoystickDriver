import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct DevicePipelineSleepTests {
  /// The analog-only scripted trigger also gets its normalization-derived trigger button.
  @Test(arguments: [
    (UInt8(3), [InputChange.leftStick(x: 0.8, y: 0)]), (UInt8(4), [.press(.east)]),
    (UInt8(6), [.hat(.north)]), (UInt8(7), [.leftTrigger(0.75), .press(.leftTrigger)]),
  ])
  func testIdlePipelineForwardsFirstWakeInput(code: UInt8, expected: [InputChange]) async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000,
      idleMonitorIntervalNanoseconds: 10_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([2]))

    await waitUntil("the idle pipeline neutralizes") { dispatcher.states.last == .neutral }

    await pipeline.feedHIDData(Data([code]))

    #expect(
      dispatcher.states == [
        snapshot(.press(.south)), .neutral, ControllerState.neutral.applying(expected),
      ]
    )
  }

  @Test
  func testForegroundGateNeutralizesOutputAndWaitsForNeutralBeforeResuming() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.states == [snapshot(.press(.south))])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.states == [snapshot(.press(.south)), .neutral])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([2]))
    #expect(dispatcher.states == [snapshot(.press(.south)), .neutral])

    await pipeline.feedHIDData(Data([4]))
    #expect(
      dispatcher.states == [snapshot(.press(.south)), .neutral, snapshot(.press(.east))]
    )
  }

  @Test
  func testForegroundGateRearmsAfterFirstPostFocusChangeWithoutFullNeutral() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([3]))
    #expect(dispatcher.states == [snapshot(.leftStick(x: 0.8, y: 0))])

    await pipeline.setExternalOutputAllowed(false)
    #expect(dispatcher.states == [snapshot(.leftStick(x: 0.8, y: 0)), .neutral])

    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([5]))
    #expect(dispatcher.states == [snapshot(.leftStick(x: 0.8, y: 0)), .neutral])

    await pipeline.feedHIDData(Data([4]))
    // The stick held across the gate stays hidden until it changes.
    #expect(
      dispatcher.states == [
        snapshot(.leftStick(x: 0.8, y: 0)), .neutral, snapshot(.press(.east)),
      ]
    )
  }

  @Test
  func testRepeatedAllowedSignalDoesNotRearmForegroundGate() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([4]))

    #expect(dispatcher.states == [snapshot(.press(.east))])
  }

  @Test
  func testPipelineSkipsSnapshotsThatDoNotChangeDispatchedState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([9]))
    await pipeline.feedHIDData(Data([11]))
    #expect(dispatcher.states.isEmpty)

    await pipeline.feedHIDData(Data([1]))
    await pipeline.feedHIDData(Data([10]))
    #expect(dispatcher.states == [snapshot(.press(.south))])
  }

  @Test
  func testStopNeutralizesForwardedButtonState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([1]))
    await pipeline.stop()
    await waitUntil("the stop neutralizes") { dispatcher.states.last == .neutral }

    #expect(dispatcher.states == [snapshot(.press(.south)), .neutral])
  }

  @Test
  func testStopNeutralizesForwardedDpadAndAxesState() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 100, productID: 200),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([6]))
    await pipeline.feedHIDData(Data([3]))
    await pipeline.stop()
    await waitUntil("the stop neutralizes") { dispatcher.states.last == .neutral }

    #expect(
      dispatcher.states == [
        snapshot(.hat(.north)), snapshot(.hat(.north), .leftStick(x: 0.8, y: 0)), .neutral,
      ]
    )
  }

  @Test
  func testReconnectDoesNotKeepForegroundMaskFromEndedConnection() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 10462, productID: 4418),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedLifecycleInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    await pipeline.feedHIDData(Data([7]))
    await pipeline.feedHIDData(Data([1]))
    // Lifting the gate with South held masks it until it changes.
    await pipeline.setExternalOutputAllowed(false)
    await pipeline.setExternalOutputAllowed(true)
    await pipeline.feedHIDData(Data([8]))
    await pipeline.feedHIDData(Data([7]))
    await pipeline.feedHIDData(Data([1]))

    // The reconnected controller's first press is visible; the old connection's mask is gone.
    #expect(dispatcher.states.last == snapshot(.press(.south)))
    await pipeline.stop()
  }

  @Test
  func testInputConnectionLifecycleDefersAndStopsOutput() async {
    let dispatcher = RecordingOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 10462, productID: 4418),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: ScriptedLifecycleInputParser(),
      dispatcher: dispatcher,
      idleTimeoutNanoseconds: 5_000_000_000,
      idleMonitorIntervalNanoseconds: 5_000_000_000
    )

    await pipeline.start()
    #expect(await pipeline.hidDeactivationWrites().isEmpty)

    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.states.isEmpty)

    let connectReports = await pipeline.feedHIDData(Data([7]))
    #expect(dispatcher.activations == 1 && dispatcher.states.isEmpty)
    #expect(connectReports == [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xAA]))])

    await pipeline.feedHIDData(Data([1]))
    #expect(dispatcher.states == [snapshot(.press(.south))])
    let shutdownReports = await pipeline.hidDeactivationWrites()
    #expect(shutdownReports == [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB]))])

    let disconnectReports = await pipeline.feedHIDData(Data([8]))
    #expect(dispatcher.states == [snapshot(.press(.south)), .neutral])
    #expect(disconnectReports == [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB]))])
    #expect(await pipeline.hidDeactivationWrites().isEmpty)
    #expect(
      dispatcher.stoppedIdentifiers == [LogicalControllerID(vendorID: 10462, productID: 4418)]
    )
  }

}

private final class ScriptedInputParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan()
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  private var script = ScriptedState()
  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }
  func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    let changes: [InputChange]
    switch data.first {
    case 1: changes = [.press(.south)]
    case 2: changes = [.release(.south)]
    case 3: changes = [.leftStick(x: 0.8, y: 0)]
    case 4: changes = [.press(.east)]
    case 5: changes = [.leftStick(x: 0.6, y: 0)]
    case 6: changes = [.hat(.north)]
    case 7: changes = [.leftTrigger(0.75)]
    case 9: changes = [.press(.south), .release(.south)]
    case 10: changes = [.press(.south), .press(.south)]
    case 11: changes = [.leftStick(x: .nan, y: .infinity)]
    default: return nil
    }
    return script.event(changes, at: receivedAt)
  }
}

private final class ScriptedLifecycleInputParser: PhysicalProtocolDriver {
  let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
  let sessionPlan = DriverSessionPlan(requiresInputConnectionBeforeOutput: true)
  let outputCapabilities = PhysicalControllerOutputCapabilities.none
  let defaultColor: ControllerColor? = nil
  private var connected = false
  private var pendingState: ControllerInputConnectionState?
  private var script = ScriptedState()

  func activationWrites() -> [PhysicalOutputWrite] {
    [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xAA]))]
  }

  func deactivationWrites() -> [PhysicalOutputWrite] {
    [.hidFeature(PhysicalHIDOutputReport(reportID: 0, bytes: [0xBB]))]
  }

  func inputConnectionWrites(for state: ControllerInputConnectionState) -> [PhysicalOutputWrite] {
    state == .connected ? activationWrites() : deactivationWrites()
  }

  func consumeInputConnectionStateChange() -> ControllerInputConnectionState? {
    let state = pendingState
    pendingState = nil
    return state
  }

  func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
    switch data.first {
    case 7:
      connected = true
      pendingState = .connected
      return nil
    case 8:
      connected = false
      pendingState = .disconnected
      script = ScriptedState()
      return nil
    case 1 where connected: return script.event([.press(.south)], at: receivedAt)
    default: return nil
    }
  }
}

private final class RecordingOutputDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  private let lock = NSLock()
  private var recordedStates: [ControllerState] = []
  private var recordedActivations = 0
  private var recordedStops: [LogicalControllerID] = []

  var states: [ControllerState] { lock.withLock { recordedStates } }
  var activations: Int { lock.withLock { recordedActivations } }
  var stoppedIdentifiers: [LogicalControllerID] { lock.withLock { recordedStops } }

  func dispatch(
    _ event: ControllerEvent,
    from _: LogicalControllerID
  ) { lock.withLock { recordedStates.append(event.state) } }

  func activateOutput(for _: LogicalControllerID) { lock.withLock { recordedActivations += 1 } }
}

extension RecordingOutputDispatcher: ControllerLifecycleListener {
  func controllerDidStop(_ identifier: LogicalControllerID) {
    lock.withLock { recordedStops.append(identifier) }
  }
}
