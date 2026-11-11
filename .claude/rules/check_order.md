---
paths:
  - "**/*"
---

# check_order

Build once, run the narrow test, then run `just check` once, and rerun only the failures.

```sh
just check && just check
              ^ warning: full rerun after one failed step [check_order]
```
