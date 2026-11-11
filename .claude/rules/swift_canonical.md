---
paths:
  - "**/*"
---

# swift_canonical

Swift owns parsing and the rules. Python reads the Swift output.

```python
def parse_mode_choice(entry): ...
    ^ error: repeats the Swift catalog parser [swift_canonical]
# fix: read the Swift CLI output
```
