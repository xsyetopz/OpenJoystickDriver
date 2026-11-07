## MODIFIED Requirements

### Requirement: REQ-24 Original Xbox One controller is listed

The USB transport adapter MUST take the identity of an XboxUSBDevice service (`idVendor`, `idProduct`, `locationID`, and the strings) from its parent `IOUSBHostDevice`, so that an original Xbox One controller (`045E:02D1`, model 1537) is listed by `ojd controller list` and bound to `XboxGIP` when the extension is active.
The route of the controller is `ExtensionOwned`, set by its record, and the extension match list that holds `045E:02D1` is generated from the records with that route. `docs/testing/xbox-one-02d1.md` MUST record the evidence and say that the fix is not verified on hardware.

#### Scenario: Extension active

- **WHEN** a `045E:02D1` controller is connected and the XboxUSBDevice extension is active
- **THEN** the transport reads its identity from the parent `IOUSBHostDevice` and `DeviceManager` claims it on interface 0 for `XboxGIP` (`dextServiceTakesIdentityFromParentUSBDevice`, `dextRouteServiceIsClaimedOnInterfaceZero`)
- **AND** the listing is not confirmed on hardware

#### Scenario: Service without a parent

- **WHEN** an extension service has no parent `IOUSBHostDevice` and no scalar `idVendor` and `idProduct` of its own
- **THEN** the transport lists no device for it (`dextServiceWithoutParentYieldsNoDevice`)

## ADDED Requirements

### Requirement: REQ-25 A configuration descriptor that cannot be read is named, not retried without bound

When the configuration descriptor read of a raw-USB device fails, `DeviceManager` MUST give the failure one named outcome and log it once.

#### Scenario: Another program holds the controller

- **WHEN** a raw-USB controller's descriptor read is refused with `accessDenied` and the host reports an exclusive owner
- **THEN** the service is acknowledged and left unclaimed with the unbound reason `DeviceInUse`, and each detection poll reads the owner, not the descriptor
- **AND** the descriptor is read once across later polls and the device is recorded with `DeviceInUse` (`deniedDescriptorReadIsAcknowledgedAndReadOnce`, `theDetectionLoopReadsAHeldDeviceOnceAcrossPolls`)
- **AND** the device is listed with the reason's sentence (`controllersPageListsAnUnservedDeviceWithTheSentenceOfItsReason`, `aDeviceHeldByAnotherProgramIsExplainedInHumanOutputOnly`)

#### Scenario: The owner releases the device

- **WHEN** the host reports no owner for a held service
- **THEN** the service is admitted again, and a changed owner keeps it held (`heldServiceIsAdmittedAgainOnlyWhenItsHolderGoesAway`)

#### Scenario: The owner can no longer be read

- **WHEN** the owner read of a held service fails
- **THEN** the reason changes to `ConfigurationUnreadable` and the owner is not read again (`anUnreadableOwnerEndsTheWatchWithTheUnreadableReason`)

#### Scenario: A refusal with no owner

- **WHEN** the read is refused and the host reports no owner, or the owner cannot be read
- **THEN** the service is acknowledged and left unclaimed with the reason `ConfigurationUnreadable`
- **AND** the device is recorded with `ConfigurationUnreadable` and stays acknowledged (`deniedReadWithoutAnOwnerIsUnreadableUntilReenumeration`)

#### Scenario: Another read failure

- **WHEN** the read fails with another error on every poll
- **THEN** the descriptor is read again on the next poll, for at most `usbConfigurationReadAttempts` polls in a row, each attempt logged with its number
- **AND** it is read `usbConfigurationReadAttempts` times, then the device is recorded with `ConfigurationUnreadable` and not read again (`otherReadFailuresAreBoundedThenNamed`)
- **AND** a later successful read resets the count (`aSuccessfulReadResetsTheFailedReadCount`)

#### Scenario: Stop during the owner read

- **WHEN** the manager stops while the owner read of a refused device is in flight
- **THEN** no held service or unbound record is left behind (`stopDuringTheOwnerReadLeavesNoHold`)

### Requirement: REQ-27 An unreadable service shows the sentence of its reason

The Controllers page and `ojd status` MUST show the sentence of the reason a service is left unclaimed. A service left unclaimed is read again only when it re-enumerates or, for `DeviceInUse`, when its owner goes away.

#### Scenario: Sentence of the reason

- **WHEN** a service is left unclaimed with `DeviceInUse` or `ConfigurationUnreadable`
- **THEN** the Controllers page and `ojd status` show `ui.controllers.deviceInUse` (close the program or reconnect) or `ui.controllers.configurationUnreadable` (reconnect)

#### Scenario: Read again

- **WHEN** a service is left unclaimed
- **THEN** it is read again only when it re-enumerates or, for `DeviceInUse`, when its owner goes away
