# Localization Review 0.6.0

The AI agent reviewed the 20 non-English locales against `LOCALIZATION.md` (Meaning, Punctuation), Apple's localized macOS terms, CLDR plural categories, and the English source with its translator comment.
Native speakers have not reviewed them, so the plural bundles keep their first-draft comment.

## Scope

Counts come from the commands shown, run from the repository root, with `R=Sources/OpenJoystickDriverKit/Resources`.

- In-scope keys per locale: 358.
  Of these, 335 have no platform prefix and 23 carry `platform.macos.`.

  ```sh
  grep -cE '^"(platform\.macos\.)?(a11y|ui\.(sidebar|mainWindow|extra|menu|settings|library|access|controllers\.serv(er|ing))|cli\.controller\.(claim|release))\.' $R/en-US.lproj/Localizable.strings
  ```

- Plural entries: 12.
  Each was read in all 20 locales against `Resources/Localization/PluralCategories.json`.

  ```sh
  plutil -convert json -o - $R/en-US.lproj/Localizable.stringsdict | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))'
  ```

- Values with numbered specifiers: 136.
  Each was read for natural specifier order, and none needed a reorder.

  ```sh
  grep -E '^"' $R/en-US.lproj/Localizable.strings | sed 's/^"[^"]*" = //' | grep -cE '%[0-9]+\$'
  ```

Terms and punctuation that recur were checked across the whole catalog, not only the in-scope keys.
A term fixed in one key is fixed in every key that uses it.

## Decisions

1. **System Settings in Spanish.
   **
   - es-MX uses "Configuración del Sistema" and "configuración", matching Apple's Latin American Spanish.
   - es-ES uses "Ajustes del Sistema" and "ajustes", matching Apple's Spanish for Spain.
2. **Dutch notifications.** nl-NL "Meldingen" is Apple's Dutch term for Notifications and stays.
3. **CJK typography** (ja-JP, zh-CN, zh-TW, zh-HK, plus Korean question marks):
   - A half-width space separates CJK text from Latin words, digits, and placeholders, for example "コントローラが %d 台接続されています" and "已连接 %d 个控制器".
   - Full-width punctuation (「」“”（）：，。、；！？)
     takes no space next to it.
   - Wide spaces that align columns (for example "：  %@") stay.
   - Ellipses are "…".
   - Japanese and Korean questions end in "？"
     or "?".
     Thai questions end in "หรือไม่" with no question mark.
   - zh-TW uses 打開 and zh-HK uses 開啟, following Apple's Taiwan and Hong Kong catalogs.
4. **Counts.
   ** Every count in this record comes from a command shown here.
5. **Kept terms.
   **
   - "Socket" stays in it-IT, nl-NL, and vi-VN, because it is the established networking loanword. de-DE and the Spanish locales use it too.
   - "OpenJoystickDriver (virtual)" stays in es-ES, es-MX, pt-BR, and id-ID, because "virtual" is the native word there.

## Shared Values

Some locales use one word for two English source strings, because the language has a single word for both.
These shared values stay:

- **Plural and singular:** one form in ja, zh, ko, th, vi, id, and hi.
- **Same word for two English strings:**
  - Off and Deactivated
  - Dismiss and Close
  - Turn On and Activate
  - Tokens and Token
  - Continue and Resume
  - Grant and Grant Access
- **Single-locale cases:**
  - es-MX and pt-BR "Control"
  - th ปิด
  - ru Удалить
  - ja 詳細, for both Details and Advanced

## Kept English

`LocalizationCatalogAudit` keeps a key in English where the locale uses the same word as the source.
The reasons:

- **Keyboard key names** (`term.key.*`): macOS prints them in English in the locale, for example Escape, Return, Shift, Alt, Control, and Caps Lock.
- **Names and identifiers:**
  - Product and protocol names: `term.protocolFamily.*`, `term.protocolVariant.usb`, and `term.app.name`.
  - Identifiers: HID, USB ID, and Y/Triangle.
- **Menu titles that match English:** `ui.menu.window.zoom`, `ui.menu.app.services`, `ui.settings.notifications.title`, `ui.menu.controller.title`, `ui.menu.file.title`, `ui.menu.edit.title`, and `ui.menu.help.title`.
  The system menu title in that locale is the same word as English, for example fr "Services", "Zoom", and "Notifications"; nl "Help" and "Controller"; id "File" and "Edit".
- **Dutch `Controllers` keys:** Dutch uses the loanword "controller", and so do Apple's Dutch game-controller settings.
- **Socket and OpenJoystickDriver (virtual):** see decision 5.

## Per Locale

Changed values come from this command.
In the `.stringsdict` files, the count covers plural strings.

```sh
git diff -U0 5a15374cd -- $R/<locale>.lproj/Localizable.strings | grep -c '^+[^+]'
```

The full before-and-after list comes from `git diff 5a15374cd -- $R/<locale>.lproj/`.

| Locale | `.strings` | `.stringsdict` | Fixes |
| --- | --- | --- | --- |
| ar-SA | 12 | 0 | Apple terms (تحقّق من الصحة, يُخدَم بواسطة); one form for the suspended status |
| de-DE | 9 | 0 | scope name „Steuern“; "Pausiert"; progress "…" |
| es-ES | 12 | 3 | Apple terms (Descartar cambios, herramientas para desarrolladores); `many` plural with "de" |
| es-MX | 65 | 3 | "Configuración del Sistema" and "configuración"; “…” quotes; `many` plural with "de" |
| fr-CA | 31 | 3 | scope « Contrôle »; "manette"; ’ apostrophes; `many` plural with "d’" |
| fr-FR | 32 | 3 | scope « Contrôle »; "manette"; ’ apostrophes; `many` plural with "d’" |
| hi-IN | 10 | 0 | Undo, Quit, and Suspend (निलंबित करें) wording; टर्मिनल; comma form of the virtual gamepad label |
| id-ID | 62 | 0 | notifikasi; "file"; Apple menu names (Urungkan, Ulangi, Masuk ke Layar Penuh); “…” quotes; one form for the suspended status |
| it-IT | 21 | 3 | mod gender; "gestisce"; Socket; ’ apostrophes; `many` plural with "di" |
| ja-JP | 308 | 20 | CJK spacing; "App"; ユーザ and デベロッパツール; ターミナル; "？" questions; full-width parentheses |
| ko-KR | 86 | 1 | 세요 politeness level throughout; 릴리스; 터미널; "?" questions; one form for the suspended status |
| nl-NL | 40 | 0 | Socket; ’ apostrophes; ‘…’ quotes, the dominant style in the catalog; Zoeken |
| pt-BR | 5 | 3 | "OpenJoystickDriver (virtual)"; `many` plural with "de" |
| ru-RU | 10 | 0 | обслуживает; «…» around names |
| th-TH | 54 | 0 | Royal Institute spelling (แอป, อัปเดต); เวอร์ชัน; หรือไม่ question; one form for the suspended status |
| tr-TR | 45 | 2 | hizmet; kontrolcü; Görüntü and Küçült; ’ apostrophes and “…” quotes; lowercase "paket" in the plural |
| vi-VN | 19 | 0 | "Đóng" for Dismiss; Socket; one form for the suspended status; mod wording |
| zh-CN | 95 | 1 | CJK spacing; App; “终端”; 存储; full-width punctuation |
| zh-HK | 89 | 1 | CJK spacing; 開啟; 連線; 取用; 「終端機」 |
| zh-TW | 87 | 1 | CJK spacing; 打開; 連線; 取用; 捨棄; 「終端機」 |

In addition, ja-JP, ko-KR, hi-IN, id-ID, th-TH, tr-TR, vi-VN, zh-CN, zh-TW, and zh-HK write `ui.controllers.serving.virtualHID` in the comma form of the English source, for example "OpenJoystickDriver, 가상 게임패드".

## tr-TR service term

The tr-TR catalog uses `servis` for the OpenJoystickDriver background service. `servis` already stood in 92 lines. `hizmet` named the same service in some values and the verb "serve" in others (`hizmet vermek`, `Hizmet veren`, `Hizmet yolu`), so it covered two concepts. `ui.menu.app.services` keeps `Hizmetler`, the Turkish macOS name of the Services menu; that is a different concept from the daemon, so it does not clash with `servis`.

The verb "serve" (labels "Served by" and "Serving route", "serves a controller") is `sunmak`: `Sunan`, `Sunma yolu`, `sunar`. `Sunma yolu` takes the verbal noun because `Sunum` reads as "presentation". `sunmak` takes the controller as its object: "OpenJoystickDriver tarafından sunulmasını", "%@ kontrolcüsünü yerel olarak sunmaz". "Serves only programs" is `yanıt verir`, because the service answers only granted programs, and "serves 8 connections" is `yönetiyor`.

Changed values: 24, counted with `git diff -U0 -- Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj | rg -c '^\+"'`. The `.stringsdict` has no such term. The one remaining `hizmet` line, from `rg -c -i hizmet Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj`, is the Services menu item.

## Kept as Written

- **ASCII "..." in ranges:** values such as `%1$lld...%2$lld`, `(U-...)`, and `physical:...` keep it, because `LOCALIZATION.md` fixes numeric and identifier ranges to it.
- **Japanese colons:** they stay half-width, which is the majority form in the ja-JP catalog.
- **Korean `ui.controllers.server.ojd`:** "OpenJoystickDriver(가상)" has no space before the parenthesis, following Korean orthography.
