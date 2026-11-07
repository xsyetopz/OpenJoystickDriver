---
paths:
  - "**/*"
---

# Claim only what a check showed

A statement about the code, a task tick, or a report line rests on evidence from this session: the source, a test, a schema, or a capture from hardware. Run checks in order, from the narrowest to the widest, and run each one once.

- Follow the active change in `openspec/changes/`. When its design or tasks are wrong, fix them and say so in the report.
- Tick a hardware task only with a capture or a log from that hardware. Without one, leave it unticked and list it as hardware-gated.
- Build once. Run the narrow test for the code you changed (one suite or one filter), then run `just check` once, and rerun only what failed. `just check-fast` skips the build and the tests.
- Before you remove code, find every reference to it, in the code, the tests, the docs, and the schemas.

GREEN: "`swift test --filter LocalizationTests` passed with 37 tests. `just check` failed only on `catalog regenerate --check`, which was fixed and rerun." The report gives the commands and the results.

RED: "all tests should pass now" after an edit, with no run. Or a hardware task ticked because the parser test passed, with no capture from the controller.
