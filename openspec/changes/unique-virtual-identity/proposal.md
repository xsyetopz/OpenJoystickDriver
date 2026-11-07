## Why

Two wired pads that report the same VID:PID and the same USB serial get the same virtual serial and the same virtual LocationID, so macOS merges them and `GCController.controllers()` lists one pad too few.

- Report (Discord, OJD 0.6.0-alpha.1, commit `3552be9`): a Thunderobot G50S and a ZD O+ Excellence in Switch mode both enumerate as `057E:2009` "Pro Controller" with USB serial `000000000001`. Both get `OpenJoystickDriver-UserSpace:d7b8ce84d34c45a2`. A third pad on `057E:2009` without a serial (GameSir Cyclone 2 dongle) works. Moving ports does not help; connecting one pad over Bluetooth is a workaround.
- Cause: `UserSpaceVirtualDeviceConstants.stableKey(for:)` adds the location ID to the hash input only when the serial is empty (`Sources/OpenJoystickDriverKit/HID/PhysicalHIDTrackingStateMachine.swift:103-113`, the `loc` line). `serialNumber(for:)` (line 83) and `locationID(for:)` (line 89) both hash that key, so two pads with one serial share both values. FNV-1a of `1406:8201:000000000001::` (0x057E = 1406, 0x2009 = 8201, serial, empty location, empty interface) is `d7b8ce84d34c45a2`, the value in the report; a unit test reproduces it without hardware.
- `IOHIDVirtualDevicePublisher` reads both values for the device it creates (`Sources/OpenJoystickDriverMacOSPlatform/Output/IOHIDVirtualDevicePublisher.swift:119`).
- The `ojd-support-report.txt` the maintainer holds (build 1.19.64, macOS 27.2.0) shows one Bluetooth Xbox Wireless Controller (`045E:02E0`) and no `057E:2009` pad. It is not evidence for this bug. The support report also leaves out serials and HID locations on purpose, so it could not show the shared serial anyway.

## What Changes

- A controller whose VID:PID:serial key is already held by another currently connected logical controller adds its location ID to its key. The first controller keeps the plain key.
- A pad with a unique serial keeps a port-independent identity (`LogicalControllerIDTests.swift:146-166` already asserts this and stays).
- Two different keys whose 16-bit LocationIDs collide resolve deterministically to the next free value among connected devices.
- The set of connected identities lives with the owner of the live virtual devices, `UserSpaceOutputDispatcher` (see design).
- Docs: the user wiki states that two same-serial pads get distinct virtual controllers. `CHANGELOG.md` gets a Fixed line.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `virtual-input-delivery`: adds the requirements that each connected controller has a distinct virtual serial and LocationID.

## Impact

- `Sources/OpenJoystickDriverKit/HID/PhysicalHIDTrackingStateMachine.swift` (`UserSpaceVirtualDeviceConstants`), `Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/UserSpaceOutputDispatcher.swift`, `Sources/OpenJoystickDriverKit/Output/Backends/VirtualHIDDevicePublisher.swift`, `Sources/OpenJoystickDriverMacOSPlatform/Output/IOHIDVirtualDevicePublisher.swift`.
- Tests: `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift`, `Tests/OpenJoystickDriverKitTests/HID/PhysicalHIDPolicyTests.swift`, `Tests/OpenJoystickDriverMacOSPlatformTests/IOHIDVirtualDevicePublisherTests.swift`, `Tests/OpenJoystickDriverKitTests/Output/Backends/`.
- `CHANGELOG.md`, `wiki/Known-Issues.md`.
- Separate change `zd-o-plus-switch-mode` covers why the ZD O+ shows up as `057E:2009`.
