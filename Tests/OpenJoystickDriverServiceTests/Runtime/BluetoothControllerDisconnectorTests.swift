import Foundation
import IOKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

struct BluetoothControllerDisconnectorTests {
  @Test
  func successfulCloseReturnsThePlatformResult() async {
    let disconnector = BluetoothControllerDisconnector { address, _ in
      .init(
        status: address == "AA:BB:CC:DD:EE:FF" ? kIOReturnSuccess : kIOReturnNotFound,
        isConnected: false
      )
    }

    let result = await disconnector.disconnect(
      address: "AA:BB:CC:DD:EE:FF",
      timeoutNanoseconds: 1_000_000_000
    )

    #expect(result == .disconnected)
  }

  @Test
  func timeoutReturnsBeforeALateCloseCompletes() async {
    let releaseClose = DispatchSemaphore(value: 0)
    let disconnector = BluetoothControllerDisconnector { _, _ in
      releaseClose.wait()
      return .init(status: kIOReturnSuccess, isConnected: false)
    }

    let result = await disconnector.disconnect(
      address: "AA:BB:CC:DD:EE:FF",
      timeoutNanoseconds: 10_000_000
    )

    // The close is still blocked here, so only the timeout can have produced the result.
    #expect(result == .timedOut)
    releaseClose.signal()
  }

  @Test
  func closeSuccessRequiresDisconnectedConfirmation() async {
    let disconnector = BluetoothControllerDisconnector { _, _ in
      .init(status: kIOReturnSuccess, isConnected: true)
    }

    let result = await disconnector.disconnect(
      address: "AA:BB:CC:DD:EE:FF",
      timeoutNanoseconds: 1_000_000_000
    )

    #expect(result == .stillConnected)
  }

  @Test
  func closeFailureRetainsIOReturn() async {
    let disconnector = BluetoothControllerDisconnector { _, _ in
      .init(status: kIOReturnNotPermitted, isConnected: true)
    }

    let result = await disconnector.disconnect(
      address: "AA:BB:CC:DD:EE:FF",
      timeoutNanoseconds: 1_000_000_000
    )

    #expect(result == .failed(kIOReturnNotPermitted))
  }
}
