import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingGamepadTests {
  @Test
  func remappedStateReplacesEveryInputFieldOfVirtualState() {
    var virtual = VirtualGamepadState()
    VirtualGamepadReportMapping.apply(
      RemappingGamepadState(
        buttons: [.south, .touchpadClick],
        dpad: [.up, .right],
        axes: [.leftStickX: 0.001, .rightStickY: -0.5, .leftTrigger: 0.001, .rightTrigger: 1]
      ),
      to: &virtual
    )
    #expect(virtual.buttons == 1 | GamepadHIDDescriptor.dpadButtonBits(for: .northEast))
    #expect(virtual.hat == .northEast)
    #expect(virtual.leftStickX == 32 && virtual.rightStickY == -16383)
    #expect(virtual.leftTrigger == 32 && virtual.rightTrigger == 32767)
    VirtualGamepadReportMapping.apply(.neutral, to: &virtual)
    #expect(virtual.buttons == 0 && virtual.hat == .neutral)
    #expect(virtual.leftStickX == 0 && virtual.rightStickY == 0)
    #expect(virtual.leftTrigger == 0 && virtual.rightTrigger == 0)
  }

  @Test
  func startBackAndCaptureEachHaveTheirOwnBit() {
    var virtual = VirtualGamepadState()
    VirtualGamepadReportMapping.apply(
      RemappingGamepadState(buttons: [.start, .back, .capture]),
      to: &virtual
    )
    #expect(virtual.buttons == 1 << 8 | 1 << 9 | 1 << 15)
  }

  @Test
  func sharedButtonRemainsHeldUntilEveryBindingReleases() {
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

  @Test
  func sticksSumBeforeClampingAndTriggersTakeMaximum() {
    var output = RemappingGamepadAccumulator()
    let first = UUID()
    let second = UUID()
    _ = output.update(
      RemappingGamepadState(axes: [.leftStickX: 0.75, .leftTrigger: 0.4]),
      for: first
    )
    _ = output.update(
      RemappingGamepadState(axes: [.leftStickX: 0.75, .leftTrigger: 0.8]),
      for: second
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

  @Test
  func opposingDpadInputsCancelPerAxisAndRestoreOnRelease() {
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

  @Test
  func invalidNumbersCannotEnterVirtualOutput() {
    let state = RemappingGamepadState(axes: [
      .leftStickX: .nan, .leftStickY: .infinity, .rightStickX: -4, .rightStickY: 4,
      .leftTrigger: -1, .rightTrigger: 2,
    ])
    #expect(state.value(for: .leftStickX) == 0)
    #expect(state.value(for: .leftStickY) == 0)
    #expect(state.value(for: .rightStickX) == -1)
    #expect(state.value(for: .rightStickY) == 1)
    #expect(state.value(for: .leftTrigger) == 0)
    #expect(state.value(for: .rightTrigger) == 1)
  }
}
