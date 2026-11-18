---
paths:
  - "**/*"
---

# noUnverifiedClaims

A claim rests on a source line, test, schema, or capture from this session. A wrong design or task is fixed and reported. Build once, run the narrow test, then run `just check` once, and rerun only the failures.

```text
report.md:3:1: error: claim with no run behind it [noUnverifiedClaims]
All tests should pass now.
^
note: swift test --filter LocalizationTests → 37 tests passed
```

```sh
just check && just check
              ^ warning: full rerun after one failed step [noUnverifiedClaims]
```
