import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DeviceInputStateTests {
  @Test func testInitialStateIsZero() {
    let state = DeviceInputState(vendorID: 100, productID: 200)
    #expect(state.pressedButtons.isEmpty)
    #expect(state.leftStickX == 0)
    #expect(state.leftStickY == 0)
    #expect(state.rightStickX == 0)
    #expect(state.rightStickY == 0)
    #expect(state.leftTrigger == 0)
    #expect(state.rightTrigger == 0)
    #expect(state.touchSamples.isEmpty)
  }

  @Test func touchSamplesRoundTripAndOlderSnapshotsDefaultToNoTouchCapability() throws {
    var state = DeviceInputState(vendorID: 1, productID: 2)
    state.apply(events: [
      .touchSample(
        ControllerTouchSample(
          reportTimestamp: ControllerSampleTimestamp(
            rawCounter: 1,
            elapsedNanoseconds: 2,
            tickNanosecondsNumerator: nil,
            tickNanosecondsDenominator: nil,
            sequenceIndex: 3
          ),
          rawTouchCounter: 4,
          historyIndex: 0,
          width: 100,
          height: 50,
          contacts: [ControllerTouchContact(id: 0, isActive: true, x: 25, y: 10)],
          surface: .left,
          originX: 0,
          originY: 0
        )
      )
    ])
    let decoded = try JSONDecoder().decode(
      DeviceInputState.self, from: JSONEncoder().encode(state)
    )
    #expect(decoded == state)

    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
    )
    object.removeValue(forKey: "touchSamples")
    let older = try JSONDecoder().decode(
      DeviceInputState.self, from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(older.touchSamples.isEmpty)
  }
  @Test func testCodableRoundTrip() throws {
    var state = DeviceInputState(vendorID: 0x3537, productID: 0x1010)
    state.pressedButtons = ["a", "b"]
    state.leftStickX = 0.5
    state.leftTrigger = 0.75
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(DeviceInputState.self, from: data)
    #expect(decoded.pressedButtons == ["a", "b"])
    #expect(abs(decoded.leftStickX - 0.5) < 0.001)
    #expect(abs(decoded.leftTrigger - 0.75) < 0.001)
  }

}
