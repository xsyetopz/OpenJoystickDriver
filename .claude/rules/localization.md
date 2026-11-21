# Localization

Each key is in every `.lproj` with its comment, translated. Source English stays only for keys on the locale's allow-list in `LocalizationCatalogAudit.swift`, and different English texts get different translations within a locale. In-progress text ends with `...` in `en-US` and `…` in translations; a finished result ends with `.` or `!`.

```strings
"cli.controller.group.featureSpeaker" = "speaker";
                                        ^ error: id-ID leaves source English
// fix: "pengeras suara"
```
