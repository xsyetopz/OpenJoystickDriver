# Catalog Formats

Before `v1.0.0`, each name and shape has one lowerCamelCase spelling, and every other spelling fails with a named error. Readers stay single-version; `ojd migrate` upgrades the stale documents a user keeps. Swift owns parsing and the rules, and Python reads the Swift output.

A catalog case that Swift rejects is recorded in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`, with `"schema": true` only when the JSON schema alone rejects it.

```swift
let mode = Mode(rawValue: key) ?? Mode(legacyName: key)
                                  ^ error: second spelling accepted
// fix: guard let mode = Mode(rawValue: key) else { throw CatalogError.unknownKey(key) }
```
