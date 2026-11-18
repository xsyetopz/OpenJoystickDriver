# Localization Review 0.6.0

An AI agent reviewed the 20 non-English locales against `LOCALIZATION.md` (Meaning, Punctuation), Apple's macOS terms, CLDR plural categories, and the English source with its translator comment. No native speaker has reviewed them, so plural bundles keep their first-draft comment.

## Scope

Run each count from the repository root with `R=Sources/OpenJoystickDriverKit/Resources`.

- In-scope keys per locale: 358 (335 plain, 23 with `platform.macos.`).

  ```sh
  grep -cE '^"(platform\.macos\.)?(a11y|ui\.(sidebar|mainWindow|extra|menu|settings|library|access|controllers\.serv(er|ing))|cli\.controller\.(claim|release))\.' $R/en-US.lproj/Localizable.strings
  ```

- Plural entries: 12, each read in all 20 locales against `Resources/Localization/PluralCategories.json`.

  ```sh
  plutil -convert json -o - $R/en-US.lproj/Localizable.stringsdict | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))'
  ```

- Values with numbered specifiers: 136, each read for natural order; none needed a reorder.

  ```sh
  grep -E '^"' $R/en-US.lproj/Localizable.strings | sed 's/^"[^"]*" = //' | grep -cE '%[0-9]+\$'
  ```

Recurring terms and punctuation were checked across the whole catalog, including keys outside the scope.

## Decisions

| # | Topic | Decision |
| --- | --- | --- |
| 1 | Spanish System Settings | Follows Apple per region: es-MX "Configuración del Sistema" and "configuración"; es-ES "Ajustes del Sistema" and "ajustes". |
| 2 | nl-NL Notifications | "Meldingen" is Apple's Dutch term and stays. |
| 3a | CJK spacing (ja-JP, zh-CN, zh-TW, zh-HK, plus Korean question marks) | A half-width space separates CJK text from Latin words, digits, and placeholders: "コントローラが %d 台接続されています" and "已连接 %d 个控制器". |
| 3b | CJK punctuation | Full-width punctuation (「」“”（）：，。、；！？) takes no adjacent space. Wide spaces that align columns (for example "：  %@") stay. Ellipses are "…". |
| 3c | Questions | End in "？" (Japanese), "?" (Korean), or "หรือไม่" with no question mark (Thai). |
| 3d | Open wording | zh-TW uses 打開 and zh-HK uses 開啟, following Apple's Taiwan and Hong Kong catalogs. |
| 4a | "Socket" | Stays in it-IT, nl-NL, and vi-VN: the networking loanword (de-DE and the Spanish locales use it too). |
| 4b | "OpenJoystickDriver (virtual)" | Stays in es-ES, es-MX, pt-BR, and id-ID: "virtual" is the native word. |

## Shared Values

These shared values stay:

- ja, zh, ko, th, vi, id, and hi: one form for plural and singular.
- In some locales, one word for each pair: Off and Deactivated; Dismiss and Close; Turn On and Activate; Tokens and Token; Continue and Resume; Grant and Grant Access.
- Single-locale cases: es-MX and pt-BR "Control"; th ปิด; ru Удалить; ja 詳細, for both Details and Advanced.

## Kept English

`LocalizationCatalogAudit` keeps a key in English where the locale uses the source word.

| Kind | Keys or words | Note |
| --- | --- | --- |
| Keyboard key names | `term.key.*` | macOS prints Escape, Return, Shift, Alt, Control, Caps Lock in English |
| Product and protocol names | `term.protocolFamily.*`, `term.protocolVariant.usb`, `term.app.name` | |
| Identifiers | HID, USB ID, Y/Triangle | |
| Menu titles matching the English system title | `ui.menu.window.zoom`, `ui.menu.app.services`, `ui.settings.notifications.title`, `ui.menu.controller.title`, `ui.menu.file.title`, `ui.menu.edit.title`, `ui.menu.help.title` | fr "Services", "Zoom", "Notifications"; nl "Help", "Controller"; id "File", "Edit" |
| Dutch Controllers keys | the loanword "controller" | as in Apple's Dutch game-controller settings |
| Socket, OpenJoystickDriver (virtual) | | see decision 4 |

## Per Locale

The command counts changed values (plural strings for stringsdict).

```sh
git diff -U0 5a15374cd -- $R/<locale>.lproj/Localizable.strings | grep -c '^+[^+]'
```

`git diff 5a15374cd -- $R/<locale>.lproj/` lists every change.

| Locale | .strings | .stringsdict | Fixes |
| --- | --- | --- | --- |
| ar-SA | 12 | 0 | Apple terms (تحقّق من الصحة, يُخدَم بواسطة); one form for the suspended status |
| de-DE | 9 | 0 | scope name „Steuern“; "Pausiert"; progress "…" |
| es-ES | 12 | 3 | Apple terms (Descartar cambios, herramientas para desarrolladores); many plural with "de" |
| es-MX | 65 | 3 | "Configuración del Sistema" and "configuración"; “…” quotes; many plural with "de" |
| fr-CA | 31 | 3 | scope « Contrôle »; "manette"; ’ apostrophes; many plural with "d’" |
| fr-FR | 32 | 3 | scope « Contrôle »; "manette"; ’ apostrophes; many plural with "d’" |
| hi-IN | 10 | 0 | Undo, Quit, and Suspend (निलंबित करें) wording; टर्मिनल; comma form of the virtual gamepad label |
| id-ID | 62 | 0 | notifikasi; "file"; Apple menu names (Urungkan, Ulangi, Masuk ke Layar Penuh); “…” quotes; one form for the suspended status |
| it-IT | 21 | 3 | mod gender; "gestisce"; Socket; ’ apostrophes; many plural with "di" |
| ja-JP | 308 | 20 | CJK spacing; "App"; ユーザ and デベロッパツール; ターミナル; "？" questions; full-width parentheses |
| ko-KR | 86 | 1 | 세요 politeness level throughout; 릴리스; 터미널; "?" questions; one form for the suspended status |
| nl-NL | 40 | 0 | Socket; ’ apostrophes; ‘…’ quotes, the dominant style in the catalog; Zoeken |
| pt-BR | 5 | 3 | "OpenJoystickDriver (virtual)"; many plural with "de" |
| ru-RU | 10 | 0 | обслуживает; «…» around names |
| th-TH | 54 | 0 | Royal Institute spelling (แอป, อัปเดต); เวอร์ชัน; หรือไม่ question; one form for the suspended status |
| tr-TR | 45 | 2 | hizmet; kontrolcü; Görüntü and Küçült; ’ apostrophes and “…” quotes; lowercase "paket" in the plural |
| vi-VN | 19 | 0 | "Đóng" for Dismiss; Socket; one form for the suspended status; mod wording |
| zh-CN | 95 | 1 | CJK spacing; App; “终端”; 存储; full-width punctuation |
| zh-HK | 89 | 1 | CJK spacing; 開啟; 連線; 取用; 「終端機」 |
| zh-TW | 87 | 1 | CJK spacing; 打開; 連線; 取用; 捨棄; 「終端機」 |

ja-JP, ko-KR, hi-IN, id-ID, th-TH, tr-TR, vi-VN, zh-CN, zh-TW, and zh-HK write `ui.controllers.serving.virtualHID` in the comma form of the English source, for example "OpenJoystickDriver, 가상 게임패드".

## tr-TR Service Term

tr-TR uses servis for the OpenJoystickDriver background service. hizmet named both the service and the verb "serve" (hizmet vermek, Hizmet veren, Hizmet yolu), and stood in 92 lines. `ui.menu.app.services` keeps Hizmetler, the Turkish macOS name of the Services menu, which does not clash with servis.

The verb "serve" is sunmak. Sunma yolu uses the verbal noun, because Sunum reads as "presentation". sunmak takes the controller as object: "OpenJoystickDriver tarafından sunulmasını", "%@ kontrolcüsünü yerel olarak sunmaz".

| English | Turkish |
| --- | --- |
| Served by | Sunan |
| Serving route | Sunma yolu |
| serves a controller | sunar |
| Serves only programs | yanıt verir |
| serves 8 connections | yönetiyor |

Changed values: 24, from `git diff -U0 -- Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj | rg -c '^\+"'`. The stringsdict has no such term. The one hizmet line left (`rg -c -i hizmet Sources/OpenJoystickDriverKit/Resources/tr-TR.lproj`) is the Services menu item.

## Kept as Written

- ASCII "..." in ranges such as `%1$lld...%2$lld`, `(U-...)`, and `physical:...`, as `LOCALIZATION.md` requires.
- Half-width Japanese colons, the majority form in ja-JP.
- Korean `ui.controllers.server.ojd`: "OpenJoystickDriver(가상)" has no space before the parenthesis, per Korean orthography.

## Further Reading

- [Localization Guide](../../LOCALIZATION.md)
