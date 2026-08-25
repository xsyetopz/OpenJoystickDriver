import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingEngineTests {
  @Test func xboxAndPlayStationAliasesReachTheSameFaceAndShoulderSources() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let aliases: [(Button, Button, RemappingSource)] = [
      (.a, .cross, .button(.south)), (.b, .circle, .button(.east)), (.x, .square, .button(.west)),
      (.y, .triangle, .button(.north)), (.leftBumper, .l1, .button(.leftShoulder)),
      (.rightBumper, .r1, .button(.rightShoulder)), (.guide, .ps, .button(.guide))
    ]

    for (first, second, source) in aliases {
      let profile = profile(bindings: [binding(source: source, key: .space)])
      try await engine.process(
        events: [.buttonPressed(first), .buttonReleased(first)],
        from: device(1),
        using: profile,
        at: 0
      )
      try await engine.process(
        events: [.buttonPressed(second), .buttonReleased(second)],
        from: device(1),
        using: profile,
        at: 0
      )
    }

    #expect(
      sink.actions()
        == Array(repeating: [.keyDown(.space), .keyUp(.space)], count: 14).flatMap { $0 }
    )
  }

  @Test func modelSpecificButtonsAndGenericAuxiliariesRemainReachable() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let cases: [(Button, RemappingButton)] = [
      (.share, .share), (.options, .options), (.genericButton1, .auxiliary1),
      (.genericButton2, .auxiliary2), (.genericButton3, .auxiliary3),
      (.genericButton4, .auxiliary4), (.genericButton5, .auxiliary5),
      (.genericButton6, .auxiliary6), (.genericButton7, .auxiliary7), (.genericButton8, .auxiliary8)
    ]

    for (button, source) in cases {
      let currentProfile = profile(bindings: [binding(source: .button(source), key: .returnKey)])
      try await engine.process(
        events: [.buttonPressed(button), .buttonReleased(button)],
        from: device(1),
        using: currentProfile,
        at: 0
      )
    }

    #expect(
      sink.actions()
        == Array(repeating: [.keyDown(.returnKey), .keyUp(.returnKey)], count: cases.count).flatMap
      { $0 }
    )
  }

  @Test func dpadDiagonalTransitionsMaintainIndependentCardinalSources() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      binding(source: .dpad(.up), key: .w), binding(source: .dpad(.right), key: .d)
    ])

    try await engine.process(
      events: [.dpadChanged(.northEast)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    try await engine.process(
      events: [.dpadChanged(.east)],
      from: device(1),
      using: currentProfile,
      at: 1
    )
    try await engine.process(
      events: [.dpadChanged(.neutral)],
      from: device(1),
      using: currentProfile,
      at: 2
    )

    #expect(sink.actions() == [.keyDown(.d), .keyDown(.w), .keyUp(.w), .keyUp(.d)])
  }

  @Test func digitalThresholdUsesHysteresisAndSuppressesDuplicateAxisEvents() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let tuning = RemappingAxisTuning(deadzone: 0, gain: 1, digitalActivationThreshold: 0.5)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .axisDirection(.leftStickX, .positive),
        destination: .keyboard(key: .arrowRight, modifiers: []),
        axisTuning: tuning
      )
    ])

    for value: Float in [0.6, 0.6, 0.47, 0.45, 0.45] {
      try await engine.process(
        events: [.leftStickChanged(x: value, y: 0)],
        from: device(1),
        using: currentProfile,
        at: 0
      )
    }

    #expect(sink.actions() == [.keyDown(.arrowRight), .keyUp(.arrowRight)])
  }

  @Test func continuousAxesApplyTuningClampAndStopAtNeutral() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .axis(.rightStickX),
        destination: .mouseMovement(.x),
        axisTuning: RemappingAxisTuning(deadzone: 0.2, gain: 10)
      ),
      RemappingBinding(
        source: .axis(.rightTrigger),
        destination: .scroll(.y),
        axisTuning: RemappingAxisTuning(
          deadzone: 0,
          gain: 0.5,
          inverted: true,
          responseCurve: .easeIn
        )
      )
    ])

    try await engine.process(
      events: [.rightStickChanged(x: 0.1, y: 0), .rightTriggerChanged(0.5)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    try await engine.tick(at: 1)
    try await engine.process(
      events: [.rightStickChanged(x: 0.6, y: 0)],
      from: device(1),
      using: currentProfile,
      at: 2
    )
    try await engine.tick(at: 3)
    try await engine.process(
      events: [.rightStickChanged(x: 0, y: 0), .rightTriggerChanged(0)],
      from: device(1),
      using: currentProfile,
      at: 4
    )
    try await engine.tick(at: 5)

    #expect(
      sink.actions() == [
        .scrolled(axis: .y, amount: -0.125), .mouseMoved(axis: .x, amount: 1),
        .scrolled(axis: .y, amount: -0.125), .mouseMoved(axis: .x, amount: 0),
        .scrolled(axis: .y, amount: 0)
      ]
    )
  }

  @Test func turboUsesInjectedRateAndDutyTicksAndCancelsWithoutDuplicateRelease() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.south),
        destination: .mouseButton(.left),
        turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.25)
      )
    ])
    let start: UInt64 = 1_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(1),
      using: currentProfile,
      at: start
    )
    try await engine.tick(at: start + 24_000_000)
    try await engine.tick(at: start + 25_000_000)
    try await engine.tick(at: start + 99_000_000)
    try await engine.tick(at: start + 100_000_000)
    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 125_000_000
    )
    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(1),
      using: currentProfile,
      at: start + 126_000_000
    )

    #expect(
      sink.actions() == [
        .mouseButtonDown(.left), .mouseButtonUp(.left), .mouseButtonDown(.left),
        .mouseButtonUp(.left)
      ]
    )
  }

  @Test func sameDestinationIsReferenceCountedAcrossSourcesAndControllers() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      binding(source: .button(.south), key: .space), binding(source: .button(.east), key: .space)
    ])

    try await engine.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device(2),
      using: currentProfile,
      at: 0
    )
    try await engine.process(
      events: [.buttonReleased(.a), .buttonReleased(.b)],
      from: device(1),
      using: currentProfile,
      at: 1
    )
    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device(2),
      using: currentProfile,
      at: 1
    )

    #expect(sink.actions() == [.keyDown(.space), .keyUp(.space)])
  }

  @Test func sharedModifiersRemainDownUntilTheLastChordReleases() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [
      binding(source: .button(.south), key: .a, modifiers: [.shift, .command]),
      binding(source: .button(.east), key: .b, modifiers: [.shift])
    ])

    try await engine.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: device(1),
      using: currentProfile,
      at: 0
    )
    try await engine.process(
      events: [.buttonReleased(.a), .buttonReleased(.b)],
      from: device(1),
      using: currentProfile,
      at: 1
    )

    #expect(
      sink.actions() == [
        .modifierDown(.command), .modifierDown(.shift), .keyDown(.a), .keyDown(.b), .keyUp(.a),
        .modifierUp(.command), .keyUp(.b), .modifierUp(.shift)
      ]
    )
  }

  @Test func perControllerReleaseAndGlobalDrainAreReferenceSafeAndIdempotent() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let currentProfile = profile(bindings: [binding(source: .button(.south), key: .space)])

    for identifier in [device(1), device(2)] {
      try await engine.process(
        events: [.buttonPressed(.a)],
        from: identifier,
        using: currentProfile,
        at: 0
      )
    }
    try await engine.releaseAll(for: device(1))
    try await engine.drain()
    try await engine.drain()
    try await engine.releaseAll(for: device(2))

    #expect(sink.actions() == [.keyDown(.space), .keyUp(.space)])
  }

  @Test func profileReplacementAndDeactivationNeutralizeBeforeNewOutput() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    let first = profile(name: "First", bindings: [binding(source: .button(.south), key: .a)])
    let second = profile(name: "Second", bindings: [binding(source: .button(.south), key: .b)])

    try await engine.process(events: [.buttonPressed(.a)], from: device(1), using: first, at: 0)
    try await engine.process(events: [.buttonPressed(.a)], from: device(1), using: second, at: 1)
    try await engine.setProfile(nil, for: device(1))
    try await engine.setProfile(nil, for: device(1))

    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a), .keyDown(.b), .keyUp(.b)])
  }

  private func profile(name: String = "Engine", bindings: [RemappingBinding]) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: bindings
    )
  }

  private func binding(
    source: RemappingSource,
    key: RemappingKeyboardKey,
    modifiers: Set<RemappingKeyModifier> = []
  ) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: key, modifiers: modifiers))
  }

  private func device(_ locationID: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: locationID)
  }

}
