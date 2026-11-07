---
paths:
  - "Sources/**/*.lproj/**"
  - "Sources/**/*.swift"
  - "Resources/ErrorCodes.json"
  - "LOCALIZATION.md"
---

# progress_ellipsis

Work still in progress ends with `...` in `en-US`, and with `…` in translations. A finished result ends with `.` or `!`.

```strings
"…checking" = "Checking the installed Xbox USB driver.";
                                                     ^ warning: in-progress text ends with a period [progress_ellipsis]
// fix: "Checking the installed Xbox USB driver..."
```
