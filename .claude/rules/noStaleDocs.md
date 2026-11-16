---
paths:
  - "**/*"
---

# noStaleDocs

Comments, the wiki, and schema descriptions say what the code does now, and change in the same commit as the behavior. History ("now", "previously", "new", "renamed from", "no longer") is only in `CHANGELOG.md`. Code is removed after every reference to it is found in the code, the tests, the docs, and the schemas.

```text
wiki/Wii-Remote.md:41:1: error: describes the old behavior [noStaleDocs]
The IR camera is not used.
^
note: Pointer X and Pointer Y come from the IR camera while a profile binds them.
```

```swift
/// Previously used the raw report; now reads the parsed IR state.
    ^ warning: history outside CHANGELOG.md [noStaleDocs]
// fix: /// Reads the pointer from the parsed IR state.
```

```text
error: enableIR removed after a search of Sources/ only [noStaleDocs]
note: rg -n enableIR Sources Tests wiki Resources/Schemas
```
