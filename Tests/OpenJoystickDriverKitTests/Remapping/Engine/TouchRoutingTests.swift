import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct RemappingTouchRoutingTests {
  @Test func contactGridAndSwipeStayScopedToSurfaceAndDevice() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(bindings: [
      binding(.touchContact(.primary), .a),
      binding(
        .touchGrid(
          RemappingTouchGridSource(
            surface: .primary, columns: 2, rows: 2, column: 1, row: 0
          )
        ),
        .b
      ),
      binding(
        .touchSwipe(RemappingTouchSwipeSource(surface: .primary, direction: .right)),
        .c
      ),
      binding(.touchContact(.left), .d)
    ])
    let first = device(1)
    let second = device(2)

    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: true, x: 10, y: 10))],
      from: first,
      using: profile,
      at: 1
    )
    try await engine.process(
      events: [.touchSample(sample(.left, id: 0, active: true, x: 10, y: 10))],
      from: first,
      using: profile,
      at: 2
    )
    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: true, x: 80, y: 10))],
      from: first,
      using: profile,
      at: 3
    )
    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: false, x: 80, y: 10))],
      from: first,
      using: profile,
      at: 4
    )
    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: true, x: 10, y: 10))],
      from: second,
      using: profile,
      at: 5
    )

    #expect(
      recorder.systemActions == [
        .keyDown(.a), .keyDown(.d), .keyDown(.b), .keyUp(.a), .keyUp(.b),
        .keyDown(.c), .keyUp(.c), .keyDown(.a)
      ]
    )
  }

  @Test func pointerUsesSurfaceGeometryAndResetsBaselineOnGeometryOrContactChange() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(
      touchMappings: [
        RemappingTouchMapping(
          surface: .left, mode: .pointer, pointerSensitivity: 1_000
        )
      ]
    )

    for (index, event) in [
      sample(
        .left, id: 0, active: true, x: -32_768, y: -32_768, width: 65_536, height: 65_536
      ),
      sample(.left, id: 0, active: true, x: 0, y: -16_384, width: 65_536, height: 65_536),
      sample(.right, id: 0, active: true, x: 90, y: 90),
      sample(.left, id: 0, active: true, x: 50, y: 50),
      sample(.left, id: 1, active: true, x: 75, y: 75),
    ].enumerated() {
      try await engine.process(
        events: [.touchSample(event)],
        from: device(1),
        using: profile,
        at: UInt64(index)
      )
    }

    #expect(recorder.systemActions == [.pointerDelta(x: 500, y: 250)])
  }

  @Test func physicalClickRemainsIndependentFromTouchContact() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder)
    let profile = makeProfile(bindings: [
      binding(.touchContact(.primary), .a),
      binding(.button(.touchpad), .b)
    ])

    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: true, x: 10, y: 10))],
      from: device(1),
      using: profile,
      at: 1
    )
    #expect(recorder.systemActions == [.keyDown(.a)])
    try await engine.process(
      events: [.buttonPressed(.touchpad), .buttonReleased(.touchpad)],
      from: device(1),
      using: profile,
      at: 2
    )
    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: false, x: 10, y: 10))],
      from: device(1),
      using: profile,
      at: 3
    )
    #expect(recorder.systemActions == [
      .keyDown(.a), .keyDown(.b), .keyUp(.b), .keyUp(.a)
    ])
  }

  @Test func touchStickOwnsVirtualAxesAndNeutralizesOnRelease() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder, gamepadSink: recorder)
    let profile = makeProfile(
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      touchMappings: [
        RemappingTouchMapping(
          surface: .primary, mode: .leftStick, stickRadius: 0.5, deadzone: 0
        )
      ]
    )
    let identifier = device(1)

    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: true, x: 25, y: 50))],
      from: identifier,
      using: profile,
      at: 1
    )
    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: true, x: 75, y: 50))],
      from: identifier,
      using: profile,
      at: 2
    )
    try await engine.process(
      events: [.touchSample(sample(.primary, id: 0, active: false, x: 75, y: 50))],
      from: identifier,
      using: profile,
      at: 3
    )

    #expect(recorder.gamepadStates == [
      RemappingGamepadState(axes: [.leftStickX: 1]), .neutral
    ])
  }

  @Test func disconnectReleasesTouchBindingAndVirtualContributionForOnlyThatDevice() async throws {
    let recorder = TouchOutputRecorder()
    let engine = RemappingEventEngine(sink: recorder, gamepadSink: recorder)
    let profile = makeProfile(
      outputPolicy: RemappingOutputPolicy(virtualGamepad: .mapped),
      touchMappings: [
        RemappingTouchMapping(
          surface: .primary, mode: .leftStick, stickRadius: 0.5, deadzone: 0
        )
      ],
      bindings: [binding(.touchContact(.primary), .a)]
    )
    let first = device(1)
    let second = device(2)
    for identifier in [first, second] {
      try await engine.process(
        events: [
          .touchSample(sample(.primary, id: 0, active: true, x: 25, y: 50)),
          .touchSample(sample(.primary, id: 0, active: true, x: 75, y: 50))
        ],
        from: identifier,
        using: profile,
        at: 1
      )
    }

    try await engine.releaseAll(for: first)

    #expect(recorder.systemActions == [.keyDown(.a)])
    #expect(recorder.gamepadStates == [
      RemappingGamepadState(axes: [.leftStickX: 1]),
      RemappingGamepadState(axes: [.leftStickX: 1]),
      .neutral
    ])
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

  private func binding(_ source: RemappingSource, _ key: RemappingKeyboardKey)
    -> RemappingBinding
  { RemappingBinding(source: source, destination: .keyboard(key: key, modifiers: [])) }

  private func device(_ locationID: UInt32) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: locationID)
  }

  private func sample(
    _ surface: ControllerTouchSurface,
    id: UInt8,
    active: Bool,
    x: Int32,
    y: Int32,
    width: UInt32 = 100,
    height: UInt32 = 100
  ) -> ControllerTouchSample {
    ControllerTouchSample(
      reportTimestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        elapsedNanoseconds: 0,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: 0,
        basis: .hostEstimate
      ),
      rawTouchCounter: nil,
      historyIndex: 0,
      width: width,
      height: height,
      contacts: [ControllerTouchContact(id: id, isActive: active, x: x, y: y)],
      surface: surface,
      originX: width == 65_536 ? -32_768 : 0,
      originY: width == 65_536 ? -32_768 : 0
    )
  }
}

private final class TouchOutputRecorder: RemappingSystemInputSink, RemappingGamepadSink,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var recordedSystemActions: [RemappingSystemInputAction] = []
  private var recordedGamepadStates: [RemappingGamepadState] = []

  var systemActions: [RemappingSystemInputAction] { lock.withLock { recordedSystemActions } }
  var gamepadStates: [RemappingGamepadState] { lock.withLock { recordedGamepadStates } }

  func send(_ action: RemappingSystemInputAction) {
    lock.withLock { recordedSystemActions.append(action) }
  }

  func send(_ state: RemappingGamepadState, for _: DeviceIdentifier) async {
    await Task.yield()
    lock.withLock { recordedGamepadStates.append(state) }
  }
}
