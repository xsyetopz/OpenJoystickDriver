---
paths:
  - "Sources/**/*.lproj/**"
  - "Sources/**/*.swift"
  - "Resources/ErrorCodes.json"
  - "LOCALIZATION.md"
---

Review each string change against `LOCALIZATION.md`.

# untranslated_string

- **Severity:** error
- **Description:** Each key ships in every `.lproj` with its comment, and each locale translates it. Source English stays only for keys on that locale's allow-list in `LocalizationCatalogAudit.swift`.

Non-triggering:

```strings
"cli.controller.group.featureSpeaker" = "pengeras suara";
```

Triggering (`id-ID`):

```strings
"cli.controller.group.featureSpeaker" = ↓"speaker";
```

# shared_translation

- **Severity:** error
- **Description:** Different English texts keep different translations within a locale.

Non-triggering (`es-MX`):

```strings
"ui.profiles.pointerSpeed.driver" = "Entrada de escala";
```

Triggering (`es-MX`):

```strings
"ui.profiles.pointerSpeed.driver" = ↓"Control";  // the same text as the "Controller" key
```

# progress_ellipsis

- **Severity:** warning
- **Description:** A string for work still in progress ends with an ellipsis: ASCII `...` in `en-US`, and the native `…` in translations. A finished result ends with a period, or with `!` where it fits. A menu item follows Apple's menu rule in `LOCALIZATION.md`.

Non-triggering:

```strings
"…checking" = "Checking the installed Xbox USB driver...";
"…installed" = "The Xbox USB driver is installed.";
```

Triggering:

```strings
"…checking" = "Checking the installed Xbox USB driver↓.";
```
