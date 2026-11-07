---
paths:
  - "**/*"
---

# unreferenced_removal

Code is removed after every reference to it is found in the code, the tests, the docs, and the schemas.

```text
error: enableIR removed after a search of Sources/ only [unreferenced_removal]
note: rg -n enableIR Sources Tests wiki Resources/Schemas
```
