# Evidence and Completion

A claim rests on a source line, test, schema, or capture from this session. Run the narrow check, then `just verify` once, and rerun only what failed.

A task is ticked when every body does its work, each value a control id names reaches the controller state, and a caller outside `Tests/` reaches it: session startup, an RPC handler, or a CLI command. The task note names that caller. A hardware task also needs a capture from that hardware; without one it stays unticked and is reported as hardware-gated.

```text
report.md:3:1: error: claim with no run behind it
All tests should pass now.
note: swift test --filter LocalizationTests → 37 tests passed
```

```swift
func stop() async throws { fatalError("unimplemented") }
                           ^ error: stub body
// fix: func stop() async throws { try await speaker.stop() }
```
