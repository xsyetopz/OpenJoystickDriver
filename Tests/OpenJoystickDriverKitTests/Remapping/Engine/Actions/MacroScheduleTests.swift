import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MacroScheduleTests {
  private let ms: UInt64 = 1_000_000
  private let identifier = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)

  private func tap(_ key: RemappingKeyboardKey) -> RemappingMacroStep {
    .tap(.keyboard(key: key, modifiers: []))
  }

  private func key(_ key: RemappingKeyboardKey) -> RemappingDestination {
    .keyboard(key: key, modifiers: [])
  }

  @Test
  func stepsRunInOrderAndWaitsHoldBackTheNextStep() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(name: "M", steps: [tap(.a), .wait(durationMs: 100), tap(.b)])
    )
    #expect(press(&state, profile, at: 0) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
    #expect(state.tick(at: 99 * ms).isEmpty)
    #expect(state.nextScheduledTick(after: 50 * ms, continuousIntervalNanoseconds: 1) == 100 * ms)
    #expect(state.tick(at: 100 * ms) == [.system(.keyDown(.b)), .system(.keyUp(.b))])
    #expect(state.tick(at: 5_000 * ms).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func chordPressesInOrderHoldsAndReleasesInReverse() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [.chord(destinations: [key(.a), key(.b), key(.c)], holdMs: 50), tap(.d)]
      )
    )
    #expect(
      press(&state, profile, at: 0)
        == [.system(.keyDown(.a)), .system(.keyDown(.b)), .system(.keyDown(.c))]
    )
    #expect(state.tick(at: 49 * ms).isEmpty)
    #expect(
      state.tick(at: 50 * ms)
        == [
          .system(.keyUp(.c)), .system(.keyUp(.b)), .system(.keyUp(.a)), .system(.keyDown(.d)),
          .system(.keyUp(.d)),
        ]
    )
  }

  @Test
  func countedRepeatRunsTheStepListThatManyTimes() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(name: "M", steps: [tap(.a), .wait(durationMs: 10)], repeatMode: .count(3))
    )
    var actions = press(&state, profile, at: 0)
    for time in [10, 20, 30, 40, 1_000] { actions += state.tick(at: UInt64(time) * ms) }
    #expect(
      actions
        == Array(repeating: [.system(.keyDown(.a)), .system(.keyUp(.a))], count: 3).flatMap { $0 }
    )
    #expect(state.heldOutputs.isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func passesStartAtLeastOneMillisecondApart() {
    var state = RemappingEngineState()
    let profile = profile(RemappingMacro(name: "M", steps: [tap(.a)], repeatMode: .count(3)))
    #expect(press(&state, profile, at: 0).count == 2)
    #expect(state.tick(at: 0).isEmpty)
    #expect(state.nextScheduledTick(after: 0, continuousIntervalNanoseconds: 1) == ms)
    #expect(state.tick(at: ms).count == 2)
    #expect(state.tick(at: 2 * ms).count == 2)
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func whileHeldRepeatsUntilReleaseThenEndsTheRunningPass() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [tap(.a), .wait(durationMs: 10)],
        repeatMode: .whileHeld
      )
    )
    _ = press(&state, profile, at: 0)
    #expect(state.tick(at: 10 * ms).count == 2)
    #expect(state.tick(at: 20 * ms).count == 2)
    #expect(release(&state, profile, at: 25 * ms).isEmpty)
    #expect(state.tick(at: 30 * ms).isEmpty)
    #expect(state.tick(at: 1_000 * ms).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func ignoreKeepsTheRunningPass() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [tap(.a), .wait(durationMs: 100), tap(.b)],
        whileRunning: .ignore
      )
    )
    _ = press(&state, profile, at: 0)
    _ = release(&state, profile, at: 10 * ms)
    #expect(press(&state, profile, at: 20 * ms).isEmpty)
    #expect(state.tick(at: 100 * ms) == [.system(.keyDown(.b)), .system(.keyUp(.b))])
    #expect(state.tick(at: 1_000 * ms).isEmpty)
  }

  @Test
  func restartReleasesTheRunningPassAndStartsANewOne() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [.chord(destinations: [key(.a)], holdMs: 100), tap(.b)],
        whileRunning: .restart
      )
    )
    #expect(press(&state, profile, at: 0) == [.system(.keyDown(.a))])
    _ = release(&state, profile, at: 10 * ms)
    #expect(press(&state, profile, at: 20 * ms) == [.system(.keyUp(.a)), .system(.keyDown(.a))])
    #expect(state.tick(at: 119 * ms).isEmpty)
    #expect(
      state.tick(at: 120 * ms)
        == [.system(.keyUp(.a)), .system(.keyDown(.b)), .system(.keyUp(.b))]
    )
  }

  @Test
  func interruptOnReleaseStopsAndNoLaterStepRuns() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [.chord(destinations: [key(.a)], holdMs: 100), tap(.b)],
        interruptOnRelease: true
      )
    )
    _ = press(&state, profile, at: 0)
    #expect(release(&state, profile, at: 10 * ms) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 1_000 * ms).isEmpty)
    #expect(!state.hasScheduledOutput)
  }

  @Test
  func withoutInterruptTheMacroOutlivesTheSource() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(name: "M", steps: [.chord(destinations: [key(.a)], holdMs: 100), tap(.b)])
    )
    _ = press(&state, profile, at: 0)
    #expect(release(&state, profile, at: 10 * ms).isEmpty)
    #expect(
      state.tick(at: 100 * ms)
        == [.system(.keyUp(.a)), .system(.keyDown(.b)), .system(.keyUp(.b))]
    )
  }

  @Test
  func pressStepIsReleasedByReleaseStepOrAtTheEndOfThePass() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [
          .press(key(.a)), .press(key(.b)), .wait(durationMs: 10), .release(key(.a)),
          .wait(durationMs: 10),
        ]
      )
    )
    #expect(press(&state, profile, at: 0) == [.system(.keyDown(.a)), .system(.keyDown(.b))])
    #expect(state.tick(at: 10 * ms) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 20 * ms) == [.system(.keyUp(.b))])
    #expect(state.heldOutputs.isEmpty)
  }

  @Test
  func gamepadStepsGoThroughTheVirtualGamepad() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [.chord(destinations: [.gamepadButton(.south), .gamepadDpad(.up)], holdMs: 10)]
      ),
      policy: RemappingOutputPolicy(virtualGamepad: .mapped)
    )
    let down = press(&state, profile, at: 0)
    #expect(down.count == 2)
    let up = state.tick(at: 10 * ms)
    #expect(up.count == 2)
    guard case .gamepad(let final, _) = up[1] else {
      Issue.record("Expected a gamepad action")
      return
    }
    #expect(final == .neutral)
  }

  // MARK: Stop paths leave nothing down

  @Test
  func controllerDisconnectStopsAWhileHeldMacro() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [.chord(destinations: [key(.a)], holdMs: 100)],
        repeatMode: .whileHeld
      )
    )
    _ = press(&state, profile, at: 0)
    #expect(state.releaseController(identifier) == [.system(.keyUp(.a))])
    assertIdle(&state)
  }

  @Test
  func profileChangeAndDeactivationStopTheMacro() {
    for replacement in [nil, profile(RemappingMacro(name: "N", steps: [tap(.c)]))] {
      var state = RemappingEngineState()
      let profile = profile(
        RemappingMacro(
          name: "M",
          steps: [.chord(destinations: [key(.a)], holdMs: 100)],
          repeatMode: .count(5)
        )
      )
      _ = press(&state, profile, at: 0)
      _ = release(&state, profile, at: 10 * ms)
      #expect(state.setProfile(replacement, for: identifier) == [.system(.keyUp(.a))])
      assertIdle(&state)
    }
  }

  @Test
  func drainStopsTheMacroAfterTheSourceWasReleased() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(name: "M", steps: [.press(key(.a)), .wait(durationMs: 100)])
    )
    _ = press(&state, profile, at: 0)
    _ = release(&state, profile, at: 10 * ms)
    #expect(state.drain() == [.system(.keyUp(.a))])
    assertIdle(&state)
  }

  @Test
  func stoppedMacroStartsNoOtherPass() {
    var state = RemappingEngineState()
    let profile = profile(
      RemappingMacro(
        name: "M",
        steps: [tap(.a), .wait(durationMs: 10)],
        repeatMode: .whileHeld
      )
    )
    _ = press(&state, profile, at: 0)
    _ = state.releaseController(identifier)
    #expect(state.tick(at: 1_000 * ms).isEmpty)
  }

  @Test
  func sinkFailureReleasesEveryMacroOutput() async throws {
    let sink = RemappingTestSink(failingCalls: [2])
    let engine = RemappingEventEngine(sink: sink)
    let profile = profile(
      RemappingMacro(name: "M", steps: [.press(key(.a)), .wait(durationMs: 10), tap(.b)])
    )
    try await engine.process(inputs: [.press(.south)], from: identifier, using: profile, at: 0)
    await #expect(throws: RemappingEventEngineError.sinkUnavailable) {
      try await engine.tick(at: 10 * ms)
    }
    let sent = sink.actions()
    #expect(sent.contains(.keyUp(.a)))
    #expect(sent.contains(.keyUp(.b)))
    #expect(await !engine.hasScheduledOutput())
  }

  // MARK: Helpers

  private func assertIdle(_ state: inout RemappingEngineState) {
    #expect(state.heldOutputs.isEmpty)
    #expect(!state.hasScheduledOutput)
    #expect(state.tick(at: 100_000 * ms).isEmpty)
  }

  private func press(
    _ state: inout RemappingEngineState,
    _ profile: RemappingProfile,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    state.process(inputs: [.press(.south)], from: identifier, profile: profile, at: uptime)
  }

  private func release(
    _ state: inout RemappingEngineState,
    _ profile: RemappingProfile,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    state.process(inputs: [.release(.south)], from: identifier, profile: profile, at: uptime)
  }

  private func profile(
    _ macro: RemappingMacro,
    policy: RemappingOutputPolicy = .systemInput
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Macro",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: policy,
      bindings: [RemappingBinding(source: .button(.south), destination: .macro(macro.id))],
      macros: [macro]
    )
  }
}
