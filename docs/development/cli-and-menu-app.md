# CLI and menu app parity

The persistent main app owns controller and virtual-output state. The menu UI calls that service in process. Headless commands use the same operations through the authenticated local RPC endpoint.

| Capability | Shared owner |
| --- | --- |
| Controller listing and input state | `DeviceManager` and application-service payloads |
| Permission status and requests | `PermissionManager` in the running main app |
| Virtual-device mode and diagnostics | `ApplicationServiceServer` |
| Physical output | Typed application-service payloads |
| Runtime health | `ApplicationServiceManager` and the RPC socket PID |
| Logs | `ApplicationServiceLogService` |
| Updates | `UpdateChecker` |

RPC is used only where a separately invoked headless process needs live state. The socket is user-private, signing-authenticated, framed, and bounded. GUI-only presentation includes window layout, save panels, and popover state.

## Diagnostic surfaces

The menu app is limited to connection, permission, output, self-test, and support-report actions needed for normal operation and support. Runtime soaking, private Apple catalog inspection, and browser Gamepad capture are developer diagnostics exposed only by headless commands:

```bash
OpenJoystickDriver --headless diagnose runtime --help
OpenJoystickDriver --headless diagnose gamecontroller-catalog --help
OpenJoystickDriver --headless diagnose browser-gamepad --help
```

These commands may share runtime services and report types with the app, but they do not add menu cards, controls, or task state.
