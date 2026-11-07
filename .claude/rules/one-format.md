---
paths:
  - "**/*"
---

# single_format

- **Severity:** error
- **Description:** Before `v1.0.0`, each name and shape has one valid spelling. Reject every other spelling with a named error, and add no aliases, shims, fallbacks, retries, or migrations. Schema keys are lowerCamelCase.

Non-triggering:

```swift
guard let mode = Mode(rawValue: key) else {
  throw CatalogError.unknownKey(key, file: url)
}
```

Triggering:

```swift
let mode = Mode(rawValue: key) ?? ↓Mode(legacyName: key)
```

# swift_canonical

- **Severity:** error
- **Description:** Swift owns parsing and the rules. Python calls the Swift CLI or reads its output, and never repeats that logic.

Non-triggering:

```python
report = json.loads(swift_cli_output)  # the Swift CLI did the parsing
```

Triggering:

```python
↓def parse_mode_choice(entry): ...  # repeats the Swift catalog parser
```

# schema_rejection_case

- **Severity:** warning
- **Description:** Record each catalog case that Swift rejects in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`. Set `"schema": true` only when the JSON schema alone rejects it.

Non-triggering:

```json
{ "case": "duplicateModeChoice", "schema": false }
```

Triggering:

```json
{ "case": "duplicateModeChoice", ↓"schema": true }
```

Here the schema accepts the file, and only Swift rejects it, so `"schema": true` is wrong.
