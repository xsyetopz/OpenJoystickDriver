---
paths:
  - "Sources/**/*.lproj/**"
  - "Sources/**/*.swift"
  - "Resources/ErrorCodes.json"
  - "LOCALIZATION.md"
---

# noUntranslatedStrings

Each key is in every `.lproj` with its comment, translated. Source English stays only for keys on the locale's allow-list in `LocalizationCatalogAudit.swift`. Different English texts have different translations within a locale. Work still in progress ends with `...` in `en-US`, and with `…` in translations; a finished result ends with `.` or `!`.

```strings
"cli.controller.group.featureSpeaker" = "speaker";
                                        ^ error: id-ID leaves source English [noUntranslatedStrings]
// fix: "pengeras suara"
```

```strings
"ui.profiles.pointerSpeed.driver" = "Control";
                                    ^ error: es-MX already uses "Control" for another English text [noUntranslatedStrings]
// fix: "Entrada de escala"
```

```strings
"…checking" = "Checking the installed Xbox USB driver.";
                                                     ^ warning: in-progress text ends with a period [noUntranslatedStrings]
// fix: "Checking the installed Xbox USB driver..."
```
