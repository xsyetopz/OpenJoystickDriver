import Foundation
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

/// Pins how a Joy-Con pair routes both halves into one engine device today.
///
/// Each step sets one half's full button mask and stick in a full-mode `0x30` report, parses it
/// with that half's catalog driver, and dispatches the parsed events from that half. The step line
/// names the half, the mask and stick, then the parsed events; each routed trace follows on its own
/// line. A remapped state renders as its change from the previous one: `+`/`-` sorted buttons, then
/// d-pad directions, then each changed axis quantized to `Int16((v * 32767).rounded())`, so a
/// release of a held control shows as a `-` entry.
struct JoyConPairCharacterizationTests {
  static let left = LogicalControllerID(vendorID: 0x057E, productID: 0x2006, locationID: 31)
  static let right = LogicalControllerID(vendorID: 0x057E, productID: 0x2007, locationID: 32)

  /// Left-half bits: SL `0x200000`, SR `0x100000`, L `0x400000`, ZL `0x800000`, Minus `0x100`,
  /// stick click `0x800`, Capture `0x2000`, d-pad `0xf0000` (up `0x20000`).
  ///
  /// Right-half bits: A `0x4`, B `0x8`, X `0x1`, Y `0x2`, R `0x40`, ZR `0x80`, Plus `0x200`, Home
  /// `0x1000`.
  struct Step {
    let half: LogicalControllerID
    let buttons: UInt32
    let stick: (x: UInt16, y: UInt16)

    init(
      _ half: LogicalControllerID,
      _ buttons: UInt32,
      stick: (x: UInt16, y: UInt16) = (2048, 2048)
    ) {
      self.half = half
      self.buttons = buttons
      self.stick = stick
    }
  }

  final class Session {
    let harness: RemappingRouterHarness
    let drivers: [LogicalControllerID: Switch1Driver] = [
      JoyConPairCharacterizationTests.left: Switch1Driver(layout: .leftJoyCon),
      JoyConPairCharacterizationTests.right: Switch1Driver(layout: .rightJoyCon),
    ]
    private var previous = RemappingGamepadState.neutral
    private var parsed: [LogicalControllerID: ControllerState] = [:]

    init(harness: RemappingRouterHarness) { self.harness = harness }

    func run(_ steps: [Step]) async throws -> [String] {
      var lines: [String] = []
      for step in steps {
        var report = [UInt8](repeating: 0, count: 12)
        report[0] = 0x30
        for index in 0..<3 {
          report[3 + index] = UInt8(truncatingIfNeeded: step.buttons >> (8 * index))
        }
        let offset = step.half == JoyConPairCharacterizationTests.left ? 6 : 9
        report[offset] = UInt8(truncatingIfNeeded: step.stick.x)
        report[offset + 1] =
          UInt8(step.stick.x >> 8 & 0x0F) | UInt8(truncatingIfNeeded: step.stick.y << 4)
        report[offset + 2] = UInt8(truncatingIfNeeded: step.stick.y >> 4)
        let event = try drivers[step.half]?.parse(
          report: Data(report),
          receivedAt: MonotonicTimestamp(nanoseconds: 0)
        )
        let side = step.half == JoyConPairCharacterizationTests.left ? "L" : "R"
        let changes = event.map {
          JoyConPairCharacterizationTests.render(from: parsed[step.half] ?? .neutral, to: $0)
        }
        parsed[step.half] = event?.state ?? parsed[step.half]
        lines.append(
          "\(side) \(String(step.buttons, radix: 16)) \(step.stick.x),\(step.stick.y)"
            + " [\(changes ?? "")]"
        )
        harness.recorder.removeAll()
        if let event {
          try await harness.router.dispatchCausally(.input(event), from: step.half)
        }
        lines += traces()
      }
      return lines
    }

    /// Every trace recorded since the last call, remapped states rendered as changes.
    func traces() -> [String] {
      harness.recorder.snapshot().map { trace in
        guard case .gamepad(let state, let identifier) = trace else {
          return "  \(JoyConPairCharacterizationTests.render(trace))"
        }
        defer { previous = state }
        return "  pad \(JoyConPairCharacterizationTests.side(identifier))"
          + " \(JoyConPairCharacterizationTests.change(from: previous, to: state))"
      }
    }
  }

  /// Pairs both halves under a passthrough profile, so every held control is visible; the default
  /// binding maps left SL to L.
  func pairedSession(
    bindings: [RemappingBinding] = [
      RemappingBinding(source: .button(.auxiliary3), destination: .gamepadButton(.leftShoulder))
    ]
  ) async throws -> Session {
    let profile = RemappingProfile(
      name: "Joy-Con pair pins",
      device: RemappingDeviceScope(vendorID: 0x057E, productID: 0x2006),
      applicationScope: .global,
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .exclusive),
      joyConPair: RemappingJoyConPairSettings(gyroSelection: .disabled),
      bindings: bindings
    )
    let harness = try await RemappingRouterHarness.make()
    try await harness.library.create(profile)
    for member in [Self.left, Self.right] {
      await harness.router.controllerInputOwnershipChanged(.exclusive, for: member)
      try await harness.router.dispatchCausally(.activation, from: member)
    }
    _ = try await harness.router.pairJoyCons(
      left: Self.left,
      right: Self.right,
      profile: profile
    )
    harness.recorder.removeAll()
    return Session(harness: harness)
  }

  /// What one parsed half changed, as the engine applies it: `+`/`-` and the remapping button
  /// `hat=`, and sticks as raw values with Y rendered down-positive, then
  /// samples.
  static func render(from previous: ControllerState, to event: ControllerEvent) -> String {
    let state = event.state
    var parts = RemappingEngineState.changes(from: previous, to: state).map {
      change -> String in
      switch change {
      case .button(let button, let isPressed): (isPressed ? "+" : "-") + button.rawValue
      case .dpad(let hat): "hat=\(hat.rawValue)"
      case .leftStick: "ls=\(state.leftStick.x.rawValue),\(state.leftStick.y.rawValue)"
      case .rightStick: "rs=\(state.rightStick.x.rawValue),\(state.rightStick.y.rawValue)"
      case .leftTrigger: "lt=\(state.leftTrigger.rawValue)"
      case .rightTrigger: "rt=\(state.rightTrigger.rawValue)"
      case .motion: "motion"
      case .touch: "touch"
      }
    }
    parts += event.motion.map { _ in "motion" } + event.touchFrames.map { _ in "touch" }
    return parts.joined(separator: " ")
  }

  static func side(_ identifier: LogicalControllerID) -> String { identifier == left ? "L" : "R" }

  static func render(_ trace: RemappingRouterTrace) -> String {
    switch trace {
    case .virtualGamepad(let state, let identifier):
      let held = render(from: .neutral, to: ControllerEvent([], after: state))
      return "virtual \(side(identifier)) [\(held.isEmpty ? "neutral" : held)]"
    case .virtualOutputActivation(let identifier): return "virtual-activate \(side(identifier))"
    case .virtualOutputStop(let identifier): return "virtual-stop \(side(identifier))"
    case .system(let action): return "system \(action)"
    case .gamepad(let state, let identifier):
      return "pad \(side(identifier)) \(change(from: .neutral, to: state))"
    }
  }

  static func change(
    from previous: RemappingGamepadState,
    to state: RemappingGamepadState
  ) -> String {
    func changes<Value: RawRepresentable<String>>(
      _ previous: Set<Value>,
      _ next: Set<Value>
    ) -> [String] {
      previous.subtracting(next).map { "-\($0.rawValue)" }.sorted()
        + next.subtracting(previous).map { "+\($0.rawValue)" }.sorted()
    }
    let axes = RemappingAxis.allCases.filter { previous.value(for: $0) != state.value(for: $0) }.map
    { "\($0.rawValue)=\(Int16((state.value(for: $0) * 32767).rounded()))" }
    let parts =
      changes(previous.buttons, state.buttons) + changes(previous.dpad, state.dpad).map { "d\($0)" }
      + axes
    return parts.isEmpty ? "=" : parts.joined(separator: " ")
  }
}
