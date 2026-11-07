---
paths:
  - "**/*"
---

# One format, one owner

Before `v1.0.0`, each name and each shape has one valid spelling, and one place owns the logic that reads it. Reject anything else with a named error. Don't add a second way to say the same thing.

- Validate names and shapes at the boundary, and reject the invalid ones. Add no aliases, shims, fallbacks, retries, or migrations for old forms.
- Schema keys are lowerCamelCase. Old or renamed values belong in `CHANGELOG.md`, not in the schema or the parser.
- Swift is canonical. Python calls the Swift CLI or reads its output, and never repeats its parsing or rules.
- When Swift rejects a catalog case, record it in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`. Set `"schema": true` only when the JSON schema alone rejects it.

GREEN: a profile that uses a removed key fails to load with an error that names the key and the file. The changelog entry says which key replaced it.

RED: the loader accepts both the old key and the new one, "so old profiles keep working". Two spellings are now valid, every tool has to handle both, and the old one can never be removed safely.
