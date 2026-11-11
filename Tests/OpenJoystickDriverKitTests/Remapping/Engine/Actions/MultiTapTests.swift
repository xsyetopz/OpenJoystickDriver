import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct MultiTapTests {
  private let millisecond: UInt64 = 1_000_000

  @Test
  func tripleTapFiresItsDestinationOnce() {
    var state = RemappingEngineState()
    let profile = profile(taps: [(2, 300, .b), (3, 300, .c)])
    var actions: [RemappingEngineAction] = []
    for index in 0..<3 {
      let base = UInt64(index) * 100 * millisecond
      actions += press(&state, profile, at: base)
      actions += release(&state, profile, at: base + 50 * millisecond)
    }
    #expect(actions == [.system(.keyDown(.c)), .system(.keyUp(.c))])
    #expect(state.tick(at: 2_000 * millisecond).isEmpty)
  }

  @Test
  func countNotReachedFiresOnlyTheReachedCountAfterTheWindow() {
    var state = RemappingEngineState()
    let profile = profile(taps: [(2, 300, .b), (3, 300, .c)])
    var actions: [RemappingEngineAction] = []
    actions += press(&state, profile, at: 0)
    actions += release(&state, profile, at: 50 * millisecond)
    actions += press(&state, profile, at: 100 * millisecond)
    actions += release(&state, profile, at: 150 * millisecond)
    #expect(actions.isEmpty)
    #expect(state.tick(at: 449 * millisecond).isEmpty)
    #expect(state.tick(at: 450 * millisecond) == [.system(.keyDown(.b)), .system(.keyUp(.b))])
    #expect(state.tick(at: 2_000 * millisecond).isEmpty)
  }

  @Test
  func windowRunsFromReleaseToNextPress() {
    var state = RemappingEngineState()
    let profile = profile(taps: [(2, 300, .b)])
    _ = press(&state, profile, at: 0)
    // A hold of 1 s does not matter: only the release-to-press gap counts.
    _ = release(&state, profile, at: 1_000 * millisecond)
    let actions = press(&state, profile, at: 1_299 * millisecond)
    #expect(actions == [.system(.keyDown(.b))])
    #expect(release(&state, profile, at: 1_400 * millisecond) == [.system(.keyUp(.b))])
  }

  @Test
  func baseDestinationWaitsForTheLongestWindow() {
    var state = RemappingEngineState()
    let profile = profile(taps: [(2, 200, .b), (3, 300, .c)])
    #expect(press(&state, profile, at: 0).isEmpty)
    #expect(release(&state, profile, at: 50 * millisecond).isEmpty)
    #expect(state.tick(at: 349 * millisecond).isEmpty)
    #expect(
      state.nextScheduledTick(after: 60 * millisecond, continuousIntervalNanoseconds: 1)
        == 350 * millisecond
    )
    #expect(state.tick(at: 350 * millisecond) == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  @Test
  func lateSecondPressTapsBaseFirst() {
    var state = RemappingEngineState()
    let profile = profile(taps: [(2, 200, .b)])
    _ = press(&state, profile, at: 0)
    _ = release(&state, profile, at: 50 * millisecond)
    let actions = press(&state, profile, at: 400 * millisecond)
    #expect(actions == [.system(.keyDown(.a)), .system(.keyUp(.a))])
  }

  @Test
  func doubleTapKeyIsRejected() throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .a, modifiers: [])
    )
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any]
    )
    object["doubleTap"] = ["windowMs": 200, "destination": object["destination"] as Any]
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(RemappingBinding.self, from: data)
    }
  }

  @Test
  func multiTapRoundTripsAndValidates() throws {
    let valid = profile(taps: [(2, 200, .b), (5, 300, .c)])
    try valid.validate()
    let data = try JSONEncoder().encode(valid)
    #expect(try JSONDecoder().decode(RemappingProfile.self, from: data) == valid)
    let invalid: [[(Int, Double, RemappingKeyboardKey)]] = [
      [(1, 200, .b)], [(6, 200, .b)], [(2, 49, .b)], [(2, 1001, .b)],
      [(2, 200, .b), (2, 300, .c)], [(2, .nan, .b)],
    ]
    for taps in invalid {
      #expect(throws: RemappingValidationError.self) { try profile(taps: taps).validate() }
    }
  }

  @Test
  func turboInitialDelayAndMaxRepeats() {
    var state = RemappingEngineState()
    let profile = turboProfile(
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: 400, maxRepeats: 3)
    )
    // Press at 0: down once. Period 100 ms, on 50 ms.
    #expect(press(&state, profile, at: 0) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 50 * millisecond) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 399 * millisecond).isEmpty)
    #expect(state.tick(at: 400 * millisecond) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 450 * millisecond) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 500 * millisecond) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 550 * millisecond) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 600 * millisecond) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 650 * millisecond) == [.system(.keyUp(.a))])
    // Three repeats are done: no more until the next press.
    #expect(state.tick(at: 700 * millisecond).isEmpty)
    #expect(state.tick(at: 5_000 * millisecond).isEmpty)
    #expect(release(&state, profile, at: 5_001 * millisecond).isEmpty)
    #expect(press(&state, profile, at: 6_000 * millisecond) == [.system(.keyDown(.a))])
  }

  @Test
  func turboWithoutDelayOrCapKeepsItsCycle() {
    var state = RemappingEngineState()
    let profile = turboProfile(RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5))
    #expect(press(&state, profile, at: 0) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 50 * millisecond) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 100 * millisecond) == [.system(.keyDown(.a))])
    #expect(state.tick(at: 150 * millisecond) == [.system(.keyUp(.a))])
    #expect(state.tick(at: 10_000 * millisecond) == [.system(.keyDown(.a))])
  }

  @Test
  func turboRangesAreValidated() throws {
    try turboProfile(
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: 2500, maxRepeats: 500)
    ).validate()
    for turbo in [
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: -1),
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: 2501),
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: .nan),
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, maxRepeats: 0),
      RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, maxRepeats: 501),
    ] {
      #expect(throws: RemappingValidationError.self) { try turboProfile(turbo).validate() }
    }
  }

  // MARK: Helpers

  private var identifier: LogicalControllerID {
    LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
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

  private func profile(taps: [(Int, Double, RemappingKeyboardKey)]) -> RemappingProfile {
    RemappingProfile(
      name: "Taps",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: []),
          multiTap: taps.map {
            RemappingMultiTap(
              count: $0.0,
              windowMs: $0.1,
              destination: .keyboard(key: $0.2, modifiers: [])
            )
          }
        )
      ]
    )
  }

  private func turboProfile(_ turbo: RemappingTurbo) -> RemappingProfile {
    RemappingProfile(
      name: "Turbo",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .a, modifiers: []),
          turbo: turbo
        )
      ]
    )
  }
}
