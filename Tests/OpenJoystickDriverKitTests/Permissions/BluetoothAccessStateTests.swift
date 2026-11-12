import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct BluetoothAccessStateTests {
  @Test
  func statusCarriesTheBluetoothAccessThroughJSON() throws {
    let payload = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      bluetoothAccess: .notAsked
    )
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
    #expect(decoded.bluetoothAccess == .notAsked)
  }

  @Test
  func aStatusWithoutBluetoothAccessDecodesAsNil() throws {
    let payload = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: []
    )
    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
    #expect(decoded.bluetoothAccess == nil)
  }

  @Test
  func onlyAnUndecidedOrDeniedAccessNeedsAStep() {
    #expect(BluetoothAccessState.notAsked.needsStep)
    #expect(BluetoothAccessState.denied.needsStep)
    #expect(!BluetoothAccessState.granted.needsStep)
    #expect(!BluetoothAccessState.restricted.needsStep)
    #expect(!BluetoothAccessState.unavailable.needsStep)
  }
}
