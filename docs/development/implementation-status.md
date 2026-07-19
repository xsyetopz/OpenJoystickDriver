# Implementation status

OpenJoystickDriver 0.5 uses a persistent main-app runtime. The app owns the UI, controller processing, virtual output, login registration, permission state, and authenticated local RPC endpoint. No helper daemon or LaunchAgent is packaged.

The CLI and menu app report authoritative Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. Input Monitoring gates physical controller reads. Accessibility gates compatibility `IOHIDUserDevice` publication. OJD never resets TCC.

Controller records remain generated data. Shared protocol behavior remains in code. Event normalization removes duplicate and contradictory input. Output dispatch is concurrent. Process and RPC calls have deadlines, buffers and frames are bounded, and current-session logs have typed paths.

The optional DriverKit integrity relay is implemented through the SwifterKit adapter
in `OpenJoystickDriverRelay`; it is not a consumer virtual-controller path.
SwifterKit generates its native project at build time, while the relay's Swift
configuration and report policy remain authored and tested in this repository.
Generation and unsigned native builds are validated locally; signed activation,
macOS approval, and physical HID delivery still require an appropriately
provisioned Mac and recorded evidence. Hardware claims require recorded evidence.
The current issue-by-issue acceptance state is recorded in the
[controller issue audit](issue-audit.md).

### HID-boundary uncertainty

The authored relay allowlists HID output reports. SwifterKit's generated native
runtime rejects feature and other host-report types synchronously before reading,
allocating, or enqueuing their payloads. OJD does not patch generated native code
or retain a fallback boundary. Signed activation and a target-macOS HID-boundary
check remain required runtime evidence.
