---
paths:
  - "Sources/**/*.lproj/**"
  - "Sources/**/*.swift"
  - "Resources/ErrorCodes.json"
  - "LOCALIZATION.md"
---

# untranslated_string

Each key is in every `.lproj` with its comment, translated. Source English stays only for keys on the locale's allow-list in `LocalizationCatalogAudit.swift`.

```strings
"cli.controller.group.featureSpeaker" = "speaker";
                                        ^ error: id-ID leaves source English [untranslated_string]
// fix: "pengeras suara"
```
