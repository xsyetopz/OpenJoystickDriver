import CoreBluetooth
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// Counts the managers that a central asks for, which is what shows the Bluetooth prompt.
private final class ManagerCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  var created: Int { lock.withLock { value } }
  func increment() { lock.withLock { value += 1 } }
}

struct Switch2BluetoothLECentralLaunchTests {
  private func makeCentral(
    authorization: CBManagerAuthorization,
    counter: ManagerCounter
  ) -> Switch2BluetoothLECentral {
    Switch2BluetoothLECentral(
      hub: Switch2BluetoothLEHub(),
      authorization: { authorization },
      makeManager: { _, _ in
        counter.increment()
        return nil
      }
    )
  }

  @Test(arguments: [CBManagerAuthorization.notDetermined, .denied, .restricted])
  func launchCreatesNoManagerWhileBluetoothIsNotGranted(authorization: CBManagerAuthorization) {
    let counter = ManagerCounter()
    let central = makeCentral(authorization: authorization, counter: counter)
    central.start()
    central.stop()
    #expect(counter.created == 0)
  }

  @Test
  func launchCreatesTheManagerWhenBluetoothIsAlreadyGranted() {
    let counter = ManagerCounter()
    let central = makeCentral(authorization: .allowedAlways, counter: counter)
    central.start()
    central.stop()
    #expect(counter.created == 1)
  }

  @Test
  func theUserRequestCreatesTheManagerWhileBluetoothIsNotDetermined() {
    let counter = ManagerCounter()
    let central = makeCentral(authorization: .notDetermined, counter: counter)
    central.start()
    central.requestAccessAndStart()
    central.stop()
    #expect(counter.created == 1)
  }
}
