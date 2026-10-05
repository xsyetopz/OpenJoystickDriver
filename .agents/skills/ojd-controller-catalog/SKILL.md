---
name: ojd-controller-catalog
description: >-
  Adds or patches an OpenJoystickDriver controller identity through the
  pinned-source lockfile, Resources/ControllerOverrides add/patch files, or a
  protocol driver under Protocol/Drivers/<family>, then regenerates and checks
  the generated catalog. Use when a VID/PID is missing, misclassified, or needs
  an endpoint, configuration, or quirk fix. Not for probing physical hardware
  (use ojd-hardware-evidence) or general Swift changes (use ojd-swift-change).
---

# OpenJoystickDriver Controller Catalog

Change one controller identity or one factual device deviation through the authored catalog inputs, regenerate once, and prove the generated diff contains only that change. Generated records are output; the authored inputs are the source of truth.

## Workflow

1. Read `Resources/Schemas/AGENTS.md`, `docs/development/xpad-import.md`, and `docs/testing/controller-record.md`.
1. Find the current record: `rg -l '"productID": <decimal pid>' Sources/OpenJoystickDriverKit/Resources/Controllers` and check `Resources/ControllerOverrides/<vid>/` for an existing override.
1. Choose the input from the [authored-inputs card](references/catalog-inputs.md#authored-inputs): lockfile revision, override `add`, override `patch`, or a Swift driver.
1. Write the authored change. Use decimal JSON numbers, lowercase hex file paths, and lowerCamelCase keys.
1. Regenerate once with `./Scripts/ojd catalog regenerate --write`, then read the whole generated diff (`git diff --stat -- Sources/OpenJoystickDriverKit/Resources/Controllers`).
1. Run `./Scripts/ojd catalog regenerate --check`, `./Scripts/ojd check profiles`, and `./Scripts/ojd check schemas`. For a driver change, also run the matching `swift test --filter` and `./Scripts/ojd test parsers-macos14`. The full gate list is `just check-fast` / `just check` and `AGENTS.md`.
1. Report with the [evidence class](references/catalog-inputs.md#evidence-classes) of each claim.

## Route the Change To a Card

| Situation | Card |
| --- | --- |
| VID/PID absent from every upstream source | [Override add](references/catalog-inputs.md#override-add) |
| Upstream record exists but one section is wrong on macOS | [Override patch](references/catalog-inputs.md#override-patch) |
| Upstream fixed or added the device in a newer revision | [Lockfile revision](references/catalog-inputs.md#lockfile-revision) |
| New report format, handshake, or output encoding | [Protocol driver](references/catalog-inputs.md#protocol-driver) |
| Deciding what the change proves | [Evidence classes](references/catalog-inputs.md#evidence-classes) |

## Rules

- Never edit `Sources/OpenJoystickDriverKit/Resources/Controllers/`. The next `regenerate --write` overwrites hand edits, and `regenerate --check` fails on them in CI.
- An `add` that collides with a Linux-derived VID/PID fails generation; use a `patch` for a device upstream already knows.
- A `patch` sets only the top-level sections that are wrong, and each set section replaces the upstream one whole (shallow merge). Setting only the changed field drops its siblings; copying the whole record freezes upstream fields that later revisions fix.
- Records hold operational facts only. Provenance, confidence, `experimental`, or `needsHardwareTest` fields are rejected by the strict schemas; record evidence in `docs/testing/` pages instead.
- Shared parsing lives in Swift under `Sources/OpenJoystickDriverKit/Protocol/`. A record field that re-describes parser behavior duplicates it and drifts.
- Do not infer a VID/PID, endpoint, or report length from a similar product. Neighbouring PIDs often differ in transport or handshake.
- Passing generators and schema checks prove the record's shape, not that the controller works. Hand hardware claims to `ojd-hardware-evidence`.

## References

- [Catalog inputs](references/catalog-inputs.md): authored inputs, override add and patch, lockfile revision, protocol driver, evidence classes.

## Completion Evidence

The report names the authored files changed, the generated records that changed (and that nothing else did), the check commands with results, the evidence class of every support claim, and any hardware, signing, or platform behavior left unverified.
