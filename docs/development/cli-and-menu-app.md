# CLI and menu app

The CLI owns each operational contract. The menu app calls the same service or XPC method. Window layout, save panels, refresh buttons, and quitting are GUI-only presentation actions.

## Shared operations

### Daemon and devices

- CLI: `status`, `list`, and the install, start, restart, and uninstall commands
- Menu app: system and device cards
- Code: `DaemonManager` and typed XPC payloads

### Permissions

- CLI: `permissions`
- Menu app: Permissions card
- Code: `PermissionManager`

### Controller input

- CLI: `input state`, `input watch`, and `input packets`
- Menu app: Input Test
- Code: `ControllerInputDiagnosticService`

### Virtual output

- CLI: `compat`, `userspace`, `output`, `selftest`, and `reset-settings`
- Menu app: compatibility picker, output details, and self-test
- Code: shared XPC operations and virtual-device diagnostics

### Physical output

- CLI: `physical-output`
- Menu app: Input Test output controls and validation plan
- Code: typed physical-output XPC payloads

### Diagnostics and support

- CLI: `diagnose runtime`, `diagnose gamecontroller-catalog`, `diagnose browser-gamepad`, `report create`, and `logs`
- Menu app: matching diagnostic, report, and log controls
- Code: the same sampler, auditor, browser service, report service, and bounded log reader

### Updates

- CLI: `updates check`
- Menu app: update card; signed builds may add Sparkle installation UI
- Code: `UpdateChecker` for release metadata

### System extension

- CLI: `sysext uninstall`
- Menu app: confirmed removal in the System card
- Code: `OSSystemExtensionRequest`

A feature is paired only when both surfaces reach the same operation. Matching labels are not enough.

## Input examples

VID and PID are optional with one connected controller:

```bash
OpenJoystickDriver --headless input state --json
OpenJoystickDriver --headless input watch --seconds 10 --interval-ms 16
OpenJoystickDriver --headless input packets --limit 50
```

Specify the device when more than one controller is connected:

```bash
OpenJoystickDriver --headless input state 0x045e 0x028e
```

Raw packets may contain device-specific data. Review them before sharing. Redacted support reports omit packet payloads.

The Input Test window samples normalized state at 60 Hz. Daemon input and virtual output are not tied to that display rate.

## Updates and logs

The CLI update check reads release metadata. It does not install an update:

```bash
OpenJoystickDriver --headless updates check
OpenJoystickDriver --headless updates check --prerelease --json
OpenJoystickDriver --headless updates check --open
```

`--open` opens the release page only when an update exists.

Log reads retain at most 256 KiB per file:

```bash
OpenJoystickDriver --headless logs show --stream both --lines 100
OpenJoystickDriver --headless logs show --stream stderr --json
OpenJoystickDriver --headless logs path --stream both
OpenJoystickDriver --headless logs open --stream stdout
```

Logs can contain device identifiers and paths. Use a redacted support report when possible.
