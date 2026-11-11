## What's Changed

### 8BitDo Ultimate 2C Wireless
* Rumble works over the 2.4 GHz receiver and the USB cable when the pad is in XInput mode. <!-- maintainer's own pad, reported 2026-11-11; Reddit r/GeForceNOW 1xr62z7 (dongle); evidence/2c-receiver-310a/rumble-6s.txt records the writes only -->
* Over Bluetooth LE, every control decodes correctly except the two rear buttons. <!-- 51282caa5, evidence/2c-bluetooth-301b/ojd-watch-120s.txt -->
* The receiver in DInput mode lists no controller while no pad is linked, and serves the pad once it is linked. <!-- fb958572f, 8a4003d71 -->
* The Controllers list titles a device OJD does not serve with its product name, such as `8BitDo Ultimate 2C Wireless Controller`. A receiver with no pad linked reads `Wireless receiver`. <!-- cf39f591f -->
* The 8BitDo bootloader identities `2DC8:3208` and `2DC8:5750` are sent no data. <!-- 983f4562f -->

### Other controllers
* Flydigi Vader 4 Pro over Bluetooth in XInput mode: the sticks use their full range and Home registers. <!-- bcb3739a2 -->
* Flydigi Vader 4 Pro dongle: rumble is on. <!-- bcb3739a2 -->
* Flydigi Vader 5S: the USB startup steps run in the order the controller needs. <!-- 27a294eed -->
* Xbox 360 wireless receivers (`045E:02A9`, `045E:0719`): input is decoded, and empty receiver slots do not show as controllers. <!-- 406c9042b, 7b5cdd4b9; add PR #64 once merged -->
* Xbox Elite Series 1 (`045E:02E3`): OJD uses the right USB endpoints. <!-- 5f7633ba5 -->
* Razer Wolverine V3 Tournament Edition (`1532:0A43`): OJD uses the right USB endpoints. <!-- 448e213c6 -->
* PowerA XBX Spectra Enhanced Wired (`20D6:4002`) and Turtle Beach Rematch Advanced Wired (`10F5:711E`) have records. <!-- 41b363383, 1601e35b4 -->
* Thrustmaster Ferrari 458 Spider wheel (`044F:B671`): steering and brake are read. <!-- ed18df398, 87d85c60c -->
* GameSir G7 Pro dongle (`3537:1022`): OJD can read the dongle's HID gamepad interface. <!-- f5cbcab80 -->

Several of these come from reporters' captures and were not checked on the maintainer's hardware: the Vader 4 Pro records, the Vader 5S startup, the Xbox 360 receiver in the app, the Elite Series 1 and the G7 Pro dongle. <!-- openspec/changes/0-6-0-alpha-3/drafts/changelog-entries.md -->

### USB driver extension
* OJD asks for the Xbox USB driver extension only after you act. <!-- 99678eb32 -->
* Xbox controllers that no driver owns are served over direct USB. <!-- 6ab27c1d1 -->
* The banner shows only while a connected controller needs the extension. It shows progress and the result of each request. <!-- 5bda6a419 -->
* Models that macOS serves are listed as served by macOS, with a Claim button. <!-- 557f0a80b -->
* A controller that has sent no input yet shows "Waiting for the first input...". <!-- 589dc6b4a -->
* A USB start that keeps failing stops after five tries. <!-- 85dbb6bdb -->

### Old files and profiles
* `ojd migrate` converts files from earlier alphas to the current format and keeps each original in `Migrated/`. <!-- 1834b2255, 456d21064 -->
* The service migrates your files when it starts. <!-- bc4daafb0 -->
* Every screen that reports `E5001` offers a Migrate button. <!-- 356aa9bca -->
* A profile can name several apps. You choose them from a list of running and installed apps. <!-- a5834ea91, c9800b055 -->
* Status shows the profile in force and the app that selected it. <!-- a1b6015b7 -->

### Menu bar and window
* The menu bar menu has one row per controller, with its battery and profile. <!-- 30111b349 -->
* Each problem has its own row at the top, and the row opens the fix. <!-- 542541b52 -->
* The menu bar icon changes while a problem exists. <!-- 83878a347 -->
* You can drag the menu bar item out with Command. <!-- c9b731983 -->
* Every toolbar action has a menu command, and Edit has Find. <!-- fbc9fe9a9, 6bf9438d7 -->
* Settings controls that cannot change say why. <!-- e78800f1a -->
* A failed request shows its reason beside the control that sent it. <!-- 223743198 -->
* Input Test applies the player indicator when you choose it. <!-- a4b9bb20c -->

### Add support for your own controller
* A patch, a record or a generator script adds a controller without a source change. <!-- c92100832 -->
* `ojd generate` runs a JavaScript file and writes the documents it returns. <!-- 0fe33ba52 -->
* `ojd record draft` drafts a record for a connected controller that OJD does not serve. <!-- 7f730c5f7 -->
* `ojd protocol validate`, `install` and `list` manage documented protocol families. <!-- ae9adc1ef -->
* Shortcuts and the local endpoint can set a profile value, rumble a controller and read the mod list. <!-- 8dc51099c, ca9f447e5, 5b44dbcc3 -->

### Changes that need your attention
* Stored documents are XML property lists (`.plist`) with the version `openjoystickdriver/v1alpha3`. Run `ojd migrate` if the app reports `E5001`. <!-- ce2b9f8ce, af9cc004f -->
* A profile uses `appIDs`, a list, in place of `appID`. <!-- a5834ea91 -->
* `idle` is a key of a mode and names its reason. <!-- 5b8c99b50 -->
* A patch deletes a key through a `remove` list. <!-- 1bf2b2ac6 -->
* OJD is licensed under MPL-2.0. <!-- c1fef0594 -->

## Known limitations
* Bluetooth LE rumble cannot work on macOS because the 8BitDo Ultimate 2C has no GATT characteristic for its output report. <!-- evidence/2c-bluetooth-301b/rumble-gatt.txt -->
* Over Bluetooth LE, OJD leaves the 8BitDo Ultimate 2C to macOS, and macOS lists no controller for it, so games see none until you run `ojd controller claim 2DC8:301B`. <!-- evidence/2c-bluetooth-301b/serving.txt, evidence/2c-bluetooth-301b/gamecontroller-probes.txt -->
* On the receiver in DInput mode, the 8BitDo Ultimate 2C has no rumble and its controls have no names. <!-- docs/testing/8bitdo-ultimate-2c.md, evidence/2c-receiver-301c/rumble-writes.txt -->
* The rear buttons of the 8BitDo Ultimate 2C have no bit of their own on the receiver in XInput mode. <!-- docs/testing/8bitdo-ultimate-2c.md, evidence/2c-receiver-310a/rear-square-star-45s.txt -->
* The 8BitDo Ultimate 2C battery level reads zero over Bluetooth LE. <!-- evidence/2c-bluetooth-301b/serving.txt -->

## Solved Issues
Fixes #34 <!-- fb958572f, 8a4003d71, 551ecb82b -->
Fixes #41 <!-- 51282caa5, 551ecb82b -->
Fixes #55 <!-- 5f7633ba5, 2637e929d, 85dbb6bdb -->
Fixes #14 <!-- 448e213c6 -->
Fixes #62 <!-- 41b363383 -->
Closes #39 <!-- 448e213c6 -->
Closes #50 <!-- 41b363383 -->
Closes #54 <!-- 406c9042b -->
Closes #56 <!-- 5f7633ba5 -->
Closes #57 <!-- 1601e35b4 -->

## Partly addressed
* #9, Xbox 360 wireless receiver: decoding and empty-slot hiding are tested with the captured packets. Input through the app on a receiver is not checked. <!-- 406c9042b -->
* #18, Xbox One controller (`045E:02D1`): OJD seizes its HID device only after the serving decision. Not confirmed on a controller. <!-- b7b343664 -->
* #35, Flydigi Vader 4 Pro: Bluetooth XInput mode and dongle rumble are done. The dongle in DInput mode still reaches only the generic fallback. <!-- bcb3739a2 -->
* #37, Flydigi Vader 4 Pro dongle in XInput mode: the fix is decided and not built. <!-- 32bd041c8 -->
* #58, Thrustmaster Ferrari 458 Spider: steering and brake are read. The clutch, the other buttons and the turn to the right need captures. <!-- ed18df398 -->
* #59, 8BitDo Ultimate C Wired for Xbox (`2DC8:2027`): the startup sequence is compared with the Linux capture, and a pad that sends nothing says so. The pad has no record, and the Ultimate Mini is not covered. <!-- 469109ddc, c02722262, 589dc6b4a -->
* #63, GameSir G7 Pro dongle: the HID gamepad interface is read. Its controls have no names until a capture through the dongle. <!-- f5cbcab80 -->

## Contributors
* @xsyetopz
* @bdidier: Xbox 360 wireless receiver work (#54, #64)
* @konnsim: Xbox Elite Series 1 endpoints (#56, #55)
* @multision: Razer Wolverine V3 Tournament Edition endpoints (#39)
* @phil-bbs: Turtle Beach Rematch Advanced record (#57)
* @Anonim0Venezian0: PowerA Spectra record (#50)
* @fmilioni, @manupernas, @feelyourwarmth, @ductrsan-sys: 8BitDo Ultimate 2C reports, patches and captures (#34, #41)
* @nightmare2122: Linux capture of the 8BitDo Ultimate C Wired (#59)
* @lzpfmh, @jonasw8, @Presum0: Xbox 360 wireless receiver captures and reports (#9)
* @nabekhan: Xbox 360 receiver bridge used as a reference (#9)
* @scraton: Flydigi Vader 4 Pro captures (#35, #37, #36)
* @deniskabana: Ferrari 458 Spider packets (#58)
* @dnfanjos: GameSir G7 Pro dongle report (#63)
* @cooltune: Xbox One controller report (#18)
* @cbandras: Razer Wolverine V3 Tournament Edition request (#14)
* @ElAscendido: PowerA Spectra report (#62)

## New Contributors
* @bdidier made their first contribution in https://github.com/xsyetopz/OpenJoystickDriver/pull/54
* @konnsim made their first contribution in https://github.com/xsyetopz/OpenJoystickDriver/pull/56
* @multision made their first contribution in https://github.com/xsyetopz/OpenJoystickDriver/pull/39
* @phil-bbs made their first contribution in https://github.com/xsyetopz/OpenJoystickDriver/pull/57
* @Anonim0Venezian0 made their first contribution in https://github.com/xsyetopz/OpenJoystickDriver/pull/50

**Full Changelog**: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.6.0-alpha.2...0.6.0-alpha.3
