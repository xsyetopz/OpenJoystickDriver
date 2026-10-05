# Swift Idioms

## Contents

- [Locked state](#locked-state)
- [Blocking work](#blocking-work)
- [Strict decoding](#strict-decoding)
- [Package access](#package-access)
- [CLI errors](#cli-errors)

The package uses swift-tools-version 6.3 (Swift 6 language mode, complete concurrency checking), and source targets build for `.macOS(.v12)`.

## Locked State

**Definition.** `Locked<Value: Sendable>` in `Sources/OpenJoystickDriverKit/Concurrency/Locked.swift` is a `package final class` with a private `NSLock`, accessed through `withLock { (inout Value) in ... }`.

**Use when.** Several threads read and write plain state, and an actor would force `await` on a synchronous caller, such as an IOKit callback.

**Do not use when.**

- The state is used only from async code. Use an actor.
- The code is UI state. Use `@MainActor`.
- The closure would do I/O or call back into other code. Copy the values out, release the lock, and act after it.

**Example.**

```swift
let counter = Locked(0)
DispatchQueue.concurrentPerform(iterations: 1_000) { _ in counter.withLock { $0 += 1 } }
let total = counter.withLock { $0 }
```

**Cost removed.** It replaces about 26 hand-rolled lock boxes, each with its own `@unchecked Sendable` justification.

**Verify.** `Tests/OpenJoystickDriverKitTests/Concurrency/LockedTests.swift` covers concurrent increments and rethrow behavior.

## Blocking Work

**Definition.** `BlockingWork.run(label:_:)` and `BlockingWork.run(on:_:)` in `Concurrency/BlockingWork.swift` run a synchronous throwing closure on a dispatch queue, and resume the caller through a checked continuation.

**Use when.** Socket I/O, native device creation, or any call that can block is reached from async code.

**Do not use when.** The work is short and non-blocking. Call it directly. Never bridge in the other direction with `DispatchSemaphore` waiting on a `Task`. That pattern was removed from the CLI because it can deadlock the cooperative pool.

**Example.**

```swift
let bytes = try await BlockingWork.run(label: "ojd.rpc.read") { try socket.read(count: 4) }
```

**Verify.** `rg -n 'DispatchSemaphore|Task\.detached' Sources` finds no new blocking bridge in the changed files.

## Strict Decoding

**Definition.** A custom `init(from:)` calls `try container.rejectUnknownKeys(CodingKeys.self)` (`Sources/OpenJoystickDriverKit/Remapping/Profile/Document/StrictDecoding.swift`), where `CodingKeys` is `CaseIterable`. An unknown key at any depth throws.

**Use when.** Decoding any saved profile, controller document, or RPC payload.

**Do not use when.** Never use it to soften a failure. There is no fallback. Keep a default only for keys that the schema in `Resources/Schemas/` marks optional.

**Example.**

```swift
init(from decoder: any Decoder) throws {
  let container = try decoder.container(keyedBy: CodingKeys.self)
  try container.rejectUnknownKeys(CodingKeys.self)
  mode = try container.decode(Mode.self, forKey: .mode)
}
```

**Cost removed.** Lenient decoding ignored `gyroOutput.virtualMotion` in saved profiles without reporting it. Strict decoding makes such a profile visible as damaged.

**Verify.** Add a decoding test with one extra key, and expect it to throw.

## Package Access

**Definition.** The `package` access level makes a declaration visible to every target in this package, and to nothing outside it.

**Use when.** One target needs an internal helper from another, as with `Locked` and `BlockingWork` from Kit.

**Do not use when.** The API is meant for external consumers. Use `public` only for those. Never widen access to `public` to satisfy a test. Use `@testable import` instead.

**Verify.** `swift build` succeeds with no new `public` declarations for cross-target use.

## CLI Errors

**Definition.** Parsers throw `CLIParseError`, and commands throw `CLIExit`. Only `CLI.run(arguments:)` in `Sources/OpenJoystickDriverCLI/CLI.swift` maps errors to exit codes.

**Use when.** A command must fail with a specific exit status.

**Do not use when.** Never call `exit(...)` inside a command or parser. It skips `defer` blocks and cannot be tested.

**Verify.** A CLI test asserts on the thrown error type or the exit code, not on help text.
