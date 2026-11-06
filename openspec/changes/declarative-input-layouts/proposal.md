# Proposal: declarative input layouts

Status: proposal. This folder holds planning files only; no code is changed by it. Target release: alpha.2 (maintainer decision, 2026-10-25: every area is part of alpha.2). Hardware checks go to the Discord testers through tester builds (`docs/development/tester-builds.md`).

## Why

The requirement "Declarative input layout" in `openspec/changes/platform-neutral-redesign/specs/controller-records/spec.md:26-39` (scenario "Twelve-bit stick") is not implemented, and no task or test covers it. `Resources/Schemas/controller.schema.json` lets an axis be `bits: 8|16` at a whole `byte` of 0-63 (`controller.schema.json:945-960`), and every button, hat and trigger field is a `byte` plus an 8-bit `mask` (`controller.schema.json:892-908`, `:909-944`). A 12-bit stick, a 10-bit stick, a 16-bit trigger that starts at a bit, or a field that crosses a byte cannot be written as data.

Two more gaps block work that is planned next. The Wii remote sends one of several report layouts selected by report ID (report modes 0x30-0x3F, research notes `input-config.md:6`), and a record can hold one layout only. The SDL_GameControllerDB import (change `sdl-gamecontrollerdb-import`) needs HID usage map kinds that `hidUsageMap` lacks: `Button`, `Axis` and `Hat` are the only three (`ControllerRecordDocument+HIDUsageMap.swift:132`).

## What Changes

- **BREAKING** Every input field is addressed by `bitOffset` and `bitSize` (1 to 32), counted from bit 0 of report byte 0. The keys `byte`, `mask` and `bits` of input fields are removed in the same change; the five files that use them are rewritten (`Resources/Controllers/2563/2563-0575.json`, `Resources/ControllerPatches/046d/046d-cad1.patch.json`, `Resources/Protocols/vendor-flydigi.json`, `Resources/Protocols/xbox-xid.json`, `Resources/Protocols/nintendo-switch-input-only.json`).
- Axes and triggers gain `byteOrder` (`LittleEndian` or `BigEndian`, byte-aligned fields only), `signed`, and a `min` and `max` of 32-bit width.
- **BREAKING** `input` holds `layouts`, a list of layouts, each selected by report ID and length. A report that no layout selects is ignored by a named rule. Layouts whose selectors overlap are rejected.
- `hidUsageMap` gains four kinds: `HalfAxis`, `AxisDpad`, `AxisButton` and `ButtonTrigger`. A usage may appear once per half.
- The 64-byte ceiling for a layout report is kept and named; no family that a layout describes reads a longer report (see `design.md`, decision 6).
- Swift decodes and validates; the schema carries the same shapes. Python validates records only through Swift output. Generated records are regenerated with `./Scripts/ojd catalog regenerate --write`, never edited.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `controller-records`: adds requirements for bit-addressed fields, wide-value normalization, the report length ceiling, conditional layouts and the HID usage map kinds. `controller-records` exists only in the open change `platform-neutral-redesign`, not yet in `openspec/specs/`, so the delta is written as ADDED requirements with names that do not repeat that change's "Declarative input layout"; archive this change after `platform-neutral-redesign`.

## Impact

- `Resources/Schemas/controller.schema.json` (`inputField`, `inputButton`, `inputAxis`, `inputHatSource`, `inputTrigger`, `input`, `hidUsage`), and `Resources/Schemas/protocol-description.schema.json` where it describes the input layout.
- `Sources/OpenJoystickDriverKit/Protocol/Catalog/`: `ControllerInputLayout.swift`, `ControllerRecordDocument+InputLayout.swift`, `HIDUsageMap.swift`, `ControllerRecordDocument+HIDUsageMap.swift`; `Protocol/Drivers/Generic/ReportLayoutDriver.swift` and `HIDDescriptorDriver.swift`.
- Authored inputs listed above; the generated copies under `Sources/OpenJoystickDriverKit/Resources/Controllers/046d/046d-cad1.json` and `.../2563/2563-0575.json` change only through regeneration.
- `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/`, `Tests/HIDUsageGolden/hid-usage-layouts.txt`, `Tests/EquivalenceSnapshots`.
- `wiki/Controller-Records.md` (input section, lines 96-99, and the `hidUsageMap` section, lines 313-320), `Resources/Schemas/AGENTS.md` only if its rules change, `CHANGELOG.md`.

## Out of scope

- A Wii remote record or driver. No Wii file exists in the repository; it is its own change in alpha.2, and this change only makes the layout selection a Wii record needs possible.
- The SDL_GameControllerDB import itself (change `sdl-gamecontrollerdb-import`).
- Reports longer than 64 bytes (no consumer; see `design.md`).
- Extension slots, handshake scripts, checksums and reply-bound values from the research design (`input-config.md:10`).
- Any compatibility reader for the removed keys. Before `v1.0.0` they fail like any invalid input.
