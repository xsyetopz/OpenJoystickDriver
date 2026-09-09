# Implementation status

OpenJoystickDriver 0.5 uses a persistent application runtime. The signed app host owns controller
processing, virtual output, login registration, permission state, and the authenticated local RPC
endpoint. No helper daemon or LaunchAgent is packaged.

Quit requests share one asynchronous teardown and leave the app stopped. TCC
reopen remains a native system action. Profile-library versions other than the
current schema return a typed unsupported-version error; loading an empty
unsupported library does not rewrite its bytes or discard unknown fields.

The CLI and signed application runtime report authoritative Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. Input Monitoring gates physical controller reads. Accessibility gates virtual-HID publication. OJD never resets TCC.

Controller records remain generated data, while shared protocol behavior remains
in code. Event normalization removes duplicate and contradictory input, and
output dispatch is concurrent across devices and ordered within each virtual device.
Per-device host sessions validate control requests and decode Sony/Nintendo USB
initialization and rumble. Codec tests do not establish signed consumer binding
or hardware delivery; see [wire protocols](wire-protocols.md).
Process and RPC calls have deadlines; buffers and
frames are bounded; current-session logs have typed paths.

`OpenJoystickDriverUSB` exposes one controller-neutral raw USB API. Accessible
vendor-specific interfaces use app-side IOUSBHost. The SwifterKit adapter talks
to the USBDriverKit extension only for an observed DEXT-owned service or a model
covered by OJD's restricted production entitlement. That extension is not a
consumer virtual-controller path. SwifterKit generates its native project at
build time, while this repository authors the USB configuration. Generation and
unsigned native builds are validated locally. Signed activation, macOS approval,
and physical USB delivery require an appropriately provisioned Mac and recorded
evidence.
The current issue-by-issue acceptance state is recorded in the
[controller issue audit](issue-audit.md).

## Platform boundaries

On macOS 10.15–14, physical HID access uses IOHID and consumer virtual output
uses `IOHIDUserDevice`. On macOS 15 and later, those roles use CoreHID. Raw USB
uses IOUSBHost/USBDriverKit across both ranges. `OpenJoystickDriverUSB` hides the
USB host transport from parsers and application callers. OJD does not retain a
libusb fallback.
