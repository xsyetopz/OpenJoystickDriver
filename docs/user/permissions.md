# Permissions

OJD requests Input Monitoring. It does not request Accessibility. Driver Extension and Login Item approvals are separate macOS controls.

## Input Monitoring

### OpenJoystickDriver app

The app needs Input Monitoring only for direct or headless controller diagnostics. Normal background input belongs to the daemon.

### OpenJoystickDriver Daemon

The daemon needs Input Monitoring to read physical controllers while the menu app is closed. Installing or explicitly requesting daemon access may add the helper to System Settings.

## Permissions OJD does not use

OJD does not call `AXUIElement`, synthesize keyboard or mouse input, or control another app. An OpenJoystickDriver entry under Accessibility is unnecessary and may be disabled.

## Other system approvals

Driver Extension approval installs or updates the optional DriverKit relay. Login Item approval registers the daemon through `SMAppService`. Neither approval grants Input Monitoring or Accessibility.

## Repair stale entries

A switch can remain visible after the executable behind it has been replaced. TCC evaluates process identity, and a running daemon can retain an earlier decision until restart. macOS does not provide an API for selecting one old-version row. OJD therefore requires confirmation before resetting consent.

Use **Refresh stale entries…** in the menu app, or run:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless permissions refresh --confirm
```

The repair resets `ListenEvent` only for `com.openjoystickdriver` and `com.openjoystickdriver.daemon`, refreshes daemon registration, and opens Input Monitoring settings. It leaves Accessibility and other applications alone. Grant the required OJD identities again after the reset.
