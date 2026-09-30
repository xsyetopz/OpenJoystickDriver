# CLI And Application Runtime

The signed application bundle provides the menu-bar and settings interface for the in-process controller runtime. With `--headless`, the same executable provides the expert CLI for automation, advanced mappings, and diagnostics. The app host does not shell out to the CLI. See [Architecture](architecture.md) for the shared contracts, local-RPC boundary, and process lifecycle.

| Capability | Shared owner |
| --- | --- |
| Controller listing and input state | `DeviceManager` and application-service payloads |
| Permission status and requests | `PermissionManager` in the running host |
| Virtual-device mode and diagnostics | `ApplicationServiceServer` |
| Physical output and remapping | Typed application-service payloads and remapping router |
| Runtime health | `ApplicationServiceManager` and the RPC socket PID |
| Logs | `ApplicationServiceLogService` |
| Updates and reports | CLI commands and shared report/update services |

## Application Host

Launching `OpenJoystickDriver.app` starts `ApplicationServiceRuntime` once, then installs the AppKit status-item menu and reusable settings window facade. See [Architecture](architecture.md) for host identity, socket ownership, and login registration.

## CLI

The installed `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless` CLI remains the supported expert interface for automation, complete mapping operations, streaming input, and diagnostics. The menu-bar/settings facade is the supported consumer interface for readiness, permissions, connected controllers, profiles, and ordinary remapping. With CLI arguments, `swift run OpenJoystickDriver` or `.build/debug/OpenJoystickDriver` uses the installed signed executable when available. The server still checks the user, signing identifier, and team identifier. If the repository sources are newer than the installed executable, the command stops and asks for a new install instead of running stale code.

Run `./Scripts/ojd build install-fast dev` after source changes. Set `OJD_RUN_REPOSITORY_CLI=1` only to run a local command that does not use the application service. An unsigned repository executable cannot connect to the running service. Repository development, build, validation, and release tasks use the separate maintainer command, `./Scripts/ojd`. Direct use of `OpenJoystickDriverHIDTool` is internal and supported only for focused hardware investigation.

CLI command families:

```text
status [--json]
controller list|state|packets|watch|output|disconnect|disconnect-wireless|resume ...
map ...
app status|login enable|disable|logs ...
extension status|enable|disable
permissions ...
controller virtual set|reset
test [positive-seconds]
diagnose [runtime|catalog|report]
update check ...
```

## Workflow Capability Matrix

| Runtime CLI workflow | GUI destination or classification |
| --- | --- |
| `status` and `diagnose runtime` | Overview and Developer Tools runtime health |
| `controller list` | Controllers |
| `controller state` and `controller watch` | Controllers → Input Test |
| `controller output` | Controllers → Input Test output controls |
| `controller packets` | Developer Tools packet capture |
| `map` profile authoring and activation | Profiles |
| `permissions` | Overview access cards |
| `controller virtual set/reset` | Controllers → Virtual HID profile (Advanced) |
| `app logs` and `diagnose report` | Console and Developer Tools report actions |
| `extension status/enable/disable` | Overview driver setup, repair, and uninstall |
| `update check` | Settings → Updates |
| JSON/JSONL output, scripting, soak tests, catalog diagnostics, packaging, catalog generation, and DriverKit generation | Automation-only |

`--timeout <seconds>` applies to bounded application-service calls. Controller operations retain opaque `--device` selection and ambiguity rejection. Machine-readable output uses `--json` where supported. Stream commands use their documented JSONL mode.

Packet capture is opt-in. The service records a controller's raw packets only while a reader holds a five-second capture lease, which each packet-log read renews: opening Developer Tools or selecting a controller there, its Live capture, `controller trace`, or `controller packets`, which samples for one second when its first read is empty. When the lease lapses, recording stops and the captured packets are discarded. Service logs, `status`, and `controller list` note only whether a controller has a serial number, never its value.

Keep raw packets, runtime soaking, catalog inspection, permission audits, and virtual-device self-tests in the CLI: their output is diagnostic, verbose, or unsuitable for an always-present consumer interface.

## Controller Sessions and Virtual HID Profiles

`controller disconnect` suspends a controller from OpenJoystickDriver without terminating its physical Bluetooth or USB link. Suspension neutralizes input and physical effects, removes OJD virtual output, and keeps the controller visible. `controller resume` repeats required startup output and re-enables input; a physical reconnect creates a new active session. System sleep is not a physical disconnect: a controller suspended before sleep returns suspended after wake. A Bluetooth disconnect that reaches OJD before the sleep notification is a physical disconnect and ends the suspension.

`controller disconnect-wireless` is Bluetooth-only. It neutralizes and suspends the selected OJD session before making a bounded request to macOS to close that physical connection. A failed or timed-out close leaves the session suspended so stale input cannot be republished; use `controller resume` only when you intentionally want OJD to accept it again. OJD never reconnects the controller automatically, and the command does not stop other controller sessions.

Parsers that expose complete report observations also expose typed input health in status and support reports. DualShock 4 health uses the advancing device sensor timestamp rather than host packet arrival alone. Missing or non-advancing complete reports become stale after one second, neutralize OJD-published output, and wait for a fresh neutral report before recovery. A fresh held control is not guessed to be accidental. Native HID pass-through may still be visible directly to another app, so stale health remains a Needs attention condition even after OJD retires its own publication.

Each controller model (vendor/product) has a virtual HID profile: `hid-xbox-one-s-bt` (`045E:02FD`, selected automatically when the controller's declared controls fit) or `hid-generic`. Automatic selection runs unless the model has a stored override. `controller virtual set <hid-xbox-one-s-bt|hid-generic> [--vid N] [--pid N] [--device ID]` stores an override for the selected controller's model; `controller virtual reset [--vid N|--pid N|--device ID | --all]` clears it (`--all` clears every model's override and cannot combine with a selector). Both commands print the resulting live profile line, then print a failure to stderr and exit 1 if the request did not fully take effect (for example `controller-not-found`, `override-rejected-by-controller`, or `activation-failed`).

`ApplicationServiceVirtualHIDProfileStatus` reports each connected controller's selected profile, its source (`automatic`, `override`, or `automatic-after-rejecting`), its stored override, and whether no profile is available for its declared controls.

## Responsiveness

The signed application host and headless commands must not wait indefinitely for system tools, login registration, permission APIs, or live-runtime calls.

- System commands use `BoundedProcessRunner` off the main actor.
- Headless live-state calls use framed local RPC with connect, send, and receive deadlines.
- Permission requests await the dedicated `PermissionManager` actor and never run a shell command or poll System Settings.
- System-extension and signing checks return explicit timeout or failure states.
- The host keeps its runtime on the main dispatch queue and exits through the runtime's retained signal handlers.

A missing runtime or stalled system tool may error, but must not freeze host shutdown or any CLI invocation.

## Runtime Health

Run a bounded soak diagnostic against the installed application process:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver \
  --headless diagnose runtime \
  --seconds 300 \
  --interval-ms 1000 \
  --rss-limit-mib 0 \
  --footprint-limit-mib 512
```

`--seconds` accepts 1 to 86400, `--interval-ms` 100 to 60000, and each limit 0 to 65536. Use `--json` for automation.

The sampler records resident set size, physical footprint (including dirty and compressed allocator pages), linear RSS and footprint growth rates, average process CPU, file descriptor count and growth, thread count and growth, and any configured high-water limits.

A window shorter than 60 seconds is `insufficientData` unless a configured high-water limit is exceeded. A stable run is evidence for the exercised workload, not proof that every path is leak-free.

To collect evidence:

- Run the diagnostic against the signed installed build, not only `.build/debug`.
- Confirm that the sampled PID matches `ApplicationServiceManager.health()`.
- Keep a controller active for the requested window.
- Record the verdict and high-water limits.
- Reinstall or restart the application after changing its binary before collecting evidence.
