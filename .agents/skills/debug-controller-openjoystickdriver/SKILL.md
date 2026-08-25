---
name: debug-controller-openjoystickdriver
description: >
  Use when diagnosing a physical controller in OpenJoystickDriver: USB/HID
  discovery, VID/PID and interface or endpoint capture, protocol or parser
  packets, record-probe handshakes, reconnect, rumble, LED or other output,
  and evidence classification from source-backed to hardware-verified; not for
  catalog authoring, generic product tests, UI, topology, script tests, or
  implementing product behavior.
---

# Debug Controller OpenJoystickDriver

Use this action skill for evidence-first investigation of one physical
controller and its existing OpenJoystickDriver path. It covers discovery and
transport observations, packet and parser diagnosis, signing-free runtime
record probes, physical output checks, and an honest evidence handoff. It does
not turn a passing schema check or parser fixture into a hardware claim.
`AGENTS.md` and the documented testing procedures remain authoritative.

## When to use

- A controller is missing from USB/HID discovery, opens on the wrong interface,
  reports a busy claim, or reconnects unreliably.
- A known record needs a raw packet capture, startup/handshake diagnosis,
  report-ID or framing analysis, parser-event comparison, or keep-alive check.
- A physical controller needs input coverage (neutral plus every control),
  reconnect evidence, or output checks for rumble, trigger motors, player LEDs,
  or RGB lighting.
- A maintainer needs to classify a path as `sourceBacked`, `hardwareVerified`,
  or `unavailable`, and distinguish external packet evidence from an OJD
  native IOUSBHost/USBDriverKit acceptance run.
- An experimental controller record needs a repeatable request, exact command,
  redacted packet evidence, and a report that can support or reject a future
  catalog decision.

## When NOT to use

- Authoring, importing, or regenerating a controller record or catalog input;
  route to `$add-controller-openjoystickdriver`.
- Adding Swift product tests, broad product validation, or a parser regression
  test; route to `$test-openjoystickdriver` (this skill may run the supported
  parser harness as diagnostic evidence).
- Implementing or repairing parser, HID, output, runtime, or catalog behavior;
  route to `$maintain-openjoystickdriver`.
- Designing menu-bar/settings UI, accessibility, or user-facing diagnostics;
  route to `$design-openjoystickdriver` and `$apple-design-hig`.
- Moving or splitting Sources/Tests, target ownership, or architecture paths;
  route to `$organize-openjoystickdriver`.
- Testing or changing shell/Python implementation, source prose, or generated
  `.build/driverkit/generated/` output. Use the supported `ojd` route or the
  owning skill instead; never add a script fixture or local validator.

## Non-negotiables

- Start with the exact device identity, transport (USB, HID, Bluetooth, or
  receiver), connection mode, OJD commit, macOS version, Mac model, and record
  path. Preserve unrelated work and inspect `git status --short --branch`.
- Treat the canonical record and protocol source as hypotheses. Do not guess
  endpoint addresses, interface numbers, configuration changes, startup
  packets, delays, keep-alive policy, report layouts, checksums, or output
  formats. Record which facts come from OJD source, upstream evidence, a local
  capture, or physical observation.
- Keep candidate JSON outside
  `Sources/OpenJoystickDriverKit/Resources/Controllers/` until reviewed. Use
  decimal VID/PID and other numeric values in JSON. Catalog authoring belongs to
  `$add-controller-openjoystickdriver`.
- A parser harness, `--validate-only`, successful handshake, packet count, or
  generated output plan is not hardware verification. Do not change
  `provenance.verified` from evidence that does not satisfy the documented
  physical checks.
- Never add tests that read Swift, shell, or documentation and assert literal substrings or
  human-readable messages. Observe typed events, packet structure, return
  codes, routes, and physical behavior; raw captures must be redacted before
  publication and must not expose serial values or filesystem secrets.
- Ask before taking consequential actions. Do not use `--detach` by default:
  retry it only after a busy claim, and unplug/reconnect afterward so macOS can
  reclaim the interface. Quit Steam, games, and other controller tools first.

## Quick start

1. **Freeze identity and scope.** Read `AGENTS.md`,
   `docs/testing/controller-record.md`, `docs/user/compatibility.md`, and
   `docs/development/experimental-controllers.md`. Capture VID/PID (decimal
   and hexadecimal), connection mode, expected protocol/parser, record path,
   provenance status, OJD commit, macOS version, Mac model, and
   firmware if known. Decide whether this is discovery, input/parser,
   reconnect, or output evidence; do not silently expand the request.
2. **Establish discovery.** Use native evidence (`system_profiler`, `ioreg`,
   or the controller's documented HID tool) and the repository's listing or
   monitor command. Record the exact USB configuration, interface, endpoint
   directions, transport collection, and whether another owner or Steam is
   holding it. A HID/Bluetooth/unknown path is not automatically supported by
   the raw-USB record probe; select the tool documented for that transport.
3. **Validate the record without hardware.** Keep the candidate outside the
   bundled records and run:

   ```bash
   ./scripts/ojd diagnose record /tmp/controller-candidate.json --validate-only
   ```

   A valid raw-USB GIP/Xbox360 record ends with
   `RECORD_VALIDATION result=valid`. This checks schema, supported protocol,
   transport, variants, endpoint directions, and startup names; it says
   nothing about the physical device.
4. **Exercise protocol/parser evidence.** Compare observed packet bytes with
   report IDs, lengths, sequence/framing, checksums, startup and output rules.
   Run the supported `test parsers-macos14` route for the macOS-14 parser
   harness. Route new or changed
   product tests to `$test-openjoystickdriver`; do not create source-text or
   `Tests/Scripts` fixtures.
5. **Probe the physical record.** Quit competing tools, connect directly, and
   run the exact record for a bounded interval:

   ```bash
   ./scripts/ojd diagnose record /tmp/controller-candidate.json --seconds 30
   ```

   Inspect `RECORD`, `USB_DEVICE`, `USB_CLAIM`, `RECORD_HANDSHAKE`, `USB_TX`,
   `USB_RX`, `EVENT`, `PARSE_ERROR`, and `RECORD_SUMMARY` lines. Capture
   neutral, one press/release per button and D-pad direction, trigger idle/
   intermediate/full, stick extremes and center, stick clicks, Guide or any
   record-declared extra control. Check packet continuity, net events, and
   parse errors, then unplug/reconnect and repeat handshake plus representative
   controls. If claim is busy, retry once with `--detach`, record that fact, and
   unplug/reconnect afterward.
6. **Probe physical output separately.** With a current installed app, run:

   ```bash
   OpenJoystickDriver --headless controller output list
   OpenJoystickDriver --headless controller output plan <vid> <pid>
   # add --json for a machine-readable plan; add --device <opaque-id> only
   # for the current session when identical devices are ambiguous
   ```

   Execute each generated rumble, trigger, player-light, or RGB step one at a
   time. Record the actuator, requested step, observed result, firmware, and
   stop/recovery action. The session device identifier is ephemeral; never
   publish it as a stable hardware fact. An output plan is source capability
   evidence, not a pass.
7. **Classify and hand off.** Mark each claim independently: source-backed
   (implementation/upstream support, no accepted project hardware run),
   hardware-verified only when the applicable physical observation supports
   that specific claim, or unavailable. Reserve whole-record verification for
   accepted coverage of every declared control, reconnect, and claimed output.
   Include exact commands/results,
   environment and commits, record JSON, detach use, control matrix, packet
   excerpts, parse counts/errors, reconnect result, output plan/results, and
   remaining limits. Keep external IOUSBHost/WebUSB or Linux evidence labeled
   external; it cannot silently become OJD native USB transport acceptance.

## Reference map

| Need | Load |
|---|---|
| Record schema, raw-USB scope, validation/probe output, detach policy | [`references/diagnosis.md`](references/diagnosis.md), `docs/testing/controller-record.md` |
| Compatibility identities, output and evidence meanings | `docs/user/compatibility.md`, `docs/testing/physical-output.md` |
| Experimental records and hardware limits | `docs/development/experimental-controllers.md` |
| Device-specific procedures and packet checklists | `docs/testing/` (controller-record, Steam, receiver, Razer, Nacon, Xbox, and physical-output procedures) |
| Parser harness and focused product proof | the `ojd test parsers-macos14` route, `$test-openjoystickdriver` |
| Catalog authoring or generated record changes | `$add-controller-openjoystickdriver` |
| Product implementation, UI, or topology ownership | `$maintain-openjoystickdriver`, `$design-openjoystickdriver`, `$organize-openjoystickdriver` |

## Completion criteria

- The investigation names one physical identity and transport, records the
  discovery/interface/endpoint result, and states the exact OJD commit and
  host environment used.
- Record validation and parser evidence were run through supported commands
  where applicable; parser/fixture success is explicitly separate from
  physical support and no source/prose test was added.
- Input evidence covers neutral and the controls claimed by the record,
  includes parse/error and summary results, and includes a reconnect attempt or
  an explicit hardware limitation.
- Rumble, trigger, LED, and RGB claims are each checked with the installed-app
  output plan when exposed; unsupported or untested actuators remain
  source-backed/unavailable rather than being inferred.
- The handoff classifies every claim as source-backed, hardware-verified, or
  unavailable, labels external evidence, redacts sensitive packet details, and
  names exact remaining risks. No catalog record or provenance flag was edited
  by this diagnostic slice.

## Validation instructions

Validate only this skill artifact from the repository root:

```bash
python3 "$HOME/.agents/scripts/validate_skill.py" \
  .agents/skills/debug-controller-openjoystickdriver
git diff --check -- .agents/skills/debug-controller-openjoystickdriver
```

For a controller investigation, also run the applicable supported diagnostic
routes in the order documented above. Run the `ojd diagnose record <record>
--validate-only` route before opening hardware and the `ojd test parsers-macos14`
route for parser evidence. Route product Swift
changes/tests and broad repository gates to `$test-openjoystickdriver` or the
owning implementation skill. If IOUSBHost, USBDriverKit, macOS permissions,
signing, or physical hardware is unavailable,
report the exact command, status, and limitation rather than claiming a pass.
Do not add a repo-local validator, pycache, product Sources, or Tests.

## Related skills

- `$add-controller-openjoystickdriver` — author/import records and catalog inputs.
- `$maintain-openjoystickdriver` — implement product behavior at its existing owner.
- `$test-openjoystickdriver` — add product tests and run product validation gates.
- `$design-openjoystickdriver` / `$apple-design-hig` — UI and accessibility work.
- `$organize-openjoystickdriver` — Sources/Tests topology and architecture ownership.
- `$skizzles:no-legacy-cleanup` — remove obsolete paths without compatibility shims.
