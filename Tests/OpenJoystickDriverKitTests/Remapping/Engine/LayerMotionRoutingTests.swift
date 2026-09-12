import Testing
@testable import OpenJoystickDriverKit

struct LayerMotionRoutingTests {
  @Test func latestActivatedOverrideWinsAndReleaseRestoresPrevious() {
    let base = RemappingMotionTuning(yawSensitivity: 1)
    let first = RemappingMotionTuning(yawSensitivity: 2)
    let second = RemappingMotionTuning(yawSensitivity: 3)
    let profile = RemappingProfile(
      name: "Layer motion",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      motionTuning: base,
      bindings: [],
      layers: [
        RemappingLayer(
          name: "First", activationMode: .hold, activator: .button(.south), motionTuning: first
        ),
        RemappingLayer(
          name: "Second", activationMode: .toggle, activator: .button(.east), motionTuning: second
        ),
        RemappingLayer(name: "Bindings only", activationMode: .hold, activator: .button(.west))
      ]
    )
    let identifier = DeviceIdentifier(vendorID: 1, productID: 2)
    var engine = RemappingEngineState()
    func send(_ event: ControllerEvent) {
      _ = engine.process(events: [event], from: identifier, profile: profile, at: 0)
    }
    send(.buttonPressed(.a))
    #expect(engine.devices[identifier]?.effectiveMotionTuning == first)
    send(.buttonPressed(.b))
    #expect(engine.devices[identifier]?.effectiveMotionTuning == second)
    send(.buttonPressed(.x))
    #expect(engine.devices[identifier]?.effectiveMotionTuning == second)
    send(.buttonReleased(.b))
    send(.buttonPressed(.b))
    #expect(engine.devices[identifier]?.effectiveMotionTuning == first)
    send(.buttonReleased(.a))
    #expect(engine.devices[identifier]?.effectiveMotionTuning == base)
    #expect(engine.devices[identifier]?.gyroAwaitingBaseline == true)
  }
}
