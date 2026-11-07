# Tasks: Unique Virtual Identity

## Working Agreements

- Docs state current behavior with no history words. History goes in `CHANGELOG.md`.
- Before writing a function, run the duplication check; before refactoring a file, list its clones.
- A task is done only after its Verify command ran in the session that closes it.
- After the group tests: `just check` once.

## 1. Tests First

Owns: `Tests/OpenJoystickDriverKitTests/Device/LogicalControllerIDTests.swift`, `Tests/OpenJoystickDriverKitTests/HID/PhysicalHIDPolicyTests.swift`.
Depends: none.
Verify: `swift test --filter LogicalControllerIDTests`.

- [ ] 1.1 `sameSerialControllersGetDistinctVirtualIdentities`: build two `LogicalControllerID(vendorID: 0x057E, productID: 0x2009, serialNumber: "000000000001", locationID: ...)` with different locations and assert different serials and LocationIDs. This is the reproduction of the report without hardware.
- [ ] 1.2 `firstSameSerialControllerKeepsThePlainIdentity`: the first pad's serial is `OpenJoystickDriver-UserSpace:d7b8ce84d34c45a2`.
- [ ] 1.3 `identitiesStayStableWhileBothAreConnected`, `stoppedControllerReleasesItsIdentity`, `locationIDCollisionResolvesToTheNextFreeValue` and `locationIDResolutionIsDeterministic`. Find two keys with one 16-bit hash by search in the test setup, with the found strings written into the test.
- [ ] 1.4 Keep `virtualIdentityOfASerialControllerSurvivesAPortChange` and the no-serial tests green.

## 2. Registry and Dispatcher

Owns: `Sources/OpenJoystickDriverKit/HID/PhysicalHIDTrackingStateMachine.swift`, `Sources/OpenJoystickDriverKit/Output/Backends/`, `Sources/OpenJoystickDriverMacOSPlatform/Output/IOHIDVirtualDevicePublisher.swift`.
Depends: 1.
Verify: `swift test --filter UserSpaceOutputDispatcher`, `swift test --filter IOHIDVirtualDevicePublisherTests`.

- [ ] 2.1 Add `VirtualIdentityRegistry` (design D1 to D4) beside `UserSpaceVirtualDeviceConstants`.
- [ ] 2.2 `UserSpaceOutputDispatcher` reserves in the creation path and releases in `controllerDidStop`; `createDevice` takes the resolved identity.
- [ ] 2.3 `IOHIDVirtualDevicePublisher` uses the passed identity; update `IOHIDVirtualDevicePublisherTests` (lines 227-231) and `PhysicalHIDPolicyTests` (line 154) to the new call.
- [ ] 2.4 Find every caller of `serialNumber(for:)` and `locationID(for:)` before changing them; the physical-device filter (`isOJDUserSpaceLocationID`, line 35) still sees only the OJD namespace.

## 3. Docs

Owns: `CHANGELOG.md`, `wiki/Known-Issues.md`.
Depends: 2.
Verify: `markdownlint CHANGELOG.md wiki/Known-Issues.md`.

- [ ] 3.1 Add under `## [Unreleased]` / `### Fixed` in `CHANGELOG.md`: two controllers with the same VID:PID and USB serial, such as two `057E:2009` pads, no longer share one virtual controller.
- [ ] 3.2 Add a short section to `wiki/Known-Issues.md` (near "Rumble Does Not Reach Two Identical Controllers", line 17) saying that same-serial pads get separate virtual controllers and that the second pad's identity follows its port.

## Hardware Checks (Testers)

Anyone with two pads that report one USB serial can run this. Not run yet.

- [ ] H1 Connect two same-serial pads (for example a G50S and a ZD O+ in Switch mode, plus a Cyclone 2 dongle as a third). Run `ioreg -l -w0 -r -c IOUSBHostDevice` to see `idVendor`, `idProduct`, `USB Serial Number` and `locationID`, and check that `GCController.controllers()` (or System Settings > Game Controllers) lists every pad.
