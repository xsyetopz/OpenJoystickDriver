---
name: ojd-swift-change
description: >-
  Changes OpenJoystickDriver Swift behavior and its tests inside the SwiftPM
  target and directory owners from contributing/development/source-topology.md:
  placement across Kit, USB, Service, CLI, and Presentation; Type+Concern file
  naming and the 500/1000 code-line limits; Swift 6 concurrency on a macOS
  10.15 floor (Locked, BlockingWork, actors); strict Codable decoding; and
  behavior tests. Use when fixing a bug, adding a feature, moving or splitting
  Swift files, or writing Swift tests. Not for catalog records
  (ojd-controller-catalog), SwiftUI flows (ojd-app-ui), or scripts and CI
  (ojd-repo-tooling).
---

# OpenJoystickDriver Swift Change

Make one coherent behavior change at its owner, prove it with a behavior test that fails without the change, and leave the target graph, file names, and file sizes within the checked rules.

## Workflow

1. Read `contributing/development/source-topology.md`, `Package.swift`, and the nearest source and its mirrored test directory. When `.codegraph/` exists, use `codegraph explore "<symbol>"` to find callers before editing.
1. Place the code with the [placement card](references/placement.md#target-and-directory): choose a target by its allowed dependencies, then pick the capability directory.
1. Write or extend the test first in the mirrored directory and watch it fail ([test rules](references/tests.md#behavior-tests)).
1. Make the change with the [Swift 6 idioms](references/swift-idioms.md) that the macOS 10.15 floor allows.
1. Keep files within the [naming and size rules](references/placement.md#naming-and-size).
1. Run the focused test: `swift test --filter <TestType>`. Then run `python3 Scripts/Quality/check_swift_file_length.py`, `just lint`, and `swift test --no-parallel`. For parser or protocol code, also run `./Scripts/ojd test parsers-macos14`. `just check` runs every gate. Before running `swift` or `./Scripts/ojd`, export `DEVELOPER_DIR` for the installed Xcode.

## Route the problem to a card

| Situation | Card |
| --- | --- |
| Which target or directory owns this code | [Target and directory](references/placement.md#target-and-directory) |
| File over the limit, or named `+Behavior2` | [Naming and size](references/placement.md#naming-and-size) |
| Shared mutable state across threads | [Locked state](references/swift-idioms.md#locked-state) |
| Blocking I/O called from async code | [Blocking work](references/swift-idioms.md#blocking-work) |
| Decoding a saved document or RPC payload | [Strict decoding](references/swift-idioms.md#strict-decoding) |
| Cross-target internal API | [Package access](references/swift-idioms.md#package-access) |
| CLI command error or exit code | [CLI errors](references/swift-idioms.md#cli-errors) |
| Writing or fixing a test | [Behavior tests](references/tests.md#behavior-tests) |

## Rules

- Presentation depends on Kit only. It reaches the runtime through `ApplicationServiceGateway` and injected closures. Importing Service, CLI, or USB fails to compile, and that failure is intended.
- Source targets build for macOS 10.15. `Mutex` (macOS 15), `OSAllocatedUnfairLock` (macOS 13), and `@Observable` (macOS 14) do not compile for that floor. Test targets build at a macOS 14 triple, so test-only code can hide the problem.
- Saved profiles and RPC payloads decode strictly. The repository keeps no upcasters, fallback decoders, or legacy keys (`Resources/Schemas/AGENTS.md`). An old document fails to decode and shows up as damaged.
- Do not edit `Sources/OpenJoystickDriverKit/Resources/Controllers/` or `.build/driverkit/generated/`. Both are generated.
- When code moves, delete the old path in the same change. Leave no forwarding typealiases, stubs, or empty `extension X {}` files.
- `@unchecked Sendable` needs a comment that names the lock or invariant that makes it sound. A type whose stored properties are all `Sendable` should be plain `Sendable`.

## References

- [Placement](references/placement.md): target and directory, naming and size.
- [Swift idioms](references/swift-idioms.md): locked state, blocking work, strict decoding, package access, CLI errors.
- [Tests](references/tests.md): behavior tests, prohibited tests, focused runs.

## Completion evidence

The report states the behavior changed and its owning paths. It names the test that failed before the change and passes after it, and gives the gate commands with their results and the test count. It lists any gate not run and why, plus remaining hardware, signing, or platform risk.
