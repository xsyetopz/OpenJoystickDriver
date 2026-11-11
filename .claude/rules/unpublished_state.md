---
paths:
  - "**/*"
---

# unpublished_state

A value that a control id names is written into the controller state.

```swift
let pointer = ir.position
    ^ error: PointerX/PointerY computed, never written to state [unpublished_state]
// fix: state[.pointerX] = ir.x; state[.pointerY] = ir.y
```
