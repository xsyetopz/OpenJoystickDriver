import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct BluetoothAccessStateTests {
  @Test
  func statusCarriesBluetoothAccessThroughJSON() throws {
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
  func statusWithoutBluetoothAccessDecodesAsNil() throws {
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
  func onlyUndecidedOrDeniedAccessNeedsStep() {
    #expect(BluetoothAccessState.notAsked.needsStep)
    #expect(BluetoothAccessState.denied.needsStep)
    #expect(!BluetoothAccessState.granted.needsStep)
    #expect(!BluetoothAccessState.restricted.needsStep)
    #expect(!BluetoothAccessState.unavailable.needsStep)
  }
}
