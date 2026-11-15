# Unconfigured Xbox USB Device Bootstrap

An Xbox One `045E:02D1` can enumerate as an `IOUSBHostDevice` in configuration 0
without publishing any `IOUSBHostInterface`. OJD reserves the Microsoft models in
its existing entitlement list for its interface-scoped extension. The extension
matches configuration 1, interface 0, class 255/subclass 71/protocol 208. Without
that interface, it cannot attach; without a selected transport, the pipeline's
configuration-before-claim option cannot run.

The operator reported that an independent libusb SET_CONFIGURATION(1) caused
interfaces to appear, after which OJD discovered the device and reached the
separate startup/transfer failures discussed in
[PR #68](https://github.com/xsyetopz/OpenJoystickDriver/pull/68). This is reporter
evidence, not a fresh configuration-0 hardware test of the bootstrap below.

## Bootstrap Contract

Before selecting routes, the facade may prepare an existing, catalogued raw-USB
model reserved for the extension, only when both discovery providers answered
and no extension is observed for that same vendor/product/location. Failed
extension discovery is not treated as evidence that no extension owns the device.

Preparation opens only the device-level control channel, without seize, reset,
interface claim, alternate-setting selection or GIP packets. The native helper:

1. Restricts preparation to the existing Microsoft entitlement tuples and the
   exact registry service ID; it never substitutes a reconnected device.
2. Skips a nonzero registry configuration, an existing interface, or another
   process's exclusive device ownership before opening a device client.
3. Validates configuration 1's descriptor with the existing descriptor parser and
   bundled GIP interface contract, including interrupt IN and OUT endpoints.
4. Reads live GET_CONFIGURATION with a one-second completion timeout. A missing
   registry property is not assumed to prove configuration 0.
5. Rechecks device state and ownership, then selects configuration 1 only after
   the live read returned zero, with `matchInterfaces: true`.
6. Releases the device client so the normal extension route can proceed.

The facade re-reads the extension list after a successful write. Delayed matching
can settle on a later normal poll; it does not fall back to direct data input.
Attempts are limited to once per registry service every two seconds, including
concurrent polls. Failure leaves other controller discovery intact and is logged
once per service. This does not activate an inactive system extension.

## Validation Boundary

Tests use injected operations and fake discovery providers: they do not configure
attached hardware. They cover state and descriptor checks, live configuration
readback, ownership/interface races, failure behavior, retry limiting, concurrent
polls and publication of an extension-owned route after bootstrap.

A signed tester still needs fresh-plug tests with no external script: confirm
configuration 0 becomes 1, interface 0 appears, the extension attaches, and the
transport fixes from #68 then reach input. Also test an already configured unit,
an inactive extension, another USB consumer, unplug/replug and failed configuration.
No fresh configuration-0 result is claimed here. The game-tested external bridge
and the installed signed app were not modified during this work.
