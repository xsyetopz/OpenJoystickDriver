import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Pinned pipeline neutralize transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Records what a `DevicePipeline` asks of its dispatcher, in order, and forwards it.
  final class PipelineOutput: OutputDispatcher, ControllerLifecycleListener, @unchecked Sendable {
    let output = VirtualOutput()
    private let lock = NSLock()
    private var calls: [String] = []
    private var previous = ControllerState.neutral

    var suppressOutput: Bool {
      get { output.stateDispatcher.suppressOutput }
      set {
        output.stateDispatcher.suppressOutput = newValue
        output.reportDispatcher.suppressOutput = newValue
      }
    }

    /// Records what the snapshot changed since the previous one.
    func dispatch(
      _ event: ControllerEvent,
      labels: ControllerButtonLabels,
      from identifier: DeviceIdentifier
    ) async {
      let changes = lock.withLock {
        defer { previous = event.state }
        return OutputCharacterizationTests.renderChanges(from: previous, to: event, labels: labels)
      }
      record("  dispatch [\(changes)]")
      await output.dispatch(event, from: identifier)
    }

    func activateOutput(for _: DeviceIdentifier) { record("  activate") }

    func controllerDidStop(_ identifier: DeviceIdentifier) async {
      record("  stop")
      await output.stateDispatcher.controllerDidStop(identifier)
      await output.reportDispatcher.controllerDidStop(identifier)
    }

    /// The calls since the last render, then the output state line and new reports.
    func render(_ label: String) -> [String] {
      let recorded = lock.withLock {
        defer { calls.removeAll() }
        return calls
      }
      return [label] + recorded + output.render("  state")
    }

    private func record(_ call: String) { lock.withLock { calls.append(call) } }
  }

  /// Parses a one-byte report as the index of a scripted change batch.
  final class ScriptedBatches: PhysicalProtocolDriver, @unchecked Sendable {
    let capabilities = ControllerCapabilities(controls: ControlID.xboxLayout)
    let sessionPlan = DriverSessionPlan()
    let outputCapabilities = PhysicalControllerOutputCapabilities.none
    let defaultColor: ControllerColor? = nil
    let batches: [[InputChange]]
    private var script = ScriptedState()

    init(_ batches: [[InputChange]]) { self.batches = batches }

    func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

    /// Applies the batch the report's first byte indexes to the previous snapshot.
    func parse(report data: Data, receivedAt: MonotonicTimestamp) throws -> ControllerEvent? {
      data.first.map { script.event(batches[Int($0)], at: receivedAt) }
    }
  }

  /// The three pipeline neutralize paths over the same held input: each dispatches exactly
  /// `.neutral`, so sub-threshold sticks and triggers are released too; liveness loss then stops
  /// the controller, after the neutralizing dispatch.
  @Test
  func pipelineNeutralizePathsReleaseToExactNeutral() async {
    let held: [InputChange] = [
      .press(.faceWest), .press(.faceSouth), .hat(.north), .leftStick(x: 0.1, y: 0),
      .rightStick(x: 0.5, y: 0), .leftTrigger(0.04), .rightTrigger(0.3),
    ]
    var lines: [String] = []
    for path in ["neutralize", "gate", "liveness"] {
      let dispatcher = PipelineOutput()
      let pipeline = DevicePipeline(
        identifier: Self.standard,
        transport: .hid(locationID: 1),
        driver: ScriptedBatches([held]),
        dispatcher: dispatcher,
        idleTimeoutNanoseconds: 5_000_000_000,
        idleMonitorIntervalNanoseconds: 5_000_000_000
      )
      await pipeline.start()
      _ = await pipeline.feedHIDData(Data([0]))
      lines += dispatcher.render("\(path) held")
      switch path {
      case "neutralize": await pipeline.neutralizeOutput()
      case "gate": await pipeline.setExternalOutputAllowed(false)
      default: await pipeline.retireOutputAfterLivenessLoss()
      }
      lines += dispatcher.render("\(path) after")
      switch path {
      case "neutralize": await pipeline.neutralizeOutput()
      case "gate": await pipeline.setExternalOutputAllowed(false)
      default: await pipeline.retireOutputAfterLivenessLoss()
      }
      lines += dispatcher.render("\(path) again")
      await pipeline.stop()
    }
    #expect(
      lines == [
        "neutralize held",
        "  dispatch [+south +west hat=north ls=3276,0 rs=16383,0 lt=2621 rt=19660]",
        "  state b=0805 h=1 ls=3276,0 rs=16383,0 t=1310,9829 f=00 +1",
        "  out 0504cc0c0000ff3f00001e056526", "neutralize after",
        "  dispatch [-south -west hat=neutral ls=0,0 rs=0,0 lt=0 rt=0]",
        "  state b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "neutralize again", "  state b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0", "gate held",
        "  dispatch [+south +west hat=north ls=3276,0 rs=16383,0 lt=2621 rt=19660]",
        "  state b=0805 h=1 ls=3276,0 rs=16383,0 t=1310,9829 f=00 +1",
        "  out 0504cc0c0000ff3f00001e056526", "gate after",
        "  dispatch [-south -west hat=neutral ls=0,0 rs=0,0 lt=0 rt=0]",
        "  state b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "gate again", "  state b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0", "liveness held",
        "  dispatch [+south +west hat=north ls=3276,0 rs=16383,0 lt=2621 rt=19660]",
        "  state b=0805 h=1 ls=3276,0 rs=16383,0 t=1310,9829 f=00 +1",
        "  out 0504cc0c0000ff3f00001e056526", "liveness after",
        "  dispatch [-south -west hat=neutral ls=0,0 rs=0,0 lt=0 rt=0]", "  stop",
        "  state b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
        "liveness again", "  state b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +0",
      ]
    )
  }

  /// While remapped output is suppressed a pressed state is refused, but a neutral state still
  /// reaches an existing device.
  @Test
  func remappedNeutralWhileSuppressed() async {
    let output = VirtualOutput()
    var lines: [String] = []
    func send(_ label: String, _ state: RemappingGamepadState) async {
      do { try await output.send(state, for: Self.engineDevice) } catch {
        lines.append("\(label) threw \(type(of: error))")
      }
      lines += output.render(label)
    }
    await send("+south", RemappingGamepadState(buttons: [.south], axes: [.leftTrigger: 0.5]))
    await output.stateDispatcher.setRemappingOutputSuppressed(true)
    await output.reportDispatcher.setRemappingOutputSuppressed(true)
    lines += output.render("suppressed")
    await send("+north", RemappingGamepadState(buttons: [.north]))
    await send("neutral", .neutral)
    #expect(
      lines == [
        "+south b=0001 h=0 ls=0,0 rs=0,0 t=16383,0 f=10 +1", "  out 01000000000000000000ff3f0000",
        "suppressed b=0001 h=0 ls=0,0 rs=0,0 t=16383,0 f=10 +0", "+north threw CancellationError",
        "+north b=0001 h=0 ls=0,0 rs=0,0 t=16383,0 f=10 +0",
        "neutral b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1", "  out 0000000000000000000000000000",
      ]
    )
  }
}
