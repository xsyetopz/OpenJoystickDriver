import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Pins what reaches the virtual gamepad, audited line by line across the move from delta
/// events to full state snapshots.
///
/// Each step applies one batch of changes to the controller's previous snapshot and feeds the
/// resulting snapshot (virtual output path), or one engine transition (remapped path), to two
/// `UserSpaceOutputDispatcher`s over test backends: one publishes a
/// `ContinuitySnapshotReportFormat` report, decoded back into the dispatcher's
/// `VirtualGamepadState`, and one publishes the production `OJDGenericGamepadFormat` report.
/// - A step line renders the state after the step: `b=` the XInput-order button bits in hex,
///   `h=` the raw HID hat, sticks and triggers as the raw `Int16` state, and `f=` the digital
///   left-trigger and right-trigger flags; `+n` counts the generic reports the step published,
///   each following on its own `out` line in hex. `+0` is a deduplicated delivery.
/// - Engine actions render in emission order before the state they produce: `sys` for system
///   input, `pad` for a remapped gamepad state (sorted buttons, sorted d-pad, axes quantized to
///   `Int16((v * 32767).rounded())`).
struct OutputCharacterizationTests {}

extension OutputCharacterizationTests {
  static let standard = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, locationID: 1)
  static let playStation = DeviceIdentifier(vendorID: 0x054C, productID: 0x0CE6, locationID: 2)
  static let nintendo = DeviceIdentifier(vendorID: 0x057E, productID: 0x2009, locationID: 3)
  /// The one controller whose sticks use the rescaled 0.02 transfer instead of no dead zone.
  static let rescaled = DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600, locationID: 4)
  static let engineDevice = DeviceIdentifier(vendorID: 1, productID: 2, locationID: 5)

  /// Two dispatchers fed identically: one publishes the state snapshot, one the generic report.
  final class VirtualOutput: @unchecked Sendable {
    let stateBackend = UserSpaceDispatcherTestBackend()
    let reportBackend = UserSpaceDispatcherTestBackend()
    let stateDispatcher: UserSpaceOutputDispatcher
    let reportDispatcher: UserSpaceOutputDispatcher
    private let lock = NSLock()
    private var reported = 0
    private var inputs: [DeviceIdentifier: ControllerState] = [:]

    init() {
      stateDispatcher = UserSpaceOutputDispatcher(
        testBackendFactory: { [stateBackend] _ in stateBackend },
        format: ContinuitySnapshotReportFormat()
      )
      reportDispatcher = UserSpaceOutputDispatcher(
        testBackendFactory: { [reportBackend] _ in reportBackend },
        format: OJDGenericGamepadFormat()
      )
    }

    /// Applies `changes` to the identifier's previous snapshot and dispatches the result under
    /// the family labels of its test device.
    func dispatch(
      _ changes: [InputChange],
      from identifier: DeviceIdentifier,
      labels: ControllerButtonLabels? = nil
    ) async {
      let event = lock.withLock {
        let event = ControllerEvent(changes, after: inputs[identifier] ?? .neutral)
        inputs[identifier] = event.state
        return event
      }
      let labels = labels ?? OutputCharacterizationTests.labels(for: identifier)
      await stateDispatcher.dispatch(event, labels: labels, from: identifier)
      await reportDispatcher.dispatch(event, labels: labels, from: identifier)
    }

    /// Dispatches `event` as it stands, as a pipeline does.
    func dispatch(_ event: ControllerEvent, from identifier: DeviceIdentifier) async {
      lock.withLock { inputs[identifier] = event.state }
      let labels = OutputCharacterizationTests.labels(for: identifier)
      await stateDispatcher.dispatch(event, labels: labels, from: identifier)
      await reportDispatcher.dispatch(event, labels: labels, from: identifier)
    }

    func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
      try await stateDispatcher.send(state, for: identifier)
      try await reportDispatcher.send(state, for: identifier)
    }

    /// The state line after a step, then each generic report published since the last render.
    func render(_ label: String) -> [String] {
      let reports = reportBackend.publishedReports()
      let fresh = lock.withLock {
        defer { reported = reports.count }
        return reports.dropFirst(reported)
      }
      let state = stateBackend.publishedReports().last.map(Self.renderState) ?? "b=none"
      return ["\(label) \(state) +\(fresh.count)"] + fresh.map { "  out \(Self.hex($0))" }
    }

    static func renderState(_ report: [UInt8]) -> String {
      func word(_ offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(report[offset]) | UInt16(report[offset + 1]) << 8)
      }
      let buttons =
        UInt32(report[0]) | UInt32(report[1]) << 8 | UInt32(report[2]) << 16 | UInt32(report[3])
        << 24
      let flags = report[16...17].map(String.init).joined()
      return "b=\(String(format: "%04x", buttons)) h=\(report[18])"
        + " ls=\(word(4)),\(word(6)) rs=\(word(8)),\(word(10)) t=\(word(12)),\(word(14)) f=\(flags)"
    }

    static func hex(_ bytes: [UInt8]) -> String {
      bytes.map { String(format: "%02x", $0) }.joined()
    }
  }

  /// Records engine actions in emission order and forwards gamepad states to a virtual output.
  final class EngineRecorder: RemappingSystemInputSink, RemappingGamepadSink, @unchecked Sendable {
    let output = VirtualOutput()
    private let lock = NSLock()
    private var recorded: [String] = []

    func send(_ action: RemappingSystemInputAction) {
      append(["  sys \(OutputCharacterizationTests.render(action))"])
    }

    func send(_ state: RemappingGamepadState, for identifier: DeviceIdentifier) async throws {
      append(["  pad \(OutputCharacterizationTests.render(state))"])
      try await output.send(state, for: identifier)
      append(output.render("   "))
    }

    /// The step label, then everything the step emitted.
    func take(_ label: String) -> [String] {
      lock.withLock {
        defer { recorded.removeAll() }
        return [label] + recorded
      }
    }

    private func append(_ lines: [String]) { lock.withLock { recorded += lines } }
  }

  /// One engine over one recorder, stepping one profile through labelled event batches.
  struct EngineSession {
    let recorder = EngineRecorder()
    let engine: RemappingEventEngine
    let profile: RemappingProfile
    let device: DeviceIdentifier

    init(_ profile: RemappingProfile, device: DeviceIdentifier = engineDevice) {
      self.profile = profile
      self.device = device
      engine = RemappingEventEngine(sink: recorder, gamepadSink: recorder)
    }

    func step(
      _ label: String,
      _ events: [InputChange],
      at time: UInt64 = 0
    ) async throws -> [String] {
      // One step is one report: the whole batch lands in one snapshot.
      try await engine.process(
        InputScript.of(engine).event(events, for: device),
        labels: OutputCharacterizationTests.labels(for: device),
        from: device,
        using: profile,
        at: time
      )
      return recorder.take(label)
    }

    /// Processes one parsed snapshot as the router forwards it.
    func step(_ label: String, event: ControllerEvent) async throws -> [String] {
      try await engine.process(
        event,
        labels: OutputCharacterizationTests.labels(for: device),
        from: device,
        using: profile,
        at: 0
      )
      return recorder.take(label)
    }

    func tick(_ label: String, at time: UInt64) async throws -> [String] {
      try await engine.tick(at: time)
      return recorder.take(label)
    }
  }

  /// The family labels the pipeline binds for each test device.
  static func labels(for identifier: DeviceIdentifier) -> ControllerButtonLabels {
    switch identifier {
    case playStation: .playStation
    case nintendo: .nintendo
    default: .standard
    }
  }

  /// What `event` changed since `previous`, in the order the engine applies it: `+`/`-` and the
  /// remapping button under `labels`, `hat=`, sticks as raw values with Y rendered down-positive
  /// (the canonical Y negated) and triggers as raw values, then `motion` and `touch` per sample.
  static func renderChanges(
    from previous: ControllerState,
    to event: ControllerEvent,
    labels: ControllerButtonLabels
  ) -> String {
    let state = event.state
    var parts: [String] = []
    for change in RemappingEngineState.changes(from: previous, to: state, labels: labels) {
      switch change {
      case .button(let button, let isPressed):
        parts.append((isPressed ? "+" : "-") + button.rawValue)
      case .dpad(let hat): parts.append("hat=\(hat.rawValue)")
      case .leftStick:
        parts.append("ls=\(state.leftStick.x.rawValue),\(-state.leftStick.y.rawValue)")
      case .rightStick:
        parts.append("rs=\(state.rightStick.x.rawValue),\(-state.rightStick.y.rawValue)")
      case .leftTrigger: parts.append("lt=\(state.leftTrigger.rawValue)")
      case .rightTrigger: parts.append("rt=\(state.rightTrigger.rawValue)")
      case .motion, .touch: break
      }
    }
    parts += event.motion.map { _ in "motion" } + event.touchFrames.map { _ in "touch" }
    return parts.joined(separator: " ")
  }

  static func render(_ state: RemappingGamepadState) -> String {
    let buttons = state.buttons.map(\.rawValue).sorted().joined(separator: ",")
    let dpad = state.dpad.map(\.rawValue).sorted().joined(separator: ",")
    let axes = state.axes.sorted { $0.key.rawValue < $1.key.rawValue }.map {
      "\($0.key.rawValue)=\(Int16(($0.value * 32767).rounded()))"
    }
    return "[\(buttons)] d=[\(dpad)] a=[\(axes.joined(separator: ","))]"
  }

  static func render(_ action: RemappingSystemInputAction) -> String {
    switch action {
    case .modifierDown(let modifier): "modifier-down \(modifier.rawValue)"
    case .modifierUp(let modifier): "modifier-up \(modifier.rawValue)"
    case .keyDown(let key): "key-down \(key.rawValue)"
    case .keyUp(let key): "key-up \(key.rawValue)"
    case .mouseButtonDown(let button): "mouse-down \(button.rawValue)"
    case .mouseButtonUp(let button): "mouse-up \(button.rawValue)"
    case .mouseMoved(let axis, let amount): "mouse-moved \(axis.rawValue) \(amount)"
    case .pointerDelta(let x, let y): "pointer \(x),\(y)"
    case .scrolled(let axis, let amount): "scrolled \(axis.rawValue) \(amount)"
    case .scrollDelta(let x, let y): "scroll \(x),\(y)"
    }
  }

  static func profile(
    _ virtualGamepad: RemappingVirtualGamepadPolicy,
    bindings: [RemappingBinding] = [],
    chords: [RemappingChord] = [],
    sequences: [RemappingSequence] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Output pins",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: virtualGamepad),
      bindings: bindings,
      chords: chords,
      sequences: sequences
    )
  }

  static func key(
    _ key: RemappingKeyboardKey,
    _ modifiers: Set<RemappingKeyModifier> = []
  ) -> RemappingDestination { .keyboard(key: key, modifiers: modifiers) }
}
