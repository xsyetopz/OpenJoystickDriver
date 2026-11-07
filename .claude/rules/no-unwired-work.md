---
paths:
  - "**/*"
---

# unwired_feature

- **Severity:** error
- **Description:** A feature is done only when the shipped app or CLI reaches it in a real session. Before you tick a task, find a caller outside `Tests/`, such as the session startup, an RPC handler, or a CLI command, and name it in the task note. When the design says a profile can bind something, a test binds it and drives the output through the engine.

Non-triggering:

```swift
// WiiSession.start
if profile.binds(.pointerX) || profile.binds(.pointerY) { try await enableIR() }
```

Triggering:

```text
↓- [x] 5.2 Enable the IR camera.   // enableIR is called only from Tests/
```

# unpublished_state

- **Severity:** error
- **Description:** When a driver computes a value that a control id names, it writes that value into the controller state, so a profile and the endpoint can read it.

Non-triggering:

```swift
state[.pointerX] = ir.x
state[.pointerY] = ir.y
```

Triggering:

```swift
let ↓pointer = ir.position   // computed, never written to state
```

# stub

- **Severity:** error
- **Description:** Write no stubs, placeholders, `TODO` bodies, `fatalError("unimplemented")`, or empty handlers. When a slice cannot finish, leave the task unticked and report what is missing. Docs and the changelog describe only wired behavior.

Non-triggering:

```swift
func stop() async throws { try await speaker.stop() }
```

Triggering:

```swift
func stop() async throws { ↓fatalError("unimplemented") }
```
