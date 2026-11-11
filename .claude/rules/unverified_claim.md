---
paths:
  - "**/*"
---

# unverified_claim

A claim rests on a source line, test, schema, or capture from this session. A wrong design or task is fixed and reported.

```text
report.md:3:1: error: claim with no run behind it [unverified_claim]
All tests should pass now.
^
note: swift test --filter LocalizationTests → 37 tests passed
```
