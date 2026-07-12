# Implementation status

Automated checks cover code paths and fixtures. Hardware support claims still require controller, browser, signed-runtime, or Apple catalog evidence.

## Implemented

### Contributor record probe

`diagnose record` validates and probes a canonical raw USB record without installing the app, daemon, or DriverKit extension. See [the general hardware test](../testing/controller-record.md).

### Linux xpad import

`scripts/ojd-generate-xpad-records.py` creates review-only candidates from pinned Linux source metadata. Generated IDs do not become hardware claims.

### Permissions

The CLI and menu app show separate app and daemon Input Monitoring states. A confirmed repair can reset only the two OJD Input Monitoring decisions. OJD does not request Accessibility.

### Diagnostics

Available tools include normalized input, raw packet inspection, bounded logs, redacted support reports, runtime health, Apple catalog audit, browser snapshots, and physical-output plans.

### Runtime safeguards

Event normalization removes duplicate and contradictory input. Output dispatch is concurrent. Process and XPC calls have deadlines. Buffers are bounded, and daemon health reports memory, descriptors, and threads.

### CLI and menu app

Both surfaces call shared services for daemon control, permissions, input, output, diagnostics, reports, logs, updates, and settings. Presentation-only actions do not need a CLI command.

### DriverKit

The optional extension provides a vendor-defined integrity relay and report-delivery self-test. Consumer gamepad output remains available through the user-space backend.

## Open issue evidence

- **#8, Steam Controller:** parser, discovery, wireless lifecycle, haptics, and brightness exist. Hardware input and output still need the Steam request.
- **#9, Xbox 360 wireless receiver:** records, lifecycle, parsing, rumble, and lights exist. Receiver hardware must cover connection, slots, input, output, and reconnect.
- **#10, identity and lights:** stable labels and typed light output exist. Duplicate physical and virtual ownership still needs a capture before changing seizure policy.
- **#11, Logitech F310:** deterministic Xbox-style mapping has fixtures. The reporter must confirm the physical and browser mapping.
- **#14, Razer Wolverine V3 TE:** a GIP record exists. Input and output reports remain unverified.
- **#12 and #15:** the exported issues are closed.

Issue snapshots live under `docs/external/OpenJoystickDriver/`. SDL source material lives under `docs/external/sdl/`.

## Evidence still needed

- physical controller captures described under `docs/testing/`
- Chrome, Firefox, and Safari snapshots for each tested compatibility identity
- installed TCC, daemon, and DriverKit checks
- a long daemon soak on representative hardware
- an exact Apple GameController catalog or live runtime match before adding Apple-backed Xbox spoof identities
