---
paths:
  - "**/*"
---

# stale_doc

Comments, the wiki, and schema descriptions say what the code does now. They change in the same commit as the behavior.

```text
wiki/Wii-Remote.md:41:1: error: describes the old behavior [stale_doc]
The IR camera is not used.
^
note: Pointer X and Pointer Y come from the IR camera while a profile binds them.
```
