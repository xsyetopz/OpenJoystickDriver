---
paths:
  - "**/*"
---

# schema_rejection_case

A catalog case that Swift rejects is recorded in `Tests/OpenJoystickDriverKitTests/Protocol/Catalog/SchemaRejections/`. `"schema": true` marks a case that the JSON schema alone rejects.

```json
{ "case": "duplicateModeChoice", "schema": true }
                                 ^ error: the schema accepts this case, so Swift rejects it [schema_rejection_case]
```
