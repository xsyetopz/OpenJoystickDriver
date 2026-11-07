---
paths:
  - "**/*"
---

# stub

Every body does its work. A slice that cannot finish stays unticked and is reported.

```swift
func stop() async throws { fatalError("unimplemented") }
                           ^ error: stub body [stub]
// fix: func stop() async throws { try await speaker.stop() }
```
