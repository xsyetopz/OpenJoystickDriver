# CLI and application runtime

The signed application bundle provides the menu-bar and settings interface for the
in-process controller runtime. With `--headless`, the same executable provides the
expert CLI for automation, advanced mappings, and diagnostics. The app host does
not shell out to the CLI. See [Architecture](architecture.md) for the shared
contracts, local-RPC boundary, and process lifecycle.

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

Launching `OpenJoystickDriver.app` starts `ApplicationServiceRuntime` once, then
installs the AppKit status-item menu and reusable settings window facade. See
[Architecture](architecture.md) for host identity, socket ownership, and login
registration.

## CLI

The installed `OpenJoystickDriver --headless` CLI remains the supported expert
interface for automation, complete mapping operations, streaming input, and
diagnostics. The menu-bar/settings facade is the supported consumer interface for
readiness, permissions, connected controllers, profiles, and ordinary remapping.
Repository development, build, validation, and release tasks use the separate
maintainer command, `./scripts/ojd`. Direct use of `OpenJoystickDriverHIDTool` is
internal and supported only for focused hardware investigation.

The CLI command families are:

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
Machine-readable output uses `--json` where supported. Stream commands use
their documented JSONL mode.

Raw packet data, runtime soaking, catalog inspection, permission audits, and
virtual-device self-tests stay in the CLI. Their output is diagnostic, verbose,
or unsuitable for an always-present consumer interface.
