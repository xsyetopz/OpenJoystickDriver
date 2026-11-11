---
paths:
  - "**/*"
---

# unwired_feature

A task is done when a caller outside `Tests/` reaches it: session startup, an RPC handler, or a CLI command. The task note names that caller.

```text
tasks.md:52:3: error: 5.2 ticked, but only Tests/ call enableIR [unwired_feature]
- [x] 5.2 Enable the IR camera.
  ^
note: call enableIR from WiiSession.start when the profile binds PointerX or PointerY
```
