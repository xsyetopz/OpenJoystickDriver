# Menu app responsiveness

The menu app must not wait synchronously for child processes on the main actor. System-tool calls that wait for completion in the GUI or CLI run through `BoundedProcessRunner`, which provides four guarantees:

1. stdout and stderr are drained together while the process runs, preventing a full pipe from deadlocking the caller;
2. captured output has a fixed maximum size while excess bytes are still drained;
3. every call has a deadline, followed by termination and a kill fallback; and
4. timeout, exit status, captured output, and truncation are returned as typed data.

## GUI boundaries

The following GUI operations leave the main actor before starting a child process:

- app-bundle signature verification before daemon lifecycle actions;
- bundled-daemon Input Monitoring permission probes;
- `systemextensionsctl` status probes; and
- browser launch requests from the Gamepad API diagnostic.

The XPC client separately bounds daemon replies. A stalled daemon or system tool can therefore produce a visible error or unknown state, but it must not freeze the menu, block popover dismissal, or wait forever.

## CLI parity

The headless bundle-signature check, daemon `launchctl` plumbing, permission helper launch, system-extension status, and browser launch use the same bounded runner. GUI responsiveness is not implemented as a second, GUI-only behavior.

## Validation

Focused regression checks:

```bash
swift test --filter BoundedProcessRunnerTests
swift test --filter MenuAppResponsivenessTests
swift test --filter InputMonitoringPromptFlowTests
swift test --filter BrowserGamepadDiagnosticTests
```

`BoundedProcessRunnerTests` includes a child that floods stdout indefinitely. The runner must drain it, cap retained output, terminate it at the deadline, and return promptly. Source-integration tests verify that GUI callsites use async wrappers and that CLI callsites use the same primitive.

These tests prove scheduling and timeout contracts. They do not replace a manual responsiveness pass on a low-end Mac while opening the popover, requesting permissions, checking DriverKit state, and launching the browser diagnostic.
