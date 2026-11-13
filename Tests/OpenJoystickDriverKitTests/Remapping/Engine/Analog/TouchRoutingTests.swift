import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingTouchRoutingTests {
  @Test
  func contactGridAndSwipeStayScopedToSurfaceAndDevice() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(bindings: [
      binding(.touchContact(.primary), .a),
      binding(
        .touchGrid(
          RemappingTouchGridSource(surface: .primary, columns: 2, rows: 2, column: 1, row: 0)
        ),
        .b
      ), binding(.touchSwipe(RemappingTouchSwipeSource(surface: .primary, direction: .right)), .c),
      binding(.touchContact(.left), .d),
    ])
    let first = device(1)
    let second = device(2)

    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: true, x: percent(10), y: percent(10)))],
      from: first,
      using: profile,
      at: 1
    )
    try await engine.process(
      inputs: [.touch(sample(.left, slot: 0, active: true, x: percent(10), y: percent(10)))],
      from: first,
      using: profile,
      at: 2
    )
    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: true, x: percent(80), y: percent(10)))],
      from: first,
      using: profile,
      at: 3
    )
    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: false, x: percent(80), y: percent(10)))],
      from: first,
      using: profile,
      at: 4
    )
    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: true, x: percent(10), y: percent(10)))],
      from: second,
      using: profile,
      at: 5
    )

    #expect(
      recorder.systemActions == [
        .keyDown(.a), .keyDown(.d), .keyDown(.b), .keyUp(.a), .keyUp(.b), .keyDown(.c), .keyUp(.c),
        .keyDown(.a),
      ]
    )
  }

  @Test
  func pointerUsesNormalizedSpanAndResetsBaselineOnContactChange() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(touchMappings: [
      RemappingTouchMapping(surface: .left, mode: .pointer, pointerSensitivity: 1_000)
    ])

    for (index, event) in [
      sample(.left, slot: 0, active: true, x: 0, y: 0),
      sample(.left, slot: 0, active: true, x: 32_768, y: 16_384),
      sample(.right, slot: 0, active: true, x: 58_982, y: 58_982),
      sample(.left, slot: 1, active: true, x: 49_151, y: 49_151),
    ].enumerated() {
      try await engine.process(
        inputs: [.touch(event)],
        from: device(1),
        using: profile,
        at: UInt64(index)
      )
    }

    // Pointer sensitivity is points per complete span: 65535 steps.
    let span = Double(UInt16.max)
    let expected = RemappingSystemInputAction.pointerDelta(
      x: 32_768 / span * 1_000,
      y: 16_384 / span * 1_000
    )
    #expect(recorder.systemActions == [expected])
  }

  @Test
  func jumpWithinOneContactIsMotionAndLiftThenRetouchStartsFreshContact() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(touchMappings: [
      RemappingTouchMapping(surface: .primary, mode: .pointer, pointerSensitivity: 1_000)
    ])

    for (index, event) in [
      sample(.primary, slot: 1, active: true, x: 0, y: 0),
      sample(.primary, slot: 1, active: true, x: 65_535, y: 0),
      sample(.primary, slot: 1, active: false, x: 65_535, y: 0),
      sample(.primary, slot: 1, active: true, x: 0, y: 0),
      sample(.primary, slot: 1, active: true, x: 0, y: 65_535),
    ].enumerated() {
      try await engine.process(
        inputs: [.touch(event)],
        from: device(1),
        using: profile,
        at: UInt64(index)
      )
    }

    // Slots, not device tracking IDs, identify contacts: without an inactive frame a jump reads
    // as motion; after one, the slot starts a new contact with a fresh baseline.
    #expect(
      recorder.systemActions == [.pointerDelta(x: 1_000, y: 0), .pointerDelta(x: 0, y: 1_000)]
    )
  }

  @Test
  func physicalClickRemainsIndependentFromTouchContact() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(bindings: [
      binding(.touchContact(.primary), .a), binding(.button(.touchpadClick), .b),
    ])

    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: true, x: percent(10), y: percent(10)))],
      from: device(1),
      using: profile,
      at: 1
    )
    #expect(recorder.systemActions == [.keyDown(.a)])
    try await engine.process(
      inputs: [.press(.touchpadClick), .release(.touchpadClick)],
      from: device(1),
      using: profile,
      at: 2
    )
    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: false, x: percent(10), y: percent(10)))],
      from: device(1),
      using: profile,
      at: 3
    )
    #expect(recorder.systemActions == [.keyDown(.a), .keyDown(.b), .keyUp(.b), .keyUp(.a)])
  }

  @Test
  func touchStickOwnsVirtualAxesAndNeutralizesOnRelease() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder, gamepadSink: recorder)
    let profile = makeProfile(
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      touchMappings: [
        RemappingTouchMapping(
          surface: .primary,
          mode: .leftStick,
          stickRadius: stickRadius,
          deadzone: 0
        )
      ]
    )
    let identifier = device(1)

    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: true, x: 0, y: percent(50)))],
      from: identifier,
      using: profile,
      at: 1
    )
    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: true, x: halfSpan, y: percent(50)))],
      from: identifier,
      using: profile,
      at: 2
    )
    try await engine.process(
      inputs: [.touch(sample(.primary, slot: 0, active: false, x: halfSpan, y: percent(50)))],
      from: identifier,
      using: profile,
      at: 3
    )

    #expect(recorder.gamepadStates == [RemappingGamepadState(axes: [.leftStickX: 1]), .neutral])
  }

  @Test
  func disconnectReleasesTouchBindingAndVirtualContributionForOnlyThatDevice() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder, gamepadSink: recorder)
    let profile = makeProfile(
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      touchMappings: [
        RemappingTouchMapping(
          surface: .primary,
          mode: .leftStick,
          stickRadius: stickRadius,
          deadzone: 0
        )
      ],
      bindings: [binding(.touchContact(.primary), .a)]
    )
    let first = device(1)
    let second = device(2)
    for identifier in [first, second] {
      try await engine.process(
        inputs: [
          .touch(sample(.primary, slot: 0, active: true, x: 0, y: percent(50))),
          .touch(sample(.primary, slot: 0, active: true, x: halfSpan, y: percent(50))),
        ],
        from: identifier,
        using: profile,
        at: 1
      )
    }

    try await engine.releaseAll(for: first)

    #expect(recorder.systemActions == [.keyDown(.a)])
    #expect(
      recorder.gamepadStates == [
        RemappingGamepadState(axes: [.leftStickX: 1]),
        RemappingGamepadState(axes: [.leftStickX: 1]), .neutral,
      ]
    )
    try await engine.releaseAll(for: second)
    #expect(recorder.systemActions == [.keyDown(.a), .keyUp(.a)])
    #expect(recorder.gamepadStates.last == .neutral)
  }

  private func makeProfile(
    outputPolicy: RemappingOutputPolicy = .systemInput,
    touchMappings: [RemappingTouchMapping] = [],
    bindings: [RemappingBinding] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: "Touch",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      outputPolicy: outputPolicy,
      touchMappings: touchMappings,
      bindings: bindings
    )
  }

  private func binding(_ source: RemappingSource, _ key: RemappingKeyboardKey) -> RemappingBinding {
    RemappingBinding(source: source, destination: .keyboard(key: key, modifiers: []))
  }

  private func device(_ locationID: UInt32) -> LogicalControllerID {
    LogicalControllerID(vendorID: 1, productID: 2, locationID: locationID)
  }

  /// The largest travel below half the span, and a stick radius equal to it, so a contact that
  /// travels it deflects the stick by exactly 1 without saturating.
  private let halfSpan: UInt16 = 32_767
  private let stickRadius = 32_767.0 / 65_535

  /// Contacts in percent of the surface span use `percent`; others pass normalized steps.
  private func sample(
    _ surface: ControllerTouchSurface,
    slot: UInt8,
    active: Bool,
    x: UInt16,
    y: UInt16
  ) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: surface,
      timestamp: MonotonicTimestamp(nanoseconds: 0),
      contacts: [ControllerTouchContact(slot: slot, isActive: active, x: x, y: y)]
    )
  }

  private func percent(_ value: UInt16) -> UInt16 {
    UInt16((Double(value) / 100 * Double(UInt16.max)).rounded())
  }
}
