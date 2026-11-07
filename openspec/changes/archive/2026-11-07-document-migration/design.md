## Context

See proposal.md. Each reader reads `OpenJoystickDriverAPI.version` only. Kit owns parsing and
rules, so Kit owns the conversion; Python does not repeat it. The CLI and the app depend on Kit
only, and `AccessGrantFile` lives in the service target.

## Goals / Non-Goals

- Goal: one explicit step turns each convertible `v1alpha1` file into a `v1alpha2` file.
- Non-goal: a second reader, an alias, a fallback, or a migration on load.
- Non-goal: migrating installed mods.

## Decisions

- Steps are pure functions on a JSON object, keyed by kind and source version. A new version adds
  a step; the chain applies in order.
- The alpha.1 to alpha.2 mappings come from `CHANGELOG.md` and the schema diff against the tag
  `0.6.0-alpha.1`:
  - every kind: `apiVersion` becomes `openjoystickdriver/v1alpha2`;
  - `Profile`: each `doubleTap {destination, windowMs}` becomes `multiTap [{count: 2, ...}]`;
  - `Controller` and `ControllerPatch`: `input` becomes `{layouts: [input]}`, and each field
    `byte`/`mask`/`bits` becomes `bitOffset` and `bitSize` (`bitOffset = byte * 8 + lowest set bit
    of mask`, `bitSize = number of mask bits`; an axis is 8 or 16 bits, a trigger 8). A
    non-contiguous mask, or a patch `input` without `report`, has no mechanical mapping.
  - `Settings`, `AccessGrants`, `VirtualDevice`: the version only.
- The original goes to `Migrated/<folder>/<name>` in the support directory. A backup in the
  profile or record folder would be read as a second document there.
- The result is checked with the current reader before the write. The `AccessGrants` reader is in
  the service target, so Kit checks the header and the object shape, and the store's own load runs
  on the retry.
- The write is atomic.

## Risks / Trade-offs

- An unconvertible file stays as is; the wiki gives the manual fallback.
- The `AccessGrants` result is not read by the service reader before the write; its content does
  not change between the two versions.
