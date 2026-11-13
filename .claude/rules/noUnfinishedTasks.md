---
paths:
  - "**/*"
---

# noUnfinishedTasks

A task is ticked when every body does its work, a value a control id names is written into the controller state, and a caller outside `Tests/` reaches it: session startup, an RPC handler, or a CLI command. The task note names that caller. A hardware task also needs a capture from that hardware. A task short of this stays unticked and is reported, a hardware one as hardware-gated.

```swift
func stop() async throws { fatalError("unimplemented") }
                           ^ error: stub body [noUnfinishedTasks]
// fix: func stop() async throws { try await speaker.stop() }
```

```swift
let pointer = ir.position
    ^ error: PointerX/PointerY computed, never written to state [noUnfinishedTasks]
// fix: state[.pointerX] = ir.x; state[.pointerY] = ir.y
```

```text
tasks.md:52:3: error: 5.2 ticked, but only Tests/ call enableIR [noUnfinishedTasks]
- [x] 5.2 Enable the IR camera.
  ^
note: call enableIR from WiiSession.start when the profile binds PointerX or PointerY
```

```text
tasks.md:40:3: error: ticked with no capture [noUnfinishedTasks]
- [x] T3 Capture the 310B report over Bluetooth LE.
  ^
```
