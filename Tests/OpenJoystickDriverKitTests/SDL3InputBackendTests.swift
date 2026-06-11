import Testing

@testable import OpenJoystickDriverKit

struct SDL3InputBackendTests {
  @Test
  func mapsCanonicalSDLGamepadButtonsToOJDButtons() {
    let previous = SDL3GamepadSnapshot.neutral(vendorID: 1133, productID: 49693)
    var current = previous
    current.buttons = [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder,
      .leftStick, .rightStick, .back, .start, .guide,
    ]

    let events = SDL3GamepadMapper.events(previous: previous, current: current)

    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.buttonPressed(.b)))
    #expect(events.contains(.buttonPressed(.x)))
    #expect(events.contains(.buttonPressed(.y)))
    #expect(events.contains(.buttonPressed(.leftBumper)))
    #expect(events.contains(.buttonPressed(.rightBumper)))
    #expect(events.contains(.buttonPressed(.leftStick)))
    #expect(events.contains(.buttonPressed(.rightStick)))
    #expect(events.contains(.buttonPressed(.back)))
    #expect(events.contains(.buttonPressed(.start)))
    #expect(events.contains(.buttonPressed(.guide)))
  }

  @Test
  func mapsSDLDpadToCanonicalDpadDirection() {
    let previous = SDL3GamepadSnapshot.neutral(vendorID: 1133, productID: 49693)
    var current = previous
    current.buttons = [.dpadUp, .dpadRight]

    let events = SDL3GamepadMapper.events(previous: previous, current: current)

    #expect(events == [.dpadChanged(.northEast)])
  }

  @Test
  func mapsSDLGamepadAxesToOJDNormalizedState() {
    let previous = SDL3GamepadSnapshot.neutral(vendorID: 1, productID: 2)
    var current = previous
    current.axes[.leftX] = 32767
    current.axes[.leftY] = -32768
    current.axes[.rightX] = -16384
    current.axes[.rightY] = 16384
    current.axes[.leftTrigger] = 32767
    current.axes[.rightTrigger] = 16384

    let events = SDL3GamepadMapper.events(previous: previous, current: current)

    #expect(events.contains(.leftStickChanged(x: 1.0, y: -1.0)))
    #expect(events.contains(.rightStickChanged(x: -0.5, y: 0.50001526)))
    #expect(events.contains(.leftTriggerChanged(1.0)))
    #expect(events.contains(.rightTriggerChanged(0.50001526)))
  }

  @Test
  func filtersOpenJoystickDriverVirtualDevicesBeforeOpening() {
    let ojdVirtual = SDL3DeviceIdentity(
      vendorID: 0x4F4A,
      productID: 0x4448,
      name: "OpenJoystickDriver Virtual Gamepad",
      serial: nil,
      guid: nil,
      locationID: nil
    )
    let virtualSerial = SDL3DeviceIdentity(
      vendorID: 0x045E,
      productID: 0x02EA,
      name: "Xbox Wireless Controller",
      serial: VirtualDeviceIdentityConstants.driverKitSerialNumber,
      guid: nil,
      locationID: nil
    )
    let virtualLocation = SDL3DeviceIdentity(
      vendorID: 0x045E,
      productID: 0x02EA,
      name: "Xbox Wireless Controller",
      serial: nil,
      guid: nil,
      locationID: VirtualDeviceIdentityConstants.driverKitLocationID
    )
    let physicalF310 = SDL3DeviceIdentity(
      vendorID: 1133,
      productID: 49693,
      name: "Logitech Gamepad F310",
      serial: nil,
      guid: nil,
      locationID: nil
    )

    #expect(ojdVirtual.isOpenJoystickDriverVirtualDevice)
    #expect(virtualSerial.isOpenJoystickDriverVirtualDevice)
    #expect(virtualLocation.isOpenJoystickDriverVirtualDevice)
    #expect(!physicalF310.isOpenJoystickDriverVirtualDevice)
  }
}
