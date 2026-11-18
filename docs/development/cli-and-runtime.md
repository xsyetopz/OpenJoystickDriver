# CLI and Application Runtime

The signed app bundle provides the menu-bar and settings interface. As `ojd` (`argv[0]`) the executable is the CLI; under any other name it runs the app host, which never shells out to the CLI. Contracts, RPC boundary, lifecycle: [Architecture](architecture.md).

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

Launching `OpenJoystickDriver.app` starts `ApplicationServiceRuntime` once, then installs the status-item menu and settings window. Host identity, sockets, login registration: [Architecture](architecture.md).

## CLI

`ojd` covers automation, complete mapping operations, streaming input, and diagnostics. Options, output formats, exit codes: [Using the command line](../../wiki/Command-Line.md). The menu bar and settings window cover readiness, permissions, controllers, profiles, and ordinary remapping.

A repository build run as `ojd` (for example `ln -sf OpenJoystickDriver .build/debug/ojd`) uses the installed signed executable when available; the server still checks user, signing identifier, and team identifier. If sources are newer than the installed executable, the command stops and asks for an install. Run `just install-fast-dev` after source changes. `OJD_RUN_REPOSITORY_CLI=1` runs a local command that skips the application service; an unsigned repository executable cannot connect to the running service.

`OpenJoystickDriverHIDTool` is internal, for hardware investigation. When the service holds a controller exclusively, `OpenJoystickDriverHIDTool --monitor` reads the service's packet log like `ojd controller capture`. The service refuses a tool it did not sign, and the tool hints to run `ojd controller capture`.

CLI command families:

```text
ojd status
ojd service start|stop|wait
ojd controller list|show|watch|check|capture|rumble|light|player|speaker|suspend|resume|disconnect|calibrate|pair|unpair|claim|release|lookup
ojd profile ...
ojd binding ...
ojd macro ...
ojd virtual show|set|reset|feed|export-mapping|launch
ojd record ...
ojd mod ...
ojd protocol ...
ojd permission list|request
ojd transport-extension status|activate|deactivate
ojd setting list|get|set|reset|test-notification
ojd config ...
ojd access status|enable|disable|list|grant|revoke|web
ojd log show|path|export
ojd diagnose [--output PATH] [--soak SECONDS] [--frames SECONDS]
ojd update check
ojd explain <code>
ojd migrate
ojd generate
```

`ojd <command> --help` lists subcommands and options.

## Workflow Capability Matrix

| Runtime CLI workflow | GUI destination or classification |
| --- | --- |
| `status` | Menu-bar status row and the banner of the main window |
| `service start/stop/wait` | Menu-bar Quit and app launch |
| `permission list/request` | Access area permission rows |
| `transport-extension status/activate/deactivate` | Settings, Advanced pane, Xbox USB Driver |
| `setting list/get/set` | Settings |
| `log show/path/export` | Activity area, Log mode |
| `diagnose --output` | Copy Support Report |
| `update check` | Settings update check |
| JSON/JSONL output, scripting, soak tests, catalog diagnostics, packaging, catalog generation, and DriverKit generation | Automation-only |

| Option or operand | Behavior |
| --- | --- |
| `--timeout <seconds>` | Bounds application-service calls |
| `<controller>` | ID from `ojd controller list`, or `VVVV:PPPP` (hexadecimal vendor and product ID); a VVVV:PPPP matching two connected controllers is rejected, listing them |
| `--json` | Machine-readable output where supported |

Packet capture is opt-in. The service records raw packets only while a reader holds a five-second capture lease, renewed by each packet-log read. Readers: Developer Tools (opening it or selecting a controller), its Live capture, `ojd controller capture`. Lapsed lease: recording stops, captured packets are discarded. Logs, `status`, and `controller list` show only whether a controller has a serial number, never its value.

CLI-only: raw packets, soak runs, catalog inspection, permission audits, virtual-device self-tests.

## Controller Sessions and Virtual HID Profiles

| Command | Effect |
| --- | --- |
| `controller suspend` | Releases the controller without ending its Bluetooth or USB link: neutralizes input and physical effects, removes OJD virtual output, keeps it visible, closes every HID and USB handle OJD holds |
| `controller resume` | Only way to reopen handles (they stay closed even if the HID backend admits the controller again); repeats startup output, re-enables input. Failed resume: session stays suspended |
| `controller disconnect` | Bluetooth only. Suspends, then asks macOS to close the connection within a bound. Failed close: session stays suspended. OJD never reconnects automatically; `controller resume` accepts the controller again |

Physical reconnect: active session. Suspended before sleep: returns suspended after wake, unless a Bluetooth disconnect reaches OJD before the sleep notification, which ends the suspension.

`ojd controller show --json` reports `publication.state`:

| Field | Values |
| --- | --- |
| `publication.state` | Published, NotPublished, Failed |
| `publication.reason` | Only when NotPublished: OutputDisabled, SystemGamepad, NativeHIDPassThrough, UpstreamVirtualDevice, SessionSuspended, NoVirtualProfile, Suppressed, NoInputYet, HeldByAnotherClient |
| `publication.failure` | Only when Failed: non-empty text of the failed send |

`ApplicationServicePublicationStatus` builds and decodes only these combinations. The extension-owned route waits as NoInputYet, like the virtual HID route.

Parsers with complete report observations expose typed input health in status and support reports. DualShock 4 health uses the advancing sensor timestamp. Missing or non-advancing reports go stale after one second, neutralize OJD output, and wait for a fresh neutral report. Stale health stays Needs attention (native HID pass-through may stay visible to another app).

Each controller model (vendor/product) has a virtual HID profile, automatic unless the model has a stored override:

| Profile | ID | Selection |
| --- | --- | --- |
| SDLCompatible | 045E:0B0C | Automatic when declared controls fit |
| GameControllerCompatible | 045E:0B13 | Override only |
| Generic | | Override or fallback |

| Command | Effect |
| --- | --- |
| `ojd virtual reset <controller>` | Clears the override |
| `ojd virtual reset --all` | Clears every override; cannot combine with a controller |
| `ojd virtual show [<controller>]` | Shows each live profile and the choices |
| `ojd virtual launch [--] <program> [<arguments>]` | Runs the program with `SDL_GAMECONTROLLERCONFIG` set by `SDLLaunchEnvironment.environment(adding:to:)` to each served profile's mapping line (existing value stays first). Exit: `E2013` no controller has a live profile, `E2033` program cannot start, otherwise the program's status |

- `ojd virtual set <sdl-compatible|game-controller-compatible|generic> <controller>`: stores a model override; `--unit` applies it to one controller by unit ID.
- `ojd virtual export-mapping [<profile>] [--format sdl|w3c]`: prints each profile's SDL mapping or W3C description from `VirtualHIDProfileID.gamepadMapping()`.

`set` and `reset` print the live profile line. A request not fully taken effect (for example `controllerNotFound`, `overrideRejectedByController`, `activationFailed`) prints a failure to stderr and exits 1.

`ApplicationServiceVirtualHIDProfileStatus` reports each controller's selected profile, source (automatic, override, automaticAfterRejecting), stored override, and whether no profile fits.

## Responsiveness

Host and CLI never wait indefinitely on system tools, login registration, permission APIs, or runtime calls.

| Area | Mechanism |
| --- | --- |
| System commands | `BoundedProcessRunner`, off the main actor |
| Headless live-state calls | Framed local RPC with connect, send, receive deadlines |
| Permission requests | Await the `PermissionManager` actor; no shell command or System Settings polling |
| System-extension and signing checks | Explicit timeout or failure states |
| Host | Main dispatch queue; exits through the runtime's retained signal handlers |

## Runtime Health

Every diagnostic check plus a bounded soak of the installed app process:

```bash
ojd diagnose \
  --soak 300 \
  --interval-ms 1000 \
  --rss-limit-mib 0 \
  --footprint-limit-mib 512
```

| Option | Range |
| --- | --- |
| `--soak` | 1 to 86400 seconds |
| `--interval-ms` | 100 to 60000 |
| each limit | 0 to 65536 |

`--json` for automation. The sampler records resident set size and physical footprint (including dirty and compressed allocator pages) with linear growth rates, average CPU, file descriptor and thread counts with growth, and high-water limits.

A window under 60 seconds is insufficientData unless a high-water limit is exceeded. A stable run is evidence for the exercised workload only. Collect evidence:

| Step | Action |
| --- | --- |
| 1 | Run against the signed installed build, not only `.build/debug` |
| 2 | Confirm the sampled PID matches `ApplicationServiceManager.health()` |
| 3 | Keep a controller active for the window |
| 4 | Record the verdict and high-water limits |
| 5 | Reinstall or restart the app after changing its binary |

## Further Reading

- [Architecture](architecture.md)
- [Using the command line](../../wiki/Command-Line.md)
