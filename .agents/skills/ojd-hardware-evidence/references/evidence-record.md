# Evidence Record

## Contents

- [Evidence ledger](#evidence-ledger)
- [Bounded physical output](#bounded-physical-output)
- [Redaction](#redaction)
- [Handoff fields](#handoff-fields)

## Evidence ledger

**Definition.** One row per claim, each with its own minimum observation and class.

| Claim | Minimum physical observation |
| --- | --- |
| Discovery | Exact VID/PID, transport, mode, interface, and stable presence |
| Input | Neutral, then press and release (or a full axis sweep) for each claimed control |
| Reconnect | Disconnect, rediscovery, handshake, then representative input |
| Rumble | Each claimed actuator identified separately |
| Player LED or RGB | Each claimed pattern or colour observed |

The classes are source-backed, packet/parser-backed, record-probe-backed, hardware-verified, and unavailable (no implemented path or exposed capability).

**Use when.** Writing or updating a `contributing/testing/` page, an issue comment, or a PR test plan.

**Do not use when.** Never put the class into a controller record. The schemas forbid evidence fields there.

**Verify.** Each claim in the page has its class and the command or observation behind it.

## Bounded physical output

**Definition.** List the capabilities, generate a plan, then run one step at a low bounded value on one named controller.

```bash
app=/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver
"$app" --headless controller output list
"$app" --headless controller output plan <decimal-vid> <decimal-pid> [--device <id>]
```

When identical models are connected, `--device <id>` is required. Ambiguous commands are rejected. `rumble`, `player`, `color`, and `brightness` each send one command, and a missing capability fails with a "has no ... implementation" message. The full behavior is in `contributing/testing/physical-output.md`.

**Use when.** Any rumble, LED, colour, or brightness claim.

**Do not use when.** The user has not approved physical output for this controller in this session.

**Cost removed.** An unbounded or wrong-device write can hold a motor on or change a controller mode, and the user has to recover the controller by hand.

**Verify.** Report the step, its value, the controller it targeted, and what the person observed.

## Redaction

- Remove serial numbers, user home paths, signing identities, Team IDs, tokens, and runtime `--device` identifiers.
- Keep VID/PID, interface, endpoint, report ID, length, direction, and timing, because the analysis depends on them.
- Never publish unredacted captures.

## Handoff fields

Include: the controller name and VID/PID; transport and mode; the OJD revision; the macOS version; the firmware, if known; the exact commands and durations; which interface owner was stopped; the handshake and summary lines; the control matrix; the reconnect result; the result for each actuator; the evidence class of each claim; the redactions applied; and the remaining unknowns.
