# Permissions

OpenJoystickDriver uses one privacy identity: `OpenJoystickDriver.app`. No nested executable needs to be located or added manually.

## Input Monitoring

Input Monitoring lets the app read reports from physical controllers.

```text
System Settings > Privacy & Security > Input Monitoring
```

## Accessibility

The compatibility virtual-gamepad backend uses `IOHIDUserDevice`. macOS authorizes that HID publication through the post-event permission shown as Accessibility.

```text
System Settings > Privacy & Security > Accessibility
```

This access publishes a virtual gamepad. OpenJoystickDriver does not inspect other applications' UI or synthesize keyboard or mouse actions.

Use the app's **Request Access** action once. The app requests any missing state and then reads the authoritative result. If macOS asks for a relaunch, quit and reopen OpenJoystickDriver. The CLI command `permissions status` obtains both states from the running main app rather than inheriting the terminal's privacy identity.

## Other approvals

Driver Extension approval installs or updates the optional generated DriverKit
relay. The host app has a narrow DriverKit user-client allowlist for
`com.openjoystickdriver.VirtualHIDDevice`; it does not request allow-any access.
Login Item approval allows macOS 13 or later to start the main app at login.
Neither approval grants Input Monitoring or Accessibility.

## Older alpha entries

An older alpha may leave an `OpenJoystickDriverDaemon` registration or stale privacy row. Current builds do not execute that helper or manage its launchd registration. If System Settings offers a remove control for a stale entry, remove that entry manually; OJD never resets TCC.
