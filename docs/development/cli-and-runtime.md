# CLI and application runtime

The signed application bundle is a thin, headless host for the in-process
controller runtime. The executable also provides the low-level CLI through
`--headless`; both paths use the same `OpenJoystickDriverKit` contracts and
authenticated local RPC endpoint. The app host does not shell out to the CLI.

| Capability | Shared owner |
| --- | --- |
| Controller listing and input state | `DeviceManager` and application-service payloads |
| Permission status and requests | `PermissionManager` in the running host |
| Virtual-device mode and diagnostics | `ApplicationServiceServer` |
| Physical output and remapping | Typed application-service payloads and remapping router |
| Runtime health | `ApplicationServiceManager` and the RPC socket PID |
| Logs | `ApplicationServiceLogService` |
| Updates and reports | CLI commands and shared report/update services |

## Application host

Launching `OpenJoystickDriver.app` starts `ApplicationServiceRuntime` directly
and keeps the process alive on the main dispatch queue. It has no status item,
popover, custom panel, or menu-specific state. The app remains the single
signed TCC and DriverKit host, and `SMAppService.mainApp` registration is still
performed on first launch unless the user opted out.

## CLI

Headless commands are the supported control and diagnostic surface:

```text
status [--json]
controller list|state|packets|watch|output ...
map ...
app status|login enable|disable|logs ...
extension status|enable|disable
permissions ...
compat show|set <identity>|reset
test [positive-seconds]
diagnose [runtime|catalog|report]
update check ...
```

`--timeout <seconds>` applies to bounded application-service calls. Controller
operations retain opaque `--device` selection and ambiguity rejection.
Machine-readable output uses `--json` where supported; stream commands use
their documented JSONL mode.

Raw packet data, runtime soaking, catalog inspection, permission audits, and
virtual-device self-tests stay in the CLI because their output is diagnostic,
verbose, or unsuitable for an always-present consumer surface.
