import Testing

@testable import OpenJoystickDriverKit

// Pinned neutralize transcripts; the rendering rules are on `OutputCharacterizationTests`.
extension OutputCharacterizationTests {
  /// Neutralizing dispatches exactly `.neutral`: every control, stick and trigger is released,
  /// including sub-threshold ones, under both the default and the rescaled transfer. A second
  /// neutralize changes nothing.
  @Test
  func neutralizeReleasesSubThresholdInput() async {
    let held: [InputChange] = [
      .press(.faceWest), .press(.faceSouth), .press(.leftShoulder), .hat(.northEast),
      .leftStick(x: 0.1, y: -0.12), .rightStick(x: 0.5, y: 0), .leftTrigger(0.04),
      .rightTrigger(0.3),
    ]
    var lines: [String] = []
    for (name, identifier) in [("std", Self.standard), ("11c1", Self.rescaled)] {
      let input = ControllerState.neutral.applying(held)
      let output = VirtualOutput()
      await output.dispatch(held, from: identifier)
      lines += output.render("\(name) held")
      let neutralized = ControllerState.neutral
      let event = ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: neutralized)
      lines.append("  events \(Self.renderChanges(from: input, to: event, labels: .standard))")
      await output.dispatch(event, from: identifier)
      lines += output.render("\(name) neutralized")
      lines.append(
        "\(name) residual [\(neutralized.pressed.map(\.rawValue).sorted().joined(separator: ","))]"
          + " ls=\(neutralized.leftStick.x.rawValue),\(-neutralized.leftStick.y.rawValue)"
          + " rs=\(neutralized.rightStick.x.rawValue),\(-neutralized.rightStick.y.rawValue)"
          + " t=\(neutralized.leftTrigger.rawValue),\(neutralized.rightTrigger.rawValue)"
          + " neutral=\(neutralized == .neutral)"
      )
      let again = ControllerEvent(timestamp: MonotonicTimestamp(nanoseconds: 0), state: .neutral)
      lines.append(
        "\(name) again [\(Self.renderChanges(from: neutralized, to: again, labels: .standard))]"
      )
    }
    #expect(
      lines == [
        "std held b=4815 h=2 ls=3276,-3932 rs=16383,0 t=1310,9829 f=00 +1",
        "  out 1524cc0ca4f0ff3f00001e056526",
        "  events -south -west -left_shoulder hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "std neutralized b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "std residual [] ls=0,0 rs=0,0 t=0,0 neutral=true",
        "std again []", "11c1 held b=4815 h=2 ls=2674,-3343 rs=16048,0 t=1310,9829 f=00 +1",
        "  out 1524720af1f2b03e00001e056526",
        "  events -south -west -left_shoulder hat=neutral ls=0,0 rs=0,0 lt=0 rt=0",
        "11c1 neutralized b=0000 h=0 ls=0,0 rs=0,0 t=0,0 f=00 +1",
        "  out 0000000000000000000000000000", "11c1 residual [] ls=0,0 rs=0,0 t=0,0 neutral=true",
        "11c1 again []",
      ]
    )
  }

  /// A neutral remapped state before any output exists creates no virtual device.
  @Test
  func neutralRemappedStateBeforeOutputCreatesNothing() async throws {
    let output = VirtualOutput()
    try await output.send(.neutral, for: Self.engineDevice)
    #expect(output.render("neutral") == ["neutral b=none +0"])
  }
}
