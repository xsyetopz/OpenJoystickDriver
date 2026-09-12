import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingGamepadTests {
  @Test func virtualTransitionsExplicitlyNeutralizeSmallAxesAndHeldControls() {
    let state = RemappingGamepadState(
      buttons: [.south, .touchpad],
      dpad: [.up, .right],
      axes: [.leftStickX: 0.001, .rightStickY: -0.5, .leftTrigger: 0.001, .rightTrigger: 1]
    )
    #expect(
      RemappingGamepadState.neutral.events(since: state) == [
        .buttonReleased(.a), .buttonReleased(.touchpad), .dpadChanged(.neutral),
        .leftStickChanged(x: 0, y: 0), .rightStickChanged(x: 0, y: 0),
        .leftTriggerChanged(0), .rightTriggerChanged(0)
      ]
    )
    #expect(state.events(since: state).isEmpty)
  }

  @Test func virtualTransitionsCoalesceNamingAliasesBeforeReleasingButtons() {
    let both = RemappingGamepadState(buttons: [.start, .options, .share])
    #expect(both.events(since: .neutral) == [.buttonPressed(.share), .buttonPressed(.start)])
    let remaining = RemappingGamepadState(buttons: [.options, .share])
    #expect(remaining.events(since: both).isEmpty)
    #expect(
      RemappingGamepadState.neutral.events(since: remaining)
        == [.buttonReleased(.share), .buttonReleased(.start)]
    )
  }

  @Test func changingOneStickComponentPreservesTheOtherComponent() {
    let previous = RemappingGamepadState(axes: [.leftStickX: 0.5, .leftStickY: -0.5])
    let next = RemappingGamepadState(axes: [.leftStickX: 0.25, .leftStickY: -0.5])
    #expect(next.events(since: previous) == [.leftStickChanged(x: 0.25, y: -0.5)])
  }

  @Test func sharedButtonRemainsHeldUntilEveryBindingReleases() {
    var output = RemappingGamepadAccumulator()
    let first = UUID()
    let second = UUID()
    let held = RemappingGamepadState(buttons: [.south])
    #expect(output.update(held, for: first) == held)
    #expect(output.update(held, for: second) == nil)
    #expect(output.release(first) == nil)
    #expect(output.state.buttons == [.south])
    #expect(output.release(second) == .neutral)
    #expect(output.release(second) == nil)
  }

  @Test func sticksSumBeforeClampingAndTriggersTakeMaximum() {
    var output = RemappingGamepadAccumulator()
    let first = UUID()
    let second = UUID()
    _ = output.update(
      RemappingGamepadState(axes: [.leftStickX: 0.75, .leftTrigger: 0.4]), for: first
    )
    _ = output.update(
      RemappingGamepadState(axes: [.leftStickX: 0.75, .leftTrigger: 0.8]), for: second
    )
    #expect(output.state.value(for: .leftStickX) == 1)
    #expect(output.state.value(for: .leftTrigger) == 0.8)
    _ = output.release(second)
    #expect(output.state.value(for: .leftStickX) == 0.75)
    #expect(output.state.value(for: .leftTrigger) == 0.4)
    _ = output.update(RemappingGamepadState(axes: [.leftStickX: -0.75]), for: second)
    #expect(output.state.value(for: .leftStickX) == 0)
    #expect(output.drain() == .neutral)
    #expect(output.drain() == nil)
  }

  @Test func opposingDpadInputsCancelPerAxisAndRestoreOnRelease() {
    var output = RemappingGamepadAccumulator()
    let first = UUID()
    let second = UUID()
    _ = output.update(RemappingGamepadState(dpad: [.up, .right]), for: first)
    _ = output.update(RemappingGamepadState(dpad: [.down]), for: second)
    #expect(output.state.dpad == [.right])
    _ = output.release(second)
    #expect(output.state.dpad == [.up, .right])
    #expect(output.release(first) == .neutral)
  }

  @Test func invalidNumbersCannotEnterVirtualOutput() {
    let state = RemappingGamepadState(
      axes: [
        .leftStickX: .nan, .leftStickY: .infinity, .rightStickX: -4,
        .rightStickY: 4, .leftTrigger: -1, .rightTrigger: 2
      ]
    )
    #expect(state.value(for: .leftStickX) == 0)
    #expect(state.value(for: .leftStickY) == 0)
    #expect(state.value(for: .rightStickX) == -1)
    #expect(state.value(for: .rightStickY) == 1)
    #expect(state.value(for: .leftTrigger) == 0)
    #expect(state.value(for: .rightTrigger) == 1)
  }
}
