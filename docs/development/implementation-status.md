# Implementation status

OpenJoystickDriver 0.5 uses a persistent application runtime. The signed app host owns controller
processing, virtual output, login registration, permission state, and the authenticated local RPC
endpoint. No helper daemon or LaunchAgent is packaged.

The CLI and signed application runtime report authoritative Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. Input Monitoring gates physical controller reads. Accessibility gates compatibility `IOHIDUserDevice` publication. OJD never resets TCC.

Controller records remain generated data, while shared protocol behavior remains
in code. Event normalization removes duplicate and contradictory input, and
output dispatch is concurrent. Process and RPC calls have deadlines; buffers and
frames are bounded; current-session logs have typed paths.

The optional DriverKit integrity relay uses the SwifterKit adapter in
`OpenJoystickDriverRelay`; it is not a consumer virtual-controller path.
SwifterKit generates its native project at build time, while this repository
authors and tests the relay's Swift configuration and report policy. Generation
and unsigned native builds are validated locally. Signed activation, macOS
approval, and physical HID delivery require an appropriately provisioned Mac and
recorded evidence.
The current issue-by-issue acceptance state is recorded in the
[controller issue audit](issue-audit.md).

## HID-boundary uncertainty

The authored relay allowlists HID output reports. SwifterKit's generated native
runtime rejects feature and other host-report types synchronously before reading,
allocating, or enqueuing their payloads. OJD does not patch generated native code
or retain a fallback boundary. Signed activation and a target-macOS HID-boundary
check remain required runtime evidence.
