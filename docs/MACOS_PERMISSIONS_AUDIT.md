# macOS Permissions Audit

OpenJoystickDriver has two user-visible processes that may appear in macOS privacy panes:

- `OpenJoystickDriver.app`
- `OpenJoystickDriverDaemon.app`, embedded at `OpenJoystickDriver.app/Contents/Library/LoginItems/OpenJoystickDriverDaemon.app`

## Native macOS permission APIs

### Input Monitoring

macOS 10.15+ gates HID event listening through TCC Input Monitoring. The supported native API is:

- check: `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`
- prompt: `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`

Sources: Apple Developer Forums discuss `IOHIDCheckAccess` / `IOHIDRequestAccess` for Input Monitoring, and public Catalina-era examples use `kIOHIDRequestTypeListenEvent` behind the Input Monitoring privacy pane.

The prompt is per signed executable/bundle identity. A LaunchAgent daemon should not be asked to prompt invisibly over XPC. The app must launch the bundled daemon app in a foreground/accessory helper mode so macOS can attribute the prompt to `OpenJoystickDriverDaemon.app`.

### Accessibility

Accessibility is separate from Input Monitoring. macOS 10.9+ exposes:

- check: `AXIsProcessTrusted()`
- prompt: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`

Source: Apple Developer Documentation for `AXIsProcessTrustedWithOptions(_:)` and `kAXTrustedCheckOptionPrompt`.

OpenJoystickDriver should not require Accessibility for normal DriverKit or IOHIDUserDevice virtual gamepad output. It is an optional fallback section only, so users have a clear path if macOS or future daemon behavior asks for Accessibility.

## Current architecture

- `PermissionManager` centralizes Input Monitoring and Accessibility checks/prompts.
- The menu-bar app has a Permissions card for app and daemon Input Monitoring.
- The same card now includes an optional Accessibility section for app and daemon.
- App prompts run in `OpenJoystickDriver.app`.
- Daemon prompts run by launching `OpenJoystickDriverDaemon.app` with a dedicated argument:
  - `--request-input-monitoring`
  - `--request-accessibility`
- Daemon permission state probes run the bundled daemon executable in check-only modes:
  - `OJD_PERMISSION_CHECK_ONLY=1`
  - `OJD_ACCESSIBILITY_CHECK_ONLY=1`

## Why this is the native macOS path

TCC grants are attached to the requesting binary/bundle. Opening System Settings is not enough; OJD must call the native API from the exact app that needs the grant. For the daemon, the menu-bar app registers and opens the embedded daemon app through LaunchServices/`NSWorkspace`, then the daemon helper calls the native permission API in its own process. This gives macOS the correct identity to show in Privacy & Security.

## User-facing guidance

1. Install or open `/Applications/OpenJoystickDriver.app`.
2. In the Permissions card, request Input Monitoring for `OpenJoystickDriver` and `OpenJoystickDriver Daemon`.
3. If macOS asks for Accessibility, use the optional Accessibility rows for the app or daemon.
4. If macOS opens System Settings, enable the matching entry and allow any quit/reopen prompt.

## Verification points

- App Input Monitoring calls `IOHIDRequestAccess` from `OpenJoystickDriver.app`.
- Daemon Input Monitoring launches the embedded daemon app and calls `IOHIDRequestAccess` from that process.
- Accessibility calls `AXIsProcessTrustedWithOptions` from the app or daemon helper process.
- The daemon remains a LaunchAgent for normal service mode; permission prompting is isolated to short-lived helper modes.
