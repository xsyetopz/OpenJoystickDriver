import CoreBluetooth
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct Switch2BluetoothLECentralAccessTests {
  @Test(
    arguments: [
      (CBManagerAuthorization.notDetermined, BluetoothAccessState.notAsked),
      (.denied, .denied), (.restricted, .restricted), (.allowedAlways, .granted),
    ]
  )
  func theAuthorizationMapsToTheAccessState(
    pair: (CBManagerAuthorization, BluetoothAccessState)
  ) {
    let central = Switch2BluetoothLECentral(
      hub: Switch2BluetoothLEHub(),
      authorization: { pair.0 },
      makeManager: { _, _ in nil }
    )
    #expect(central.accessState == pair.1)
  }

  @Test
  func theAccessControlRequestsThroughTheCentral() {
    let central = Switch2BluetoothLECentral(
      hub: Switch2BluetoothLEHub(),
      authorization: { .notDetermined },
      makeManager: { _, _ in nil }
    )
    let control = BluetoothAccessControl(central: central)
    #expect(control.state() == .notAsked)
    #expect(control.request() == .notAsked)
    central.stop()
  }
}
