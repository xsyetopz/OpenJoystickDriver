import IOKit
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverMacOSPlatform

struct HIDDeviceStreamMappingTests {
  @Test
  func iohidTransportPropertyMapsToHostTransport() {
    #expect(HIDDeviceStream.hostTransport(forTransportProperty: "USB") == .usb)
    #expect(HIDDeviceStream.hostTransport(forTransportProperty: "Bluetooth") == .bluetoothClassic)
    #expect(
      HIDDeviceStream.hostTransport(forTransportProperty: "BluetoothLowEnergy") == .bluetoothLE
    )
    for unknown in [nil, "", "SPI", "bluetooth"] {
      #expect(HIDDeviceStream.hostTransport(forTransportProperty: unknown) == nil)
    }
  }

  @Test
  func transportStringIOKitPublishesForBluetoothLEPadMapsToBluetoothLE() {
    #expect(
      HIDDeviceStream.hostTransport(forTransportProperty: "Bluetooth Low Energy") == .bluetoothLE
    )
  }

  @Test
  func bluetoothLEHubReportsIOHIDBluetoothLowEnergyTransport() {
    #expect(
      Switch2BluetoothLEProfile.hidTransportProperty == kIOHIDTransportBluetoothLowEnergyValue
    )
    #expect(
      HIDDeviceStream.hostTransport(
        forTransportProperty: Switch2BluetoothLEProfile.hidTransportProperty
      ) == .bluetoothLE
    )
  }

  @Test
  func onlyDeniedInitialOpensEndHIDStream() {
    func failure(_ result: IOReturn) -> PhysicalHIDFailure? {
      guard
        case .accessFailure(let failure) = HIDDeviceStream.accessFailure(
          forInitialOpenResult: result
        )
      else { return nil }
      return failure
    }
    #expect(failure(kIOReturnNotPermitted) == .hostStatus(kIOReturnNotPermitted))
    #expect(failure(kIOReturnNotPrivileged) == .hostStatus(kIOReturnNotPrivileged))
    #expect(HIDDeviceStream.accessFailure(forInitialOpenResult: kIOReturnSuccess) == nil)
    #expect(HIDDeviceStream.accessFailure(forInitialOpenResult: kIOReturnExclusiveAccess) == nil)
  }

  @Test
  func iokitStatusCodesMapToNamedFailures() {
    #expect(PhysicalHIDFailure(ioReturn: kIOReturnTimeout) == .timedOut)
    #expect(PhysicalHIDFailure(ioReturn: kIOReturnBusy) == .busy)
    #expect(PhysicalHIDFailure(ioReturn: kIOReturnNotResponding) == .notResponding)
    #expect(PhysicalHIDFailure(ioReturn: kIOReturnUnsupported) == .declined)
    #expect(PhysicalHIDFailure(ioReturn: IOReturn(bitPattern: 0xE000_404F)) == .declined)
    // A DualShock 3 clone's stalled 0xEF feature read returns `kUSBHostReturnPipeStalled`.
    #expect(PhysicalHIDFailure(ioReturn: IOReturn(bitPattern: 0xE000_5000)) == .declined)
    for code in [
      kIOReturnNotOpen, kIOReturnNoDevice, kIOReturnAborted, kIOReturnNotPermitted,
      kIOReturnExclusiveAccess, kIOReturnError,
    ] {
      #expect(PhysicalHIDFailure(ioReturn: code) == .hostStatus(code))
    }
  }
}
