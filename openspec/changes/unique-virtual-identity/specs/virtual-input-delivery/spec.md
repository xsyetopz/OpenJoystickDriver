## ADDED Requirements

### Requirement: Connected Controllers Have Distinct Virtual Identities

The virtual serial number and the virtual LocationID of each connected logical controller SHALL differ from those of every other connected logical controller, including controllers that report the same VID:PID and the same USB serial number.

#### Scenario: Two Pads Share a Serial

- **WHEN** two logical controllers with `057E:2009`, serial `000000000001` and different location IDs are connected
- **THEN** their virtual serials differ and their virtual LocationIDs differ (`sameSerialControllersGetDistinctVirtualIdentities`)

#### Scenario: First Pad Keeps the Plain Identity

- **WHEN** the first of two same-serial controllers is connected alone
- **THEN** its virtual serial is `OpenJoystickDriver-UserSpace:d7b8ce84d34c45a2`, the hash of `1406:8201:000000000001::` (`firstSameSerialControllerKeepsThePlainIdentity`)

#### Scenario: Identities Hold While Both Are Connected

- **WHEN** the second same-serial controller is connected and the first is still connected
- **THEN** the first keeps its identity, and the second's identity does not change on later events (`identitiesStayStableWhileBothAreConnected`)

### Requirement: A Unique Serial Keeps a Port-Independent Identity

A controller whose VID:PID:serial key no other connected controller holds SHALL get the same virtual serial and LocationID on every port.

#### Scenario: Unique Serial Moves Port

- **WHEN** a controller with a unique serial reconnects at another location
- **THEN** its virtual serial and LocationID are unchanged (`virtualIdentityOfASerialControllerSurvivesAPortChange`, existing)

#### Scenario: Released Key Returns to the Plain Form

- **WHEN** the controller that held the plain key stops and a same-serial controller connects later
- **THEN** the newcomer takes the plain key (`stoppedControllerReleasesItsIdentity`)

### Requirement: LocationID Collisions Resolve Deterministically

When two different identity keys of connected controllers hash to the same 16-bit LocationID, the later controller SHALL get the next free LocationID in the OJD namespace, wrapping within the 16 bits and skipping 0 and 1. The same sequence of connections SHALL give the same values.

#### Scenario: Two Keys Collide

- **WHEN** two connected controllers with different keys hash to one 16-bit value
- **THEN** the second gets the next free value and the first is unchanged (`locationIDCollisionResolvesToTheNextFreeValue`)

#### Scenario: Same Order, Same Result

- **WHEN** the same connections repeat in the same order
- **THEN** the values repeat (`locationIDResolutionIsDeterministic`)
