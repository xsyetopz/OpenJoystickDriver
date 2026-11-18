---
paths:
  - "**/*"
---

# useSingleFormat

Before `v1.0.0`, each name and shape has one lowerCamelCase spelling. Every other spelling fails with a named error. Before `v1.0.0` a schema may change in any release; readers stay single-version, and `ojd migrate` upgrades the stale documents a user keeps. Swift owns parsing and the rules; Python reads the Swift output.

```swift
let mode = Mode(rawValue: key) ?? Mode(legacyName: key)
                                  ^ error: second spelling accepted [useSingleFormat]
// fix: guard let mode = Mode(rawValue: key) else { throw CatalogError.unknownKey(key) }
```

```python
def parse_mode_choice(entry): ...
    ^ error: repeats the Swift catalog parser [useSingleFormat]
# fix: read the Swift CLI output
```
