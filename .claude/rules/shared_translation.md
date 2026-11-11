---
paths:
  - "Sources/**/*.lproj/**"
  - "Sources/**/*.swift"
  - "Resources/ErrorCodes.json"
  - "LOCALIZATION.md"
---

# shared_translation

Different English texts have different translations within a locale.

```strings
"ui.profiles.pointerSpeed.driver" = "Control";
                                    ^ error: es-MX already uses "Control" for another English text [shared_translation]
// fix: "Entrada de escala"
```
