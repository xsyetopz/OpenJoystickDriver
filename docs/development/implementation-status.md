# Implementation status

OpenJoystickDriver 0.5 uses a persistent main-app runtime. The app owns the UI, controller processing, virtual output, login registration, permission state, and authenticated local RPC endpoint. No helper daemon or LaunchAgent is packaged.

The CLI and menu app report authoritative Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. Input Monitoring gates physical controller reads. Accessibility gates compatibility `IOHIDUserDevice` publication. OJD never resets TCC.

Controller records remain generated data. Shared protocol behavior remains in code. Event normalization removes duplicate and contradictory input. Output dispatch is concurrent. Process and RPC calls have deadlines, buffers and frames are bounded, and current-session logs have typed paths.

DriverKit is retained as an optional virtual-output path and has separate extension diagnostics. Hardware claims require recorded evidence.
