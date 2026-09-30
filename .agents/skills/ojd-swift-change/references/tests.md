# Tests

## Behavior tests

**Definition.** A test calls a Swift API, through `public` or `package` access or `@testable import`, and asserts on one of the following: a typed result, state transition, event, route, exit code, identifier, or invariant. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).

**Use when.** Every behavior change and every bug fix. The test must fail without the change; run it before the fix and record the failure.

**Do not use when.** A claim needs hardware. A packet fixture proves parsing, not a physical controller; hand that claim to `ojd-hardware-evidence`.

**Example.**

```swift
@Test
func withLockRethrowsAndKeepsEarlierMutations() {
  let value = Locked(1)
  #expect(throws: Failure()) {
    try value.withLock { value in
      value = 2
      throw Failure()
    }
  }
  #expect(value.withLock { $0 } == 2)
}
```

**Verify.** `swift test --filter <TestType>` passes with the change and fails when you revert it.

## Prohibited tests

These rules come from `AGENTS.md`, `LOCALIZATION.md`, and `contributing/development/source-topology.md`:

- No test reads Swift source, scripts, docs, or generated output to assert substrings or regex matches. Those tests break on harmless edits and pass on broken behavior.
- No test asserts human-readable help, diagnostics, or localized prose. Wording changes per locale.
- No `Tests/Scripts`, and no Swift test of shell or Python behavior. Python tests go in `Tests/RepositoryScripts/` (see `ojd-repo-tooling`).
- No mock of the unit under test. It cannot catch that unit's defect.

## Focused runs

| Change | Run first |
| --- | --- |
| Parser, protocol, or HID | `swift test --filter <ParserTest>`, then `./Scripts/ojd test parsers-macos14` |
| Service runtime, RPC, remapping library | `swift test --filter OpenJoystickDriverServiceTests.<Type>` |
| CLI | `swift test --filter OpenJoystickDriverCLITests.<Type>` |
| Presentation | `swift test --filter OpenJoystickDriverPresentationTests.<Type>` |
| USB transport | `swift test --filter OpenJoystickDriverUSBTests.<Type>` |
| Generator or DriverKit | the matching test, then `./Scripts/ojd check driverkit` |

Then run `swift test --no-parallel` and compare the passed count with the count before the change. Use `./Scripts/ojd repair swiftpm-module-cache` only for the SwiftPM module-cache mismatch error, then rerun the failed command.
