---
name: ojd-hardware-evidence
description: >-
  Probes and records physical controller behavior for OpenJoystickDriver:
  validates and live-probes a candidate controller record, reads USB_RX/EVENT
  probe output, runs DEXT, SDL3, and GameController diagnostics, plans bounded
  rumble/LED output tests, and writes the docs/testing page with an evidence
  class per claim. Use when a controller is not detected, input is wrong,
  reconnect fails, or rumble/LED support must be confirmed on hardware. Not for
  authoring catalog records (use ojd-controller-catalog) or fixing Swift code
  (use ojd-swift-change).
---

# OpenJoystickDriver Hardware Evidence

Produce a repeatable evidence record for one controller in one connection mode. Each claim (discovery, input, reconnect, rumble, LED) carries its own evidence class. Schema checks, parser fixtures, and source reading never stand in for a physical observation.

## Workflow

1. Read the controller's generated record, its driver under `Sources/OpenJoystickDriverKit/Protocol/Drivers/`, and the matching page in `docs/testing/` (see `docs/testing/controller-record.md` and `docs/testing/physical-output.md`).
1. Write down one question, its success signal, the connection mode, and the macOS version.
1. Pick the probe from the [probe table](references/probes.md#choose-the-probe).
1. Validate before opening hardware: `./Scripts/ojd diagnose record /tmp/candidate.json --validate-only`.
1. Ask the user before any live probe, install, system-extension activation, or physical output. Name the controller that may rumble, light, or change mode.
1. Run the smallest bounded capture (`--seconds N`, 1 to 300, default 30) that separates the behaviors: neutral, then one control, then release.
1. Read the markers with the [marker card](references/probes.md#record-probe-markers) and draw conclusions only from the [failure table](references/probes.md#failure-meanings).
1. Record the result in the [evidence ledger](references/evidence-record.md#evidence-ledger) with the [redactions](references/evidence-record.md#redaction) applied.

## Route the Evidence To a Card

| Observation | Card |
| --- | --- |
| Which command answers this question | [Choose the probe](references/probes.md#choose-the-probe) |
| Reading `RECORD_*`, `USB_RX`, `EVENT`, `PARSE_ERROR` lines | [Record-probe markers](references/probes.md#record-probe-markers) |
| Zero packets, handshake failure, busy interface | [Failure meanings](references/probes.md#failure-meanings) |
| Testing rumble, player LED, colour, or brightness | [Bounded physical output](references/evidence-record.md#bounded-physical-output) |
| Writing the testing page or issue comment | [Evidence ledger](references/evidence-record.md#evidence-ledger) |
| Sharing captures or logs | [Redaction](references/evidence-record.md#redaction) |

## Rules

- Stop the running app or any other probe before a live record probe. Two readers on one interface give busy errors or split packets, and the result shows nothing about the controller.
- The record probe covers raw USB GIP and wired or wireless-receiver Xbox 360 records. A HID or Bluetooth controller missing from it shows no protocol incompatibility.
- Do not fill unknown bytes by analogy with a similar PID. Leave them unknown in the page.
- The output checks from `ojd controller show` and a successful write prove only that a command was sent. The actuator counts as working only after someone observes it.
- The controller ID from `ojd controller list` is valid for one runtime session. Recording it as an identity makes later reruns point at nothing.
- Hardware verification applies to the model, mode, firmware, and macOS version that were observed, and to nothing else.
- The record probe prints `RECORD_HANDSHAKE ... result=complete` only when every startup write succeeds; a failed write prints only `ERROR:` on stderr and exits 1. Quote the handshake line or name its absence, because a report that quotes only `RECORD_SUMMARY` loses whether the declared startup was accepted.
- Write marker names literally (`RECORD_HANDSHAKE`, `RECORD_SUMMARY`), also when listing evidence still to collect before any probe has run. "The handshake line" does not tell the user which line to search for in the output.
- There is no `--detach` option. Free a busy interface by quitting its owner (the app, Steam, or another probe), then record which owner it was.

## References

- [Probes](references/probes.md): choosing a probe, record-probe markers, failure meanings.
- [Evidence record](references/evidence-record.md): evidence ledger and classes, bounded physical output, redaction, handoff fields.

## Completion Evidence

The report gives the controller and its decimal and hex VID/PID, the transport and mode, the OJD revision, and the macOS version. It also gives every command with its duration and exit status. For a record probe it quotes, redacted, the `RECORD_VALIDATION`, `RECORD_HANDSHAKE`, and `RECORD_SUMMARY` lines, any `RECORD_BINDING` line, and one `USB_RX`/`EVENT` pair per claimed control. A missing `RECORD_HANDSHAKE` line is reported as a failed startup with its `ERROR:` line ([marker card](references/probes.md#record-probe-markers)). It also gives the control matrix, the reconnect result, the result for each actuator, the evidence class of each claim, and the claims left unverified. Record changes go to `ojd-controller-catalog`, and code fixes go to `ojd-swift-change`.
