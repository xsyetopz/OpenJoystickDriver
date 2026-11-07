---
paths:
  - "**/*"
---

# stale_doc

- **Severity:** error
- **Description:** Comments, the wiki, the README, and schema descriptions say what the code does now. Update them in the same commit as the behavior, and document each behavior where users look: the wiki or the CLI help.

Non-triggering:

```markdown
Pointer X and Pointer Y come from the IR camera while a profile binds them.
```

Triggering:

```markdown
↓The IR camera is not used.   <!-- after the pointer was wired -->
```

# history_outside_changelog

- **Severity:** warning
- **Description:** Words like "now", "previously", "new", "used to", "renamed from", and "no longer" belong only in `CHANGELOG.md`.

Non-triggering:

```swift
/// Reads the pointer from the parsed IR state.
```

Triggering:

```swift
/// ↓Previously used the raw report; now reads the parsed IR state.
```

# protected_content

- **Severity:** error
- **Description:** Preserve SVGs exactly. Keep secrets out of the repository. Confirm before a destructive write or a publication.

Non-triggering:

```sh
git diff --stat -- '*.svg'   # empty
```

Triggering:

```sh
↓git push --force   # without confirmation
```
