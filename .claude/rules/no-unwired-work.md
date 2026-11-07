---
paths:
  - "**/*"
---

# No unwired or stubbed work

A feature is done only when the shipped app or CLI reaches it in a real session. Code that only tests call, state that is computed but never published, and stubs are unfinished work.

- Before you tick a task, trace the path from a real entry point to the effect: the session startup, the RPC handler, or the CLI command that calls the code, and the state, output, or profile source that carries its result. Name that call site in the task note.
- When only tests call a function that a task says runs in production, the task is not done. `grep` for callers outside `Tests/` before you tick it.
- When a driver computes a value that a control id names, it writes that value into the controller state, so a profile and the endpoint can use it.
- When the design says a profile can bind something, add a test that binds it and drives the output through the engine.
- Write no stubs, placeholders, `TODO` bodies, `fatalError("unimplemented")`, or empty handlers. When a slice cannot finish, leave the task unticked and report what is missing.
- Docs and the changelog say what the shipped code does. Don't describe a feature as working when it isn't wired.
