---
paths:
  - "**/*"
---

# unverified_claim

- **Severity:** error
- **Description:** Every claim, task tick, and report line rests on evidence from this session: the source, a test, a schema, or a capture from hardware. Follow the active `openspec/changes/` change, and when its design or tasks are wrong, fix them and say so.

Non-triggering:

```text
swift test --filter LocalizationTests → 37 tests passed
```

Triggering:

```text
↓All tests should pass now.
```

# hardware_tick_without_capture

- **Severity:** error
- **Description:** Tick a hardware task only with a capture or a log from that hardware. Without one, leave it unticked and report it as hardware-gated.

Non-triggering:

```markdown
- [ ] T3 Capture the 310B report over Bluetooth LE.  (hardware-gated)
```

Triggering:

```markdown
↓- [x] T3 Capture the 310B report over Bluetooth LE.  (the parser test passes)
```

# check_order

- **Severity:** warning
- **Description:** Build once, run the narrow test for the changed code, then run `just check` once, and rerun only the failures. `just check-fast` skips the build and the tests.

Non-triggering:

```sh
just build-dev && swift test --filter WiiRemote && just check
```

Triggering:

```sh
just check && ↓just check   # a full rerun when one step failed
```

# unreferenced_removal

- **Severity:** error
- **Description:** Before you remove code, find every reference to it in the code, the tests, the docs, and the schemas.

Non-triggering:

```sh
rg -n 'enableIR' Sources Tests wiki Resources/Schemas   # then remove
```

Triggering:

```text
↓removed `enableIR` after checking only `Sources/`
```
