---
paths:
  - "**/*"
---

# history_outside_changelog

History ("now", "previously", "new", "renamed from", "no longer") is only in `CHANGELOG.md`.

```swift
/// Previously used the raw report; now reads the parsed IR state.
    ^ warning: history outside CHANGELOG.md [history_outside_changelog]
// fix: /// Reads the pointer from the parsed IR state.
```
