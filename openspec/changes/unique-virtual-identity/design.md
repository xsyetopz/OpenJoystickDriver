## Context

- `serialNumber(for:)` and `locationID(for:)` are pure functions of a `LogicalControllerID` (`PhysicalHIDTrackingStateMachine.swift:83-95`). Both hash `stableKey(for:)`, which is `VID:PID:serial:loc:interface` where `loc` is empty unless the serial is empty (lines 103-113). The location is dropped deliberately so a serial pad keeps its identity on another port (`LogicalControllerIDTests.swift:146-166`).
- A pure function cannot know that another pad holds the same key. Two same-serial pads therefore give the same serial and the same 16-bit LocationID. The 16-bit truncation (`h & 0xFFFF`, line 91) also lets two different keys collide.
- The static functions are called from `IOHIDVirtualDevicePublisher.swift:119` and the serial from the same file's properties, and from the tests in `IOHIDVirtualDevicePublisherTests.swift:227-231` and `PhysicalHIDPolicyTests.swift:154`.
- `UserSpaceOutputDispatcher` owns the live virtual devices: `entries`, `creationTasks` and `lifecycleGenerations` are keyed by `LogicalControllerID` (`UserSpaceOutputDispatcher.swift:27-35`), it calls the publisher through `backendFactory` (lines 56-67) and removes an entry in `controllerDidStop` (line 88).

## Decisions

### D1: The Dispatcher Owns the Connected Identity Set

The dispatcher holds a small value type, `VirtualIdentityRegistry`, inside its existing registry lock (`withRegistry`). It maps each connected `LogicalControllerID` to a resolved `(serial, locationID)`. The dispatcher reserves the identity when creation starts (so two pads that connect together cannot both read an empty set) and releases it in `controllerDidStop`. The registry is a value type with no I/O so unit tests drive it directly.

The publisher protocol takes the resolved identity as an argument to `createDevice`; `IOHIDVirtualDevicePublisher` stops calling the static functions and uses the passed values. The static functions stay as the pure "plain key" step the registry starts from.

### D2: Qualified Key Only on Conflict

The registry computes the plain key. If a different connected `LogicalControllerID` already holds the same plain key, the newcomer's key adds its location ID (`VID:PID:serial:loc:interface`). Controllers with unique serials, and the first controller of a shared serial, keep the plain key.

### D3: Ordering and Reconnect

- The first controller to reserve keeps the plain key. "First" means first to start creation; for pads plugged in together it is the order the dispatcher receives them, which the registry serialises.
- While both are connected, neither identity changes. A pad is not renamed when the other leaves.
- A pad that took the qualified key keeps it until it stops. If the first pad leaves and returns while the second stays, the returning pad finds the plain key free and takes it again.
- If both leave and return in the opposite order, the first to return takes the plain key, so macOS may see the two virtual controllers swap serials across a full reconnect. A qualified key includes the port, so the second pad's identity follows the port. This is the least that distinguishes two pads that share a serial; a pad with a unique serial never swaps.
- Open: whether the plain key should prefer the lower location ID rather than the first to connect. First-to-connect is chosen because it needs no extra knowledge and matches the report ("the first pad keeps the plain key").

### D4: LocationID Collisions

The 16-bit value from the key hash is the start. If another connected controller with a different key holds it, the registry steps to the next value, wrapping within 16 bits and skipping 0 and 1 (the existing rule at line 92-93). Controllers with the same key never share a LocationID because of D2, so the step only fires for a true hash collision. Stepping is deterministic for a given connection order.

### D5: Serials Stay Hashed

The virtual serial remains `serialPrefix` plus a hash (line 85), so the physical serial is not exposed.

## Risks

- The serial of the first pad is unchanged from the value in the report, so existing per-device settings in apps keep matching it. The second pad gets a new value.
- The registry must release on every stop path. `controllerDidStop` is the only removal point for `entries` (line 88-100), and the test `stoppedControllerReleasesItsIdentity` covers it.
