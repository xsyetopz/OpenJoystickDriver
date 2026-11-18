---
paths:
  - "**/*"
---

# noProtectedContentEdits

SVGs stay unchanged, secrets stay out of the repository, and each destructive write or publication is confirmed first.

```sh
git push --force
^ error: publication with no confirmation [noProtectedContentEdits]
```
