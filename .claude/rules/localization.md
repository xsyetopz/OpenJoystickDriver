---
paths:
  - "Sources/**/*.lproj/**"
  - "Sources/**/*.swift"
  - "Resources/ErrorCodes.json"
  - "LOCALIZATION.md"
---

# Every string is translated, and punctuation shows its state

Review every string change against `LOCALIZATION.md`. Each new key ships in every bundle with its comment, and each locale translates it, unless the audit lists that key as a name or a non-linguistic value.

- Add a key to `en-US` with a comment that says where it appears. Copy the key and the comment into every `.lproj`, and translate the value.
- Different English texts keep different translations in each locale. When two of them come out the same, reword one.
- A string that shows work in progress ends with an ellipsis: ASCII `...` in the English source, and the native `…` in translations. A finished result ends with a period, or with an exclamation mark where it fits. A menu item gets an ellipsis only under Apple's menu rule in `LOCALIZATION.md`.
- When you leave source English in a locale on purpose, add the key to that locale's allow-list in `LocalizationCatalogAudit.swift`, and say why.
- After you change `Resources/ErrorCodes.json`, run `./Scripts/ojd errors regenerate --write`.

GREEN: the status line reads "Checking the installed Xbox USB driver..." while the check runs, then "The Xbox USB driver is installed." when it finishes.

RED: the status line reads "Checking the installed Xbox USB driver." while the check is still running, so it looks finished. And id-ID left `cli.controller.group.featureSpeaker` as the English "speaker", which failed `everyNonEnglishLocaleTranslatesSourceEnglishProse`.
