import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Each physical source is diffed against its own last snapshot.
struct SourceBaselineTests {
  private let first = LogicalControllerID(vendorID: 1, productID: 2, locationID: 1)
  private let second = LogicalControllerID(vendorID: 1, productID: 2, locationID: 2)

  private let profile = RemappingProfile(
    name: "Baselines",
    device: RemappingDeviceScope(vendorID: 1, productID: 2),
    applicationScope: .global,
    outputPolicy: RemappingOutputPolicy(virtualGamepad: .disabled),
    bindings: [
      RemappingBinding(source: .button(.south), destination: .keyboard(key: .a, modifiers: []))
    ]
  )

  @Test
  func twoSourcesIntoOneTargetNeverReleaseEachOther() {
    var engine = RemappingEngineState()
    let held = ControllerEvent([.press(.south)])
    let neutral = ControllerEvent([])
    func process(
      _ event: ControllerEvent,
      from source: LogicalControllerID
    ) -> [RemappingEngineAction] {
      engine.process(event, from: source, into: first, profile: profile, at: 0)
    }
    #expect(process(held, from: first) == [.system(.keyDown(.a))])
    // The second source's neutral snapshot changes nothing of its own baseline.
    #expect(process(neutral, from: second).isEmpty)
    #expect(process(held, from: first).isEmpty)
    #expect(process(neutral, from: first) == [.system(.keyUp(.a))])
  }

  @Test
  func endingSourceForgetsItsBaselineAndProfileChangesKeepIt() async throws {
    let sink = RemappingTestSink()
    let engine = RemappingEventEngine(sink: sink)
    try await engine.process(
      ControllerEvent([.press(.south)]),
      from: first,
      using: profile,
      at: 0
    )
    try await engine.releaseAll(for: first)
    // Kept across a release: the held button is not pressed again by an identical snapshot.
    try await engine.process(
      ControllerEvent([.press(.south)]),
      from: first,
      using: profile,
      at: 1
    )
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a)])
    await engine.endSource(first)
    try await engine.process(
      ControllerEvent([.press(.south)]),
      from: first,
      using: profile,
      at: 2
    )
    #expect(sink.actions() == [.keyDown(.a), .keyUp(.a), .keyDown(.a)])
  }
}
