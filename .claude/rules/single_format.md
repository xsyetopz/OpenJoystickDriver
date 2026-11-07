---
paths:
  - "**/*"
---

# single_format

Before `v1.0.0`, each name and shape has one lowerCamelCase spelling. Every other spelling fails with a named error.

```swift
let mode = Mode(rawValue: key) ?? Mode(legacyName: key)
                                  ^ error: second spelling accepted [single_format]
// fix: guard let mode = Mode(rawValue: key) else { throw CatalogError.unknownKey(key) }
```
