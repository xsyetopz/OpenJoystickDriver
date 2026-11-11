# Design: 0.6.0-alpha.3

## Context

Each fact carries its source: **observed** (a command or file read on 2026-11-10 on the maintainer's Mac, macOS 27.2, OJD `0.6.0-alpha.2+build.1.21.99`), **reported** (an issue or pull request), **cited** (a published document), or **inferred** (a hypothesis a task must confirm).

### 8BitDo

- Observed: the connected Ultimate 2C Wireless enumerates by cable as `2DC8:310A`, `bcdDevice` 0x0114, with interface 0 class `FF/5D/01` and two HID interfaces. `ioreg` shows `UsbExclusiveOwner = OpenJoystickDriver` on interface 0. `ojd controller show 2DC8:310A` prints protocol `xbox-xusb:wired`, session `active`, input `healthy`, rumble `low-frequency, high-frequency`, lighting `player-indicator`, publication `published`.
- Observed: at the same time the receiver enumerates as `2DC8:301C`, product string `IDLE`, one HID interface.
- Observed: `Sources/OpenJoystickDriverKit/Resources/Controllers/2dc8/2dc8-301c.json` holds `"idle": true` and no input section. `controller.schema.json:56` defines an idle identity as one OJD "serves nothing" for.
- Observed: `docs/testing/8bitdo-ultimate-2c.md` lists `2DC8:310A` as "2.4 GHz dongle, XInput", verified by two testers on tester build 1.5.71, and assumes the receiver re-enumerates from `301C` to `310A` once the pad links.
- Reported (#34, fmilioni): with the pad linked, the receiver keeps `2DC8:301C`, its product string becomes `8BitDo Ultimate 2C Wireless Controller`, and it sends HID report 1: 15 buttons, hat, X/Y/Z/Rz, Accelerator, Brake. Its descriptor declares output report 1 (LED page usages 0x43 to 0x46) and a 63-byte vendor report 0x81.
- Observed (2026-11-10, 22:42, cable unplugged, pad linked to the receiver): the receiver leaves the bus as `2DC8:301C` (`bcdDevice` 0x0200, product string `IDLE`) and returns as `2DC8:310A` (`bcdDevice` 0x0114, product string `8BitDo Ultimate 2C Wireless Controller`) with the same serial number and port. Interface 0 is `FF/5D/01`, owned by OJD. `ojd controller show 2DC8:310A` prints protocol `xbox-xusb:wired`, session `active`, input `healthy`, publication `published`, and a 12 s capture holds 306 input reports of 20 bytes. So OJD 0.6.0-alpha.2 serves the pad through the receiver in this pad mode, and the `IDLE` identity is correct while no pad is linked.
- Observed in the same capture: bytes 14 to 19 of each report are `10 1C 30 64 00 10`, where a standard XUSB report holds zeros. They stay constant through every press. Inferred: byte 17 (0x64, 100) is the battery level. Task 2.1 compares it with a cable capture and a second charge level.
- Observed (`evidence/2c-receiver-310a/ordered-controls-100s.txt`, presses in a fixed order): through the receiver as `310A`, A, B, X, Y, LB, RB, Minus, Plus, Guide, both stick clicks, and the four D-pad directions each set the standard XUSB bit; both triggers reach 255; each stick axis reaches -32768 and 32767. The receiver sends a report only when a control changes.
- Observed (`evidence/2c-receiver-310a/rear-square-star-45s.txt`, presses told apart by count): L4 sets the Minus bit and R4 sets the Plus bit, so neither has its own bit in this mode. Square and Star send no report. Not known: whether Minus and Plus are the factory assignment of L4 and R4 or one stored on this pad; `docs/testing/8bitdo-ultimate-2c.md:37` names another default.
- Observed (`evidence/2c-receiver-310a/rumble-6s.txt` and the maintainer's report): `ojd controller rumble 2DC8:310A --left 200` and `--right 200` each exit with status 0, and the maintainer felt the left side and then the right side. The capture holds the right-motor write `00 08 00 00 C8 00 00 00` and the stop write; it attached after the left-motor write.
- Observed (23:00, pad turned on with B + Guide, switch on `2.4G`): the receiver follows the pad's mode. It enumerates as `2DC8:301C` with `bcdDevice` 0x0001 and the product string `8BitDo Ultimate 2C Wireless Controller`, with one HID interface (usage Game Pad, descriptor as #34 gives it). `ojd controller list --json` returns no item and `ojd controller show 2DC8:301C` prints `E2012`, so #34 reproduces on the maintainer's pad. The same receiver with no pad is `bcdDevice` 0x0200 and `IDLE`. While the pad linked, the receiver changed identity five times in 20 s: `IDLE`, `310A`, off the bus, `301C` linked, `IDLE`, `301C` linked.
- Observed (`evidence/2c-receiver-301c/ordered-controls-150s.txt`, read with `hidcap.swift` in that folder because OJD lists no controller): 461 reports of 10 bytes, report 1, none while nothing is touched. Bits of bytes 1 and 2: A 0, B 1, X 3, Y 4, LB 6, RB 7, LT 8, RT 9, Minus 10, Plus 11, Guide 12, left stick click 13, right stick click 14. The hat in byte 3 reads 0, 4, 6, 2 for up, down, left, right and 15 at rest. Bytes 4 and 5 are the left stick (X, Y), bytes 6 and 7 the right stick (Z, Rz), byte 8 the right trigger (Accelerator), byte 9 the left trigger (Brake); each reaches 0 and 255. L4 sets bit 10 and R4 sets bit 11, bits 2 and 5 are never set, and Square and Star send no report.
- Cited (8BitDo, `Ultimate-2C-Wireless-Controller-EN.pdf`, "L4 / R4 Configuration"): "Hold the L4 / R4 button + the button you would like to configure, then press the Mapping button to complete the configuration. Repeat the same procedure to cancel the configuration." The Mapping button is Square and the Star button sets turbo, which explains why neither sends a report. The manual's English section names no button combination for XInput or DInput.
- Observed (`evidence/2c-receiver-301c/rear-r4-cleared-45s.txt`): the Minus and Plus assignments were stored on the pad. After the maintainer cancelled R4's assignment, R4 sets bit 5 of the report and no other bit. L4's assignment stayed after two attempts to cancel it, and L4 still sets bit 10 (`rear-l4-assigned-60s.txt`). Not captured: an unassigned L4 as `301C`; over Bluetooth LE the same L4 sets bit 2. The SDL entries for `301B` and `301D` put the rear buttons on bits 5 and 2; its `301C` entry swaps the two names.
- Observed (`evidence/2c-receiver-301c/rumble-writes.txt`): in this mode four output writes return success and the maintainer felt no rumble: report 1 with each byte at 200, at 100, and at 255, and report 5 as the Bluetooth LE record uses it. Not tried: vendor report 0x81.
- Observed: the linked `301C` identity comes from neither Bluetooth nor an OJD virtual device. #34 gives `301B` to the pad's `BT` switch position and `301C` to its `2.4G` position. The three files in `Resources/VirtualDevices/` publish `045E:0B0C`, `1209:4A4F`, and `045E:0B13`, and no file under `Resources/` or `Sources/` other than the receiver record names `301C`.
- Cited: the SDL community database (`mdqinc/SDL_GameControllerDB`, `gamecontrollerdb.txt` line 84) maps `2DC8:301C` as "8BitDo Ultimate 2C" on Windows with `paddle1:b2` and `paddle2:b5`, beside separate entries for `301B`, `301D`, and `310A`. A maintainer's comment on `sub0x00001/padbridge` issue 2 says X + Home selects XInput, B + Home selects DInput, and "L4/R4 send nothing in XInput mode". 8BitDo's FAQ for the Ultimate C 2.4G names the same two combinations, pressed while the pad is off, and says the pad keeps the mode. A comment on gist `ammuench/0dcf14faf4e3b000020992612a2711e2` reports that after a receiver firmware update the receiver came up only as `310A` and the combinations stopped working.
- Reported (#34, #41): over Bluetooth LE the pad is `2DC8:301B`, report 1 with hat, X/Y/Z/Rz, Accelerator (right trigger), Brake (left trigger), 16 buttons in Android order (usages 3 and 6 are the rear buttons), a battery byte that reads 0, and output report 5 on the Physical Interface Device page (4 bytes, 0 to 100). #41 reports the right stick dead on tester build 1.5.71. The reporters disagree on the rear buttons: #34 saw their own bits, #41 saw the right rear button repeat the right shoulder bit.
- Observed (23:10, switch on `BT`, `evidence/2c-bluetooth-301b/ordered-controls-120s.txt`): the pad is `2DC8:301B`, product string `8BitDo Ultimate 2C Wireless`, and sends report 1 in 11 bytes: hat in byte 1, left stick in bytes 2 and 3, right stick (Z, Rz) in bytes 4 and 5, right trigger (Accelerator) in byte 6, left trigger (Brake) in byte 7, 16 buttons in bytes 8 and 9, battery in byte 10. The button bits equal those of `301C`. L4 sets bit 2 and R4 sets bit 5, each alone, so the Minus assignment that L4 keeps as `301C` does not apply over Bluetooth LE. The battery byte reads 0 in all 222 reports, in the hour in which byte 17 as `310A` reads 100.
- Observed (`evidence/2c-bluetooth-301b/ojd-watch-120s.txt`): `ojd controller watch 2DC8:301B` on alpha.2 names every face, shoulder, trigger, menu, stick-click, and D-pad control as the pad labels it, moves both sticks to ±32767, and reads both triggers as 0 at rest. The dead right stick of #41 does not reproduce. It prints nothing for L4 or R4, because the bundled record maps neither usage 3 nor usage 6.
- Observed (`evidence/2c-bluetooth-301b/serving.txt`): the bundled `301B` record names no server, so OJD leaves the pad to macOS: `ojd controller show` prints `Served by System (from default)`, `native-pass-through`, and `not-published (system-gamepad)`, and OJD publishes no gamepad. macOS marks the pad `GameControllerSupport = Yes` with category `mfi`. After `ojd controller claim 2DC8:301B`, OJD holds the pad alone and publishes `045E:0B0C`; `virtual-0b0c-claimed-120s.txt` shows every control above on the right bit or axis of that gamepad, triggers 0 at rest and 1023 pressed, and no report for L4 or R4. `ojd controller release` returns the pad to macOS.
- Observed (`evidence/2c-bluetooth-301b/gamecontroller-probes.txt`): while OJD leaves the pad to macOS, the GameController framework lists no controller for it. Every run agrees: the maintainer's own shell, the repository's probe (`just diagnose-gamecontroller`: `gamecontroller=yes`, `Initial controllers: 0`, `connect=false`), after the pad was turned off and on, with the OJD service stopped, and for 60 s while the maintainer pressed buttons and moved both sticks. The probe is sound: in the same run it lists OJD's virtual gamepad `045E:0B13` with its full button list and none for the 2C. The log of `gamecontrollerd` holds "Notify HID Service Matched" and "Claim HID Service" for the virtual gamepad and neither line across the 2C's reconnect. So with the bundled record a GameController game receives no controller over Bluetooth LE, and OJD publishes none.
- Observed in source: OJD decides that macOS serves a HID pad from `GCController.supportsHIDDevice` alone (`HIDDeviceStream+DeviceLifecycle.swift:98-104`). Such a pad is not seized (`:66`), is reported as `system-gamepad` (`DeviceManager+DiscoveryModels.swift:90-94`), and gets the route `native-pass-through` when its record names no server (`DeviceCatalog.swift:96`, `ServingPolicy.swift:145-149`). The same answer sets `systemListsGameController` (`HIDDeviceStream+DeviceLifecycle.swift:80`), so after a claim `ojd controller list` warns of a second system controller that does not exist for this pad. `GCController.supportsHIDDevice` answers yes for the 2C in every run.
- Observed (same file, runs 8 to 10): of OJD's three virtual gamepads, GameController lists only `GameControllerCompatible` (`045E:0B13`); it lists none for `SDLCompatible` (`045E:0B0C`) and `Generic` (`1209:4A4F`). Automatic selection picks `SDLCompatible` and never `GameControllerCompatible` (`VirtualHIDProfileSelector.swift:37`, `wiki/Playing-Games.md:24,34`), and after the claim the 2C got `sdl-compatible (automatic)`. So a pad OJD serves reaches SDL games, Steam, and emulators, and reaches a GameController game only after `ojd virtual set game-controller-compatible`. That holds for every controller OJD serves and is the documented design of the branch.
- Observed (same file, run 11): with the 2C claimed and its profile set to `game-controller-compatible`, GameController lists one controller, and every control the maintainer pressed arrives under the right name: the four face buttons, both bumpers, both triggers to 1.0, View, Menu, both stick clicks, the four D-pad directions, and both sticks. Guide gave no line: the probes have no window, and GameController sends Home only to the frontmost app (`XboxSeriesBluetoothReport.swift:7-8`). Not tested: Guide in a frontmost GameController app.
- Not known: why `gamecontrollerd` does not take the pad's HID service, and which other HID pads share the behavior. Not tested: another Mac, another macOS version, and a game that reads raw HID (SDL's HIDAPI driver) while OJD leaves the pad to macOS.
- Observed (`evidence/2c-bluetooth-301b/rumble-writes.txt`): eight writes of output report 5 through `IOHIDDeviceSetReport` return `kIOReturnNotFound`, with and without the report ID in the payload, while macOS serves the pad. While OJD serves it, `ojd controller rumble 2DC8:301B` exits with `E2013`, because the record declares no rumble. Reported by the maintainer: the pad rumbles once when it connects. Cited (`libsdl-org/SDL`, `SDL_hidapi_8bitdo.c`): SDL sends `05`, low motor, high motor, left trigger, right trigger as that report. Not known: a write that reaches the motors over Bluetooth LE on macOS.
- Reported (#34, feelyourwarmth, 2026-11-09): on alpha.2 the 2C works by cable and not otherwise.
- Observed: `HIDDescriptorDriver` declares `outputCapabilities: .none`, so no `HIDDescriptor` record has rumble.
- Observed: no record exists for `2DC8:2027` or `2DC8:2019`. Screenshots in #59 show both listed as "Xbox One (GIP)". The `2DC8:2027` screenshot shows "Input: Healthy" beside "Not published (Waiting for the first input...)".
- Reported (#59): on `2DC8:2027` the light goes off at `SET_CONFIGURATION`, endpoint 0x81 stays silent, and macOS ends the device 10 to 25 s later; libusb shows the same. Linux sends `SET_CONFIGURATION 1`, `SET_INTERFACE` (interface 1, alternate 0), then `05 20 00 01 00`, `0a 20 01 03 00 01 14`, `06 20 02 02 01 00`. The pad sends no announce packet; its first packet is `03 20 01 04 80 00 00 00`, 8 ms after power-on. The issue attaches a Linux `usbmon` capture.
- The comment the request links (#59, issuecomment-6728417166) concerns `2DC8:2027`, a different product from the 2C. The 2C cannot reproduce it.

### What the Xbox USB driver is for

- Observed: macOS ships its own driver, `/System/Library/DriverExtensions/XboxGamepad.dext` (`com.apple.gamecontroller.driver.XboxGamepad`). On macOS 27.2 it matches `045E:028E`, `045E:02EA`, `045E:0B00`, and `045E:0B12`. It takes the USB interface of those pads and publishes each as a HID gamepad for the GameController framework.
- Cited (`docs/development/apple-controller-ownership.md:23,32`): a USB interface has one exclusive owner. While Apple's driver holds one of those pads, an app cannot open the interface.
- OJD's "Xbox USB Driver" is OJD's own driver extension, `com.openjoystickdriver.XboxUSBDevice`. It exists to take the interface in place of Apple's driver, so that OJD speaks GIP to the pad. It has no relation to the property lists of Apple's controller catalog, which map HID devices and never touch USB.
- Observed: OJD's extension matches `045E:02D1`, `02DD`, `02E3`, `02EA`, `0B00`, `0B0A`, `0B12` (`Sources/OpenJoystickDriverUSB/Configuration.swift:13-17`). The list is the scope of the entitlement Apple issued (`apple-controller-ownership.md:14-23`), not the list of pads that need a driver. Apple's driver holds three of the seven (`02EA`, `0B00`, `0B12`). Nothing holds the other four.
- Observed: the routes never fall back (`USBDriverKitTransport.swift:97`, `IOUSBHostTransport.swift:35`). `apple-controller-ownership.md:12` reserves all seven for the extension "even when unavailable". So a pad nothing holds still waits for the extension.
- Observed: the direct route (IOUSBHost, in OJD's service) serves vendor-class interfaces that have no driver (the 2C above).
- Reported (#18, felapas): a patch that serves `045E:02D1` on the direct route when no extension owns it works on hardware; the extension interfered with Steam; the reporter asks for no automatic activation request.
- Reported (#55): on the Xbox Elite Series 1 (`045E:02E3`) the extension fails every handshake with `kIOReturnBadArgument` and restarts in a loop.
- Observed: InputConfig has no driver because it never opens a USB device. It reads what macOS publishes (GameController and IOHIDManager), so an Xbox pad reaches it through Apple's `XboxGamepad.dext`, and it writes keyboard and mouse events. Its `HIDDeviceRegistry.swift:741-764` lists XUSB and GIP vendor interfaces as unreadable, and its README limits wired Xbox One and Series pads to macOS 15 or later. It publishes no virtual gamepad.
- Observed: the repair button calls `OSSystemExtensionRequest.activationRequest` with a 30 s limit. `.failed`, `.cancelled`, `.timedOut`, and `.inactive` all map to `.failed`, whose banner text equals the text before the click. `SystemExtensionSetup.swift:102` returns without a request for `.invalid`, and `:104` drops a click while a request runs. The banner depends only on the extension state (`MainWindowProblems.swift:92-118`).

### Documents

- Observed: `OpenJoystickDriverAPI.version` is `openjoystickdriver/v1alpha2`. The one migration step is `AlphaOneToAlphaTwo` for six kinds. `DocumentMigrator` scans the root, `Profiles/`, `Controllers/`, and `VirtualDevices/`. It skips without a message any file with no `apiVersion` or `kind`. It does not scan `Packages/`, `Personas/`, or `ActiveProfiles.json`.
- Observed (#59 screenshot): the Access area shows `E2006` wrapping `E5001` for a `v1alpha1` `AccessGrants.json`, with "Details" and "Try Again" only. `AccessAreaView.swift:66` adds Migrate when `failure.code == .unsupportedAPIVersion`. Observed in source: the code that arrives is `E2006`, so the button never appears. `AccessGrantStore.swift:222` throws `unsupported` with the code `E5001`; `LocalRPCBridge.swift:38` sends only its text, because the error is no `ApplicationServiceRemappingRPCError`; the client throws `LocalServiceRPCError.remote` (`LocalServiceRPCTransport+CallState.swift:107`); and the `default` branch of `AccessFailure.init` gives every such error `.serviceRequestFailed` (`AccessService.swift:38-45`).
- Observed (#59 screenshot): the Profiles area shows "Profile corrupted (E5001)" with "Delete" only.
- Reported: #58 keeps a `v1alpha1` user record; pull requests #57 and #54 carry `v1alpha1` JSON; #50, #36, and #39 use the 0.5 format (`$schema`, `operation`, `driver`, `variant`).
- Observed: `wiki/Controller-Records.md:545` says migration "does not convert files".

### The property-list and JavaScriptCore proposal

`controller-schema-migration-proposal.md` asks for checks on real data. The experiments ran in a temporary folder that no longer exists (`plistrt.swift`, `pld.swift`, `bench.swift`, `jsc.swift`, `gen.swift`, `validate_plist.py`); the tests of tasks 1.3, 6.1, and 6.2 repeat the ones the release depends on. Every row is observed.

| Check | Result |
| --- | --- |
| Round trip JSON → XML property list → objects, with type comparison | 818 of 819 files identical, counted per folder: 37 source records, 706 generated records, 34 patches, 19 protocol descriptions, 15 schemas, 3 catalog rule files, 4 user files |
| `Resources/Vocabulary/crosswalk.json` | Cannot be a property list: 137 `null` values |
| A patch that holds `null` | Cannot be a property list. `null` is how a patch deletes a key (RFC 7396). 0 of the 34 bundled patches hold one |
| Mixed-type arrays, top-level non-objects | None in any file |
| Integers above 2^53, unsigned 64-bit, reals, booleans | Kept exactly |
| `PropertyListDecoder` with a `Decodable` type | Refuses an integer for a `Bool`, a boolean for an `Int`, a fractional real for an `Int`, and `date` or `data` for a `String`. Accepts an integer for a `Double` |
| Duplicate key in one dictionary | The last value wins, as with `JSONSerialization` |
| Key order on write | Sorted, so a rewritten file has a stable difference |
| Size against JSON | XML 1.6 to 2.9 times larger (generated records 215,889 B → 515,931 B); binary 0.4 to 1.0 times |
| Parse time, 706 records, best of 20 | JSON 2.48 ms, XML property list 3.69 ms, binary property list 2.15 ms |
| Python `plistlib` round trip | 762 files, 0 differ; `None` is refused |
| JSON Schema verdict (`jsonschema` 4.26.0, Draft 2020-12) on each bundled document read as JSON and read back from an XML property list | 819 of 820 files get the same verdict: 743 records, 34 patches, 38 protocol descriptions, 3 virtual devices, and the error catalog are valid in both forms. The crosswalk is valid as JSON and cannot be converted (`null`) |
| JavaScriptCore result read with `toDictionary()` | Integers arrive as reals; a `Date` arrives as a non-JSON object |
| JavaScriptCore result read with `JSON.stringify` | Integers stay integers, reals stay reals, `undefined` is dropped, a `Date` becomes a string, and the result is a valid property list unless it holds `null` |
| TypeScript syntax, `import` statement | `SyntaxError` for both |
| `for (;;) {}` in a script | Never returns in process. In a helper process, the host ends it 1.07 s after a 1 s limit |
| Time limit in the public JavaScriptCore headers | None in the 15 headers. `JSContextGroupSetExecutionTimeLimit` is exported and undeclared, so it is private |
| Hardened runtime with no JIT entitlement | Same speed as unsigned (3.69 s against 3.62 s for 60 million iterations) |
| File and network access from a bare context | `require`, `fetch`, `XMLHttpRequest`, `process`, `setTimeout` are undefined |
| `osascript -l JavaScript` calling `ojd controller list --json` through `doShellScript` | Returns the controller list |
| Plain AppleScript: `osascript -e 'do shell script "… controller list --json"'` | Exit status 0; returns the `ControllerList` JSON with the 2C (`XboxXUSB:Wired`, session `Active`) |

Repository facts that bear on the proposal (observed):

- JSON is read and written at 144 `JSONDecoder`, `JSONEncoder`, and `JSONSerialization` sites in `Sources/`, at 616 in `Tests/`, and in 27 Python files. Schemas are 15 JSON Schema files published under `schemas/v1alpha2/`.
- Records are static data. No document has an expression or script field.
- A user customizes a bundled record with a patch document and adds a controller with a record document. Both use the bundled schemas.
- Foundation does all JSON work. The Swift package dependencies are `swift-argument-parser` and the maintainer's `SwifterKit` (three imports), so no JSON package exists to remove.
- OJD has three scripting surfaces: App Intents for Shortcuts (`Sources/OpenJoystickDriver/platform/macos/Intents/`), the `ojd` command line with `--json`, and the local endpoint (`wiki/Automating-OpenJoystickDriver.md`).

### What a controller needs from source

The maintainer's words in the request for this change: "The whole point is to *not* force users/AI agents to modify source code just to have their controlelr work", "It just works", and "a Plug-and-Play with *some* rare case of *patch an existing entry* or *add a new entry*". This design reads them as one rule: a controller works when it is plugged in; in the rare other case a patch or a record fixes it; nobody edits source for a controller. Measured against the branch (all observed):

- The classifier binds in three steps: an exact record, then a protocol-standard USB interface signature, then the HID descriptor with an SDL_GameControllerDB line or the standard usage map (`ProtocolClassifier.swift:366-369`, `:345`). So a controller with no record already binds when it speaks a family OJD has.
- Interface signatures come from protocol description documents (`ProtocolDescription+Document.swift:11-29`), not from Swift.
- A record can state modes with matches on link, interface signature, manufacturer string, product string, `bcdDevice`, and feature-report probes; endpoints; startup writes; keep-alive; a rumble template; tuning; and, for one family, input layouts (`controller.schema.json`).
- The families `XboxXID`, `NintendoSwitchInputOnly`, and `VendorFlydigi` run on the general layout driver from a protocol description (`ProtocolDriverRegistry.swift:209-218`).
- The service applies a record or package the moment its folder changes (`ControllerRecordWatcher.swift:4-9`). The watcher matches the extension `json` (`:56`).
- `ojd record draft`, `validate`, `test`, `install`, and `remove`, and `ojd mod`, cover the path from a capture to an installed record (`wiki/Command-Reference.md:242-283`).
- Swift holds five lines with a model identifier, found by a search of `Sources/` for a four-digit hexadecimal literal beside a vendor or product name: the driver extension's vendor (`Configuration.swift:13`, with its product list), the Nintendo vendor for Bluetooth LE discovery (`Switch2BluetoothLEHub.swift:28`), a diagnostic for `057E:2009` (`DiagnosticsService.swift:339`), the 8BitDo bootloader identities (`ControllerModelID.swift:34`), and the one model the passive descriptor probe may read, `3537:1010` (`PassiveUSBDescriptorProbe.swift:9`). `JoyConPair.swift:40-55` holds none: it tells the two halves apart by the record's layout.

Where a controller still needs a source change (observed):

1. **Input layouts serve one family.** `input.layouts` is read only for `HIDReportLayout` (`ControllerRecordDocument.swift:36`, `ProtocolDriverRegistry.swift:205-208`). No `XboxGIP` record carries one. A GIP or XUSB device with another report shape, such as the wheel in #58, needs Swift.
2. **`HIDDescriptor` has no output.** `HIDDescriptorDriver` declares `outputCapabilities: .none`, so rumble on such a pad needs Swift.
3. **Idle is a constant of the record.** `idle` is `true` for the whole identity (`controller.schema.json:55-83`), so a receiver that is idle only while no pad is linked needs Swift.
4. **Bootloader identities are in Swift** (`ControllerModelID.swift:34`). The next 8BitDo bootloader identity needs a source change.
5. **The family list is closed.** `protocol.family` is an enumeration in two schemas (`controller.schema.json`, `report.schema.json`) and in Swift (`PhysicalProtocolID`, `ProtocolClassifier.swift:7`). 15 Swift files name a family case, and a pattern search counts 231 lines that switch on a protocol or family value; task 9.9 replaces that count with an exact list. A family the general layout driver could run still needs a source change.

### The Apple way

- Observed: Apple's own controller catalog (`/System/Library/AssetsV2/.../com_apple_MobileAsset_GameController_DB1`) is an index property list (`Devices[]` with `IOPropertyMatch`, `Identifier`, `Personalities`, `CompatibilityVersion`) plus one XML property list per personality. Its 206 files hold no comment and no description, note, or source key.
- Observed: an IOKit personality is a matching dictionary of data only.
- Cited: Apple's device-management schemas (`github.com/apple/device-management`, `mdm/profiles/com.apple.dock.yaml`) describe property-list payloads in a separate schema file. Each key has a `content` text such as "If `true`, locks the size slider." and states limits in `range`, `rangelist`, `presence`, and `default`, outside the text.
- Cited: Swift API Design Guidelines (`swift.org/documentation/api-design-guidelines`): "Use a single sentence fragment if possible, ending with a period." "For all other declarations, describe what the declared entity is." "Omit needless words."

Reading: controller data is a property list that holds data only; a separate schema describes it; a description is one fragment that says what the value is; a limit the schema can state is stated as a keyword; everything else lives in reference documentation.

### The app's interface

Read on 2026-11-11. Paths in this section are under `Sources/OpenJoystickDriverPresentation/` unless they name another folder. Every finding is observed in source; none was reproduced in the running app, and task 10.5 does that before any fix.

Reported by the maintainer: "what is the point of menbar app and its options are very confusing to navigate, or know for their purpose"; "reports of sme users saying the dropdowns do nothing, and other options also do nothing. The scale is also questionable"; a "Simple, Advanced surface style, such as how OBS does it as a dropdwon option"; and "Making it easier for illiterate users, and everyday users alike, gamers and non-gamers, businesses and developers". Observed: a search of the repository's issues finds none that describes a dropdown that does nothing, so that report rests on the maintainer's word and on the source below.

Reported by the maintainer: the "header-style buttons" of the main window are intended, "as many apple apps, like Apple Notes and such, use the very same idea".

**Menu bar item**

- The menu is built by `StatusItemModel.entries(for:)` (`MenuBar/StatusItemModel.swift:161-236`). In order: an unavailable status line of the form `"%1$@ · %2$@ · %3$@"` (readiness, controller count, profile name); a "Controllers" submenu with one submenu per controller; a "Profiles" submenu with the submenus "Activate" and "Deactivate"; "Grant Access" while a permission is missing; "Open Window"; "Settings..."; a "Help" submenu ("Activity Log", "Explain Error Code...", "Report Problem...", "Project Website"); "Quit OpenJoystickDriver".
- A controller's submenu (`:265-325`) holds "Suspend" or "Resume", "Test Input", an "Active Profile" submenu, "Disconnect Wireless Link", and "Show in Window". "Controllers > controller > Active Profile" is three levels deep. The controller's row shows its name only: no battery, no profile, no state.
- The icon is the symbol `gamecontroller`, set once (`MenuBar/MenuBarCoordinator.swift:10-21`). It never changes. State shows only as a glyph beside the status line, and one glyph covers both a problem and "no controller connected".
- No string says that the service is stopped: an unreachable service reads "Needs attention" with 0 controllers. "Grant Access" does not name the permission.
- `docs/development/menu-bar-settings-architecture.md:78` says "Do not put refresh, profile editing, logs, reports, packet streams, raw identifiers, catalog audits, support tests, contributor diagnostics, or metrics dashboards in the menu." The menu holds "Activity Log" and "Report Problem...".
- Every action of the menu also exists in the main window or the main menu, except the status line and "Open Window". The main menu shows only while a window of the app is active, because the app starts as an accessory (`MenuBar/MenuBarCoordinator+Lifecycle.swift:16`).
- "Show in menu bar" and "Show in Dock" lock each other so one stays on (`SettingsPreferencesModel.swift:318-326`). Not traced: what the app does when a hand-edited settings file turns both off, beyond `applicationShouldHandleReopen` (`MenuBarCoordinator+Lifecycle.swift:128-135`).

**Controls that can appear to do nothing**

- Player indicator in Input Test (`Controllers/InputTest/InputTestView+Body.swift:218-226`): the segmented control changes nothing until the user clicks a separate Apply button, and nothing says so. The rumble switch (`:29`) takes effect only on "Test rumble".
- "Served by" (`Controllers/Inventory/ControllerServerPicker.swift:33-52`): both segments stay enabled while the request runs (up to 10 polls of 200 ms), so a second click starts a second request. On failure the segment snaps back and the text appears in another section of the form (`ControllerDetailView+Facts.swift:24-26`). The service refuses a choice the control offers (`OpenJoystickDriverService/Runtime/RPC/ControllerServerRequests.swift:9-91`, `E2023`).
- "Virtual HID profile" (`Controllers/Inventory/VirtualHIDProfileOverrideView.swift:34`): the setter drops the results `.unchanged` and `.otherScopeHolds` without a message (`:108-118`). The pop-up shows the stored value, not the value in force, and offers all three kinds to every controller. Its options show raw identifiers. The "Apply to" pop-up (`:48`) is view state only.
- Dead zone editor (`Controllers/Inventory/StickDeadzoneEditor.swift:32`): `guard !isWriting else { return }` drops a change made during a write.
- Profile editor: the "Virtual output" pop-up edits a draft until Save and resets `physicalInput` to `.shared` without a message (`Profiles/Editor/ProfileOutputPolicyView.swift:16-50`). Editor and list actions start with guards that return without a message (`ProfileEditorActions.swift:12-49, 254-262, 268-289`; `ProfileListActions.swift:23, 67-68, 72, 81-82, 89, 102, 133-135, 148-149`).
- Settings: "Start at login" can be unavailable with no reason shown; the lock reason of "Show in menu bar" and "Show in Dock" is only a tooltip (`SettingsWindow/SettingsPaneComponents.swift:28`); a notification switch returns to off with no message when macOS has denied the permission (`SettingsPreferencesModel.swift:207-227, 402-413`); "Automatic update check" is read only at launch (`MenuBar/MenuBarCoordinator+Lifecycle.swift:79`); the switch titled "Controller connected" also governs the notification for a controller that needs attention (`RuntimeNotificationMonitor+Delivery.swift:76`; `settings.schema.json:34` says so, the title does not); the developer controller pop-up stays enabled with no option (`Settings/Developer/DeveloperControllerSummaryView.swift:17-27`).
- Failures have seven places: the shared banner (`MainWindow/MainWindowProblems.swift`), `controllerActionFailures`, the override view's `problems`, `SettingsErrorSection`, `ProfileLibraryModel.lastError`, Input Test's `outputError`, `ActivityActionFailure`, and several alerts.
- Not read: the profile sheets, the Access view model, the Library area, `MainWindowToolbar`'s actions, and the update checker. Not verified: whether the Apply buttons of Input Test are ever unavailable.

**Sizes**

- Main window: content 1040 × 700 by default, 960 × 560 at minimum (`MainWindow/MainWindowController.swift:17,19`). The column minimums are 170, 200, and 420 (`:11-15`), which is 790, so the window stops shrinking 170 pt before its columns need it to.
- Settings window: 600 wide for every pane, height fitted, not resizable (`SettingsWindowPaneModel.swift:35-54`).
- 23 sheets use seven widths (420, 430, 440, 470, 480, 500, 520) and two paddings (20, 28).
- Text: `.caption` has about 55 uses, more than any other style; one view sets a fixed size (`Components/WorkbenchComponents.swift:62`). Spacing: 16 distinct literal values and no shared scale. The counts are a hand tally.
- The smallest hit areas are 28 × 28 pt (`Components/WorkbenchComponents.swift:62-64, :98`), which meets the guideline below.
- The toolbar holds 15 actions that have no menu command (`MainWindow/MainWindowToolbar.swift:7-47`). The app has no Find command, no in-app help, and no first-start guide.

### Reference apps and guidelines

**Apple apps on the maintainer's Mac** (observed, `evidence/interface-reference/apple-apps-accessibility.txt`):

- Notes: a 52 pt toolbar of icon-only buttons with no text label, each 36 to 44 pt wide, and 38 × 38 buttons inside groups. Each toolbar action checked ("New Note", "Share", "Checklist", "Table") is also a menu command, and the View menu holds "Hide Toolbar" and "Customize Toolbar…". This is the form the maintainer chose for OJD's toolbar.
- System Settings: window 740 × 625, toolbar 52 pt, sidebar 232 wide with rows of 232 × 32, search field 212 × 28, push buttons 80 × 24.
- The menu bar extras of macOS (Bluetooth, Wi-Fi, Sound, Control Center) cannot be read this way: System Events returns error -1719 for the ControlCenter process. No screenshot was taken, because a screenshot of Notes holds the maintainer's notes. Task 10.3 covers both with screenshots the maintainer takes.

**Open-source apps** (observed through `gh api` at the named commit of each default branch):

| App | Commit | What its menu bar item and settings show |
| --- | --- | --- |
| `OpenTabletDriver/OpenTabletDriver` | `493474c2` | Tray menu (`OpenTabletDriver.UX/TrayIcon.cs:73-158`): one item per preset at the top, "Show OpenTabletDriver", on macOS copies of the window's menus because an agent app has no menu bar, then "Quit". Window 960 × 760 with a device switcher above tabs. No app-wide advanced mode |
| `linearmouse/linearmouse` | `93d38f19` | Flat menu (`LinearMouse/UI/StatusItem.swift:255-264`): battery rows at the top, "Settings…", "Start at login", "Configure for" the app in front, "Quit". Menu bar visibility is "Always", "When needed", or "Never" |
| `pqrs-org/Karabiner-Elements` | `ac37d842` | One checkmarked item per profile under a "Profiles" header, "Settings…", "Quit" (`KarabinerConsoleUserServerApp.swift:22-140`) |
| `MonitorControl/MonitorControl` | `7cfe6450` | One block per display with the display's name as header, then "Settings…" and "Quit". Dragging the item out with Command stores "hide" (`AppDelegate.swift:383-387`). A checkbox "Show advanced settings" |
| `rxhanson/Rectangle` | `451ab711` | Actions, "Settings…", "Quit Rectangle". `behavior = .removalAllowed`, and removal by the user stores `hideMenuBarIcon` (`General/RectangleStatusItem.swift:19-24, 40-47`) |
| `obsproject/obs-studio` | `fe1ed795` | `frontend/data/locale/en-US.ini`: `Basic.Settings.Output.Mode="Output Mode"` with `Simple` and `Adv="Advanced"`. Which controls each level shows is inferred from key names; the layout file was not read |
| `apple/sample-food-truck` | `3954a769` | Apple's sample: `NavigationSplitView`, and a `MenuBarExtra` with `.menuBarExtraStyle(.window)` (`App/App.swift:36-48`). `gh search code "MenuBarExtra" --owner apple` returns only this repository |

Common to the five utilities: the item per device or profile sits at the top level, the list of profiles carries a checkmark, the menu ends with Settings and Quit, and none holds a Help submenu. Two of them let the user drag the item out of the menu bar.

**Human Interface Guidelines** (cited). The apple-docs MCP server did not connect in the sessions that wrote this change (`CONNECTION_CLOSED`), so each page was read from `developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`. Task 10.4 reads them again through the server.

- `the-menu-bar`: "Display a menu — not a popover — when people click your menu bar extra." "Let people — not your app — decide whether to put your menu bar extra in the menu bar." "Avoid relying on the presence of menu bar extras."
- `menus`: "Use submenus sparingly." "Limit the depth and length of submenus." "Show people when a menu item is unavailable." "Consider using a checkmark to show that an attribute is currently in effect." "Append an ellipsis to a menu item's label when the action requires more information before it can complete."
- `toolbars`: "Make every toolbar item available as a command in the menu bar."
- `pop-up-buttons`: "Use a pop-up button to present a flat list of mutually exclusive options or states." "Provide a useful default selection."
- `disclosure-controls`: "Use a disclosure control to hide details until they're relevant."
- `layout`: "Use progressive disclosure to make layouts cleaner and easier to interact with." "Use consistent spacing." "In general, support resizing."
- `typography`: "Use font sizes that most people can read easily." "Consider using the built-in text styles." The macOS default size is 13 pt and the minimum 10 pt.
- `accessibility`: a control on macOS is 28 × 28 pt by default and 20 × 20 pt at minimum. "Convey information with more than color alone."
- `inclusion`: "Avoid using specialized or technical terms without defining them." "Replace colloquial expressions with plain language." "Present a clear, straightforward interface." "Build in ways to learn how to use your app or game."
- `game-controls`: "Prefer using symbols, not text, to refer to game controller elements."
- `buttons`: "Ensure that each button clearly communicates its purpose."

### What users ask for

- **#63 (reported), traced in source (observed).** The bundled `Resources/Controllers/3537/3537-1022.json` holds one `XboxGIP` mode and `"capabilities": { "rumble": "Absent" }`. The GameSir G7 Pro dongle exposes two HID interfaces (class 3, usage page 1, usage 5), so the interface contract fails (`ProtocolDriverRegistry.swift:156`), OJD does not fall back to HID (`wiki/Supported-Controllers.md:134`), and the reason `interfaceContractMismatch` has no text for the user (`ProtocolClassifier.swift:275-286`). No document the user can write fixes it: `capabilities` is no section of a patch (`ControllerPatch.swift:62-65, 117-118`); a patch's `modes` replaces the whole array (`ControllerRecordDraft.swift:82`); an added HID mode fails the rule that capabilities "must be deltas the driver of every mode declares" (`ControllerRecordDocument+Modes.swift:392-393`); a user record for a bundled identity is refused (`ControllerRecordSet+Patches.swift:190`); and `ojd record draft` cannot select a device OJD does not serve (`E2012`). `E5007` carries nine or more English messages with no translation. So this controller needs a source change today, against the rule of this design.
- **Per-app profiles (observed).** The service already picks a profile by the app in front (`RemappingProfileLibrary+Operations.swift:275`), and `ojd profile create` and `import` take `--app` (`ojd profile --help`). The window offers a text field for the identifier (`ProfileCreationSheet.swift:74`), and `wiki/Remapping-Profiles.md:133` says "The app has no running-app picker." A profile names one app (`profile.schema.json:38-48`, `appID`). The menu bar item shows only the general profile (`MenuBarViewModel.swift:55`).
- **Names (observed).** The repository has no glossary. "Profile" names a remapping profile and a kind of virtual gamepad. The second also appears as "persona", "Virtual HID profile", "virtual device", and "virtual controller". Who serves a controller reads "Served by", `System`, `OJD`, "Left to macOS", "macOS (native)", and "OpenJoystickDriver (virtual)" (`wiki/Playing-Games.md:38,89`). The driver extension has six names. The window shows `SDLCompatible`, `native-pass-through`, and `not-published (system-gamepad)`. The word "backend" appears in no English string of the app; it is in the flag `--sdl-gamecontroller-backend` and in `wiki/Command-Reference.md:48`. Inferred: by "backends/modes" the maintainer means the kinds of virtual gamepad and the choice of who serves a controller.
- **InputConfig (observed, clone at commit `958bdd97`, MIT, "Copyright (c) 2026 Ryleigh Newman").** It offers what OJD lacks: a live drawing of the controller, several apps per preset with an app chooser, 46 presets and a library of 456 more, conversion of a preset between controllers (`PresetStore.swift:3759`), a global shortcut, idle disconnect for wireless pads, help guides, a tour, and a list of changes after an update. OJD already has press-to-assign (`ui.capture.pressControl`). InputConfig publishes no virtual gamepad and cannot read XUSB or GIP.
- **Profiles and controller models (observed).** A profile's bindings use controller-independent `source` identifiers, and the profile still names one model in `device` (`profile.schema.json:7-15,76`). OJD has two templates, `empty` and `gyroStick` (`ProfileCreationFields.swift:185`), and no conversion between models.
- **Issue survey (an agent's tallies of distinct users, not recounted).** The five most frequent asks: a signed tester build on GitHub Releases (about 16), fixes to the generic HID parser (about 9), correct endpoints and `SET_CONFIGURATION` (about 8), games and Steam seeing the virtual gamepad (about 7), and stable reconnect and mapping (about 6).
- **Checked claims (observed).** #22 reports a 15% default dead zone: the default is 0 (`VirtualGamepadReportMapping.swift:16-21`), so the claim does not hold. #18 reports that OJD takes devices it does not serve: the HID path seizes before any record lookup (`HIDDeviceStream+DeviceLifecycle.swift:66-67`, `HIDInputClaim.swift:96`), which supports it for HID. #19 reports "Input active" with no input: Input Test sets it on any snapshot, with no check for a control that left rest (`InputTestViewModel+SessionAndOutputState.swift:341-343`), which supports it. `wiki/Troubleshooting.md:45` says 697 records; the generated set holds 706. Not traced: the stick Y direction per family (#33).
- **Tester builds (observed).** `gh release view 0.6.0-alpha.2` shows a pre-release with one notarized disk image. `wiki/Updating-and-Uninstalling.md:36-38` says "A tester build is a private, notarized DMG that the maintainer sends to testers." and "An update check does not find tester builds." Settings already holds "Include prerelease updates" (`ui.settings.general.prereleaseUpdates`).
- **License (observed).** OJD is under PolyForm Noncommercial 1.0.0 from 0.6.0-alpha.2 (`README.md:116`).

## Goals / Non-Goals

**Goals**

- A controller that speaks a family OJD has works when it is plugged in, with no record. A controller that differs is fixed by a patch or a record. Source changes only for a protocol family OJD lacks.
- Every controller fix in this release lands as data. Where a record cannot state the fact, the change adds the general record ability, never a branch for one model.
- Every breaking change to the document contract that is known today lands in `v1alpha3`, so later versions add to the contract and do not reshape it.
- The 2C works in its three modes, proved by captures.
- A user with no Microsoft controller never meets the driver extension.
- Stored documents are property lists that Foundation reads, and one schema covers bundled and user-written documents.
- Every stale user document converts or is named with a reason; no screen leaves `E5001` without Migrate.
- A user can generate documents from a JavaScript file.
- Schemas say what each value is and nothing else.
- Every open issue and pull request has a decided next step.
- A user can fix any record with a patch: the patch reaches every section and changes one mode without restating the others.
- Every control of the app acts when used, or shows beside itself why it cannot.
- The menu bar item has one stated purpose, and each row of its menu serves it.
- A person who only wants to play meets no identifier and no protocol term; a person who tunes or contributes reaches every control by one setting.
- A protocol description document registers a family that the general layout driver runs, with no source change (tasks 9.19 to 9.22, from the measurement of 9.9).
- Each gap a mod author meets in `docs/development/scripting-surfaces.md` is opened through a surface or kept closed with its reason and its outside route (tasks 6.11 to 6.17, from the list of 6.10).
- One term names one concept in the app, the command line's prose, and the wiki.
- Each change to the interface rests on a measurement of OJD and a named reference: a guideline page, an Apple app, or an open-source app at a commit.

**Non-Goals**

- Running scripts inside the service or the app.
- A TypeScript compiler inside OJD.
- An AppleScript dictionary. AppleScript and JavaScript for Automation reach OJD through `do shell script` and Shortcuts.
- A press-to-learn mapper for raw USB reports. `ojd record draft` drafts controls only from a HID descriptor; for a device with no HID gamepad interface it drafts the identity and the interface signatures (D17).
- Removing or restyling the toolbar buttons of the main window. The maintainer chose that form (D20).
- A popover or a window under the menu bar item. The item opens a menu (D19).
- A visual redesign before the audit of group 10 exists.
- A virtual gamepad kind chosen per app. Task 9.14 researches it.
- Copying code or preset files from InputConfig (D24).
- Renaming a command, a flag, a schema value, or an error code for the glossary (D22).
- Removing the driver extension. That needs proof that the three Apple-held models work through Apple's HID device.
- Support claims for hardware with no capture. Those tasks stay unticked.
- A compatibility reader for old versions or for JSON. Readers stay single-version.

## Decisions

### D1. Stored documents are XML property lists; messages stay JSON

A stored document is a file that carries `apiVersion` and `kind`: records, patches, protocol descriptions, catalog rules, the crosswalk, the error catalog, virtual devices, profiles, settings, access grants, and package manifests. Each becomes an XML property list with the extension `.plist`.

Reasons: the data fits (818 of 819 files without loss, and the one exception has a fix below); `PropertyListDecoder` is as strict as the JSON decoder; Xcode and `plutil` edit and check the files; Apple's own controller catalog has this shape. Speed is not a reason: every form parses 706 records in under 4 ms.

- **One form.** Files are XML, UTF-8. A binary property list is refused with a named error, so every stored file stays readable and comparable (`single_format`).
- **Schema.** JSON Schema Draft 2020-12 stays the contract, and the schema files stay JSON. A validator reads the property list into objects and checks the objects. `date` and `data` values match no schema type and are refused. Apple's device-management repository uses the same split: a schema file beside the property lists it describes.
- **No `null`.** The crosswalk states "no equivalent" by leaving the key out. A patch deletes keys through `remove` (D12).
- **Messages.** `ojd --json` output, the local endpoint, and report files stay JSON: their readers are scripts, browsers, and `Scripts/SDK/reference_client.py`.
- **Bundled files** are written exactly as `PropertyListSerialization` writes them (sorted keys, no comment), and a test enforces it. A user file may hold XML comments; OJD drops them when it rewrites the file.
- Property names stay lowerCamelCase (`single_format`).

Alternative considered: keep JSON. It needs no migration and has editor support for JSON Schema. Rejected by this design, not by an instruction: the maintainer allowed the move ("if the jsons could become .plist, that's fine, too") and asked for "a more Apple-native solution that satisfies both the users and the app runtime itself"; the data fits, and a property list is the format macOS tools and Foundation treat as native. The cost is the migration in D4 and the larger files in the table above, so the maintainer can still choose JSON by dropping D1 and D12; D2 to D11 and D13 to D15 do not depend on the file format.

Alternative considered: binary property lists in the app bundle (0.8 times the JSON size). Rejected: a second form for 0.3 MB.

### D2. Generator scripts run in a helper process and only write documents

`ojd generate <script.js>` evaluates one JavaScript file with JavaScriptCore and writes the documents its `generate()` function returns.

- The command runs the script in a helper process and ends the helper at a time limit (5 s by default). JavaScriptCore has no public way to stop a script, and a process can be ended.
- The helper reads the result with `JSON.stringify`, which keeps integers exact. A result that holds `null` is refused.
- Each returned document passes the same decoder and rules as a hand-written file before the command writes it.
- The context has no file, network, or timer API, and the command adds none.
- The command does not overwrite a file whose content differs unless the user passes `--replace`.
- The service, the app, and package loading never evaluate a script. A package holds documents only.
- The language is JavaScript as JavaScriptCore runs it: one file, no `import`, no TypeScript syntax. Task 6.7 decides whether OJD ships a type declaration file for editors.

Alternative considered: scripts the service loads at run time. Rejected: no record needs run-time logic, and a script in the service can stall input.

Alternative considered: Apple's Pkl language. Rejected: it needs a separate binary.

### D3. Raise `apiVersion` to `v1alpha3`

D1, D7, and D12 change what a valid document is. `Resources/Schemas/AGENTS.md` raises the version for exactly that case.

### D4. Migration runs at service start, chains steps, and reports every file

Users did not find `ojd migrate`: both screenshots show people stuck. A backup in `Migrated/` makes the conversion reversible, so the service runs it before any reader opens a store. Steps chain (`v1alpha1` → `v1alpha2` → `v1alpha3`), and the last step writes the property list, so one run reaches the current version. Each scanned file ends as `migrated`, `current`, `failed` (with a reason), or `foreign` (not an OJD document); none is skipped without a line. The scan adds `Packages/`, `Personas/`, and `ActiveProfiles.json`. `ojd migrate <folder>` converts a folder outside the user stores, such as a package or a pull request.

A `.json` file left in a store is reported as stale; no reader opens it.

A 0.5 document (no `apiVersion`) gets `failed` with reason "written by 0.5; re-create it", unless task 5.6 finds a mechanical mapping.

Alternative considered: readers that accept old versions or JSON. Rejected by `single_format`.

### D5. The driver extension is requested only by the user, and unowned models use the direct route

Apple's driver holds three of OJD's seven models. For the other four, and for all seven on a Mac with no Apple driver, nothing blocks the direct route, as #18 shows on hardware. So:

- The classifier picks the extension route only when OJD's extension is active and owns the device. With no owner, it picks the direct route.
- OJD sends an activation request only from an explicit user action: `ojd transport-extension activate`, `ojd controller claim` for an Apple-held model, or the button.
- A model Apple's driver holds, with OJD's extension inactive, is listed as served by macOS.

Alternative considered: delete the extension in this release. Rejected: no capture shows OJD serving `02EA`, `0B00`, or `0B12` through Apple's HID device. Task 4.9 runs that experiment with a reporter who owns one.

### D6. The repair flow reports each state

The view shows: in progress (button disabled), waiting for approval (with a button that opens System Settings), done (banner gone), and failed (the `NSError` domain, code, and text, plus Try Again). `cancelled` and `timedOut` get their own text. A state that cannot send a request shows the reason and no button. The banner needs a connected controller whose route is the extension.

### D7. Schema descriptions follow one style; prose-only properties go

- A description is one sentence fragment, at most 120 characters, that says what the value is.
- It names no Swift type, file path, command, or runtime behavior.
- A limit JSON Schema can state is a keyword. A limit it cannot state is in the wiki reference and in a rejection case under `SchemaRejections/`.
- No `$comment`.
- `crosswalk.notes` and `protocol-description.rationale` leave the schemas and the bundled files. `report.notes`, `report.warnings`, and `report.caveat` stay only if a producer writes a runtime finding into them (task 7.5 decides per field).
- `profile.note` stays: it is a MIDI note number.
- A test enforces the style.

### D8. Idle is a state of a mode, stated in the record

`idle` moves from the record to the mode. A mode with `idle` serves nothing while it matches: OJD sends the device no data and publishes no gamepad. Its value names the reason, `NoControllerLinked` or `Bootloader`, and the reason selects the text the user reads. The record-level `idle` flag leaves the schema, and migration moves it to the default mode.

- `2DC8:301C` keeps one record with two modes: one that matches the product string `IDLE` (a key `match.product` already has) and is idle, and a default mode that serves the linked pad. No Swift names the receiver.
- The 8BitDo bootloader identities (`2DC8:3208`, `2DC8:5750`) become bundled records whose default mode is idle for `Bootloader`, and `ControllerModelID.isBootloaderIdentity` goes. A user or package document cannot replace or patch a bundled record with that reason, because a write to a pad in bootloader state risks a bad firmware image.
- Observed on the maintainer's hardware: the receiver sends input as `301C` when the pad is in DInput mode and as `310A` when the pad is in XInput mode, so both records serve it. The idle mode can also match `bcdDevice` 0x0200; the linked receiver reads 0x0001.

### D9. `HIDDescriptor` records can declare rumble

The 2C's wireless modes declare output reports, and "fully supported" includes rumble. A `HIDDescriptor` mode takes the `rumbleTemplate` section the other families already use, which names the output report and its motor fields. The byte layout comes from a capture; the tasks do not assume it.

A mode declares rumble only for a write shown on hardware to run a motor. For `2DC8:301B` and for the receiver as `2DC8:301C` no such write is known (Context, 8BitDo), so each record declares none until task 2.6 finds one.

The bundled `301B` record names `OJD` as its `server`. With no `server`, OJD leaves the pad to macOS, macOS lists no controller for it, and a GameController game receives nothing; with `OJD`, the virtual gamepad is correct for every control the record maps (Context, 8BitDo). The fix is record data, and it holds whatever D16's detection decides. The published profile follows automatic selection, as for every other pad: `SDLCompatible` unless the user sets an override. This change leaves that rule as it is and researches two ways past it (tasks 9.13, 9.14).

### D10. Interrupt transfers in the extension pass timeout 0

Apple's `IOUSBHostPipe::IO` documentation requires 0 for interrupt endpoints, and #55 shows `kIOReturnBadArgument` with 2000 on the Xbox Elite Series 1. The extension passes 0 on interrupt pipes whatever `usbTransferTimeoutMs` holds; the field keeps its meaning for the direct route. A handshake that fails is retried with a growing delay and stops after a fixed count, so the extension cannot loop.

### D11. A pull request in an old format is redone on the release branch with the author credited

#50, #36, #39, and #47 target code and formats that do not exist on the branch. The maintainer re-creates the data as `v1alpha3` records and patches, credits the author in the commit, and then decides on the pull request. #56, #57, and #54 convert with `ojd migrate <folder>` after a rebase.

### D12. A patch removes keys through `remove`

A patch holds `patch` (a dictionary merged key by key; an array replaces the whole array, except `modes`, which D17 merges by `id`) and `remove` (a list of dotted key paths, the form of Apple's key-value coding). OJD applies `remove` first, then `patch`. A path that names no property of the record schema is refused. A path the record does not hold changes nothing. Migration turns each `null` in a `v1alpha2` patch into a `remove` entry.

### D13. Support is a ladder, and source is its last step

A controller reaches support by the first step that fits:

1. **Nothing.** The classifier binds it by its interface signature or its HID descriptor.
2. **A patch.** A `ControllerPatch` changes the fields of a bundled record that differ: an endpoint, a startup write, a control, a tuning value.
3. **A record.** A `Controller` states the model: modes, matches, input, rumble, tuning.
4. **A generator script.** One JavaScript file writes the records of a product family (D2).
5. **Source.** A protocol family OJD lacks: a handshake, an encryption, or a transport no document can state.

Steps 1 to 4 need no build and no pull request to work on the user's Mac; a pull request only shares the file. The rule for this release and after it: a per-model fact is a record field. A change that would add a model identifier or a model branch to Swift adds the record field instead. A repository test holds the line: Swift names a vendor and product pair only in the driver extension's match list, which Apple's entitlement fixes at build time.

The documentation shows the ladder with the command for each step, in the wiki and in `llms.txt`, so a person or an agent starts at step 1 and stops at the first step that works.

Alternative considered: a plug-in interface for compiled drivers. Rejected: it moves the source change into a second place and adds a binary contract to keep stable.

### D14. An input layout applies to any family

`input.layouts` is read for every protocol family. A layout selects reports by id and length, as it does today, and decodes the controls it names; the family's own decoder handles every report no layout selects and every control the layout leaves out. So a GIP wheel, or an XUSB pad with one moved button, is a record or a patch.

The layout vocabulary grows only from a capture. Task 8.4 lists what the wheel in #58 needs (`axes` holds at most 4 entries today).

Alternative considered: a wheel driver in Swift. Rejected by D13: the next wheel would need another one.

### D15. `v1alpha3` takes every known breaking change

This release already breaks the contract (D1, D3). It also takes the changes that a later release would otherwise break it for: the `remove` list (D12), idle as a mode state (D8), output for `HIDDescriptor` (D9), layouts for every family (D14), the removal of prose properties (D7), patches that reach every section and merge `modes` by `id` (D17), and `appIDs` in a profile's `applicationScope` (D25). After `v1alpha3`, a change to a document shape needs a defect that data cannot fix; a preference is not a reason. Additions (a property, an enumeration value, a kind) stay open.

The parts this release leaves unsettled are named, each with its task: whether the driver extension stays (4.9), whether scripts get type declarations (6.7), and how a served pad reaches a GameController game with no profile command (9.13, 9.14), and whether a profile can leave out `device` (16.4).

### D16. macOS serves a pad only when GameController lists a controller for it

`GCController.supportsHIDDevice` answers yes for the 2C over Bluetooth LE, and GameController lists no controller for it (Context, 8BitDo). So that answer is a first test and not proof, and a pad that rests on it alone gets a controller from neither macOS nor OJD until its user runs `ojd controller claim`. That is step 2 of the ladder for a pad that needs nothing else.

- OJD leaves a HID pad to macOS only while GameController lists a controller for it. A pad that passes `supportsHIDDevice` and gets no controller within a settle time is served as any other HID pad: OJD takes it and publishes the virtual gamepad.
- The warning about a second system controller follows the listed controller, not `supportsHIDDevice`.
- A record's `server` overrides the detection in both directions, as it does today for `OJD`.
- Task 9.11 measures, before any code, whether the service process sees GameController's list, how it ties a listed controller to a HID device, and the settle time. If the service cannot do it, the detection moves to a later change, and the record field stays the fix for each pad found (D9 for the 2C).

Alternative considered: fix only the `301B` record. Rejected as the whole answer: every other pad with this macOS behavior would need a patch from its user.

Alternative considered: OJD serves every HID pad it has a record for. Rejected: for a pad macOS serves, macOS keeps a second controller that gives no input beside OJD's (`PhysicalInterfaceSignature.swift:295-297`).

### D17. A patch reaches every section of a record, and a draft starts from any device

#63 shows a controller that no user document can fix (Context, What users ask for). Three rules close that gap, so step 2 of the ladder (D13) holds for every bundled record:

- A patch sets every property of a record except its identity (`vendorID`, `productID`), `capabilities` included. `ControllerPatch.sections` (`ControllerPatch.swift:62-65`) lists seven sections today; the list becomes the record schema's properties minus the identity.
- Entries of `patch.modes` merge with the record's modes by `id`: an entry whose `id` the record holds merges key by key into that mode, an entry with another `id` adds a mode, and the `remove` path `modes.<id>` removes one. Every other array replaces the whole array (D12). So a patch that adds a `HIDDescriptor` mode to a record does not restate the record's other modes.
- `ojd record draft` accepts every connected controller, served or not. For a device with a HID gamepad interface it drafts a `HIDDescriptor` mode; when a bundled record holds the identity, the draft is a patch that adds that mode. For a device with only vendor-class interfaces it drafts the identity and one mode per interface signature and names the input section as missing.

The record rule "capabilities must be deltas the driver of every mode declares" (`ControllerRecordDocument+Modes.swift:392-393`) refuses a record whose modes use two drivers when a capability belongs to one of them. Task 9.15 reads `capabilitiesAreDeclared(by:)` and picks one of two forms from what it finds: capabilities stated per mode, or the rule checked per capability against the modes that can hold it. This design does not pick, because the function was not read.

Alternative considered: let a user record replace a bundled record of the same identity. Rejected: the user's copy then misses every later fix to the bundled record, and D8 forbids it for bootloader identities.

### D18. A controller whose record fits no interface falls back to its HID descriptor

When a controller has a record, no mode of the record fits the interfaces the device exposes, and a HID interface of the device meets the `HIDDescriptor` contract, OJD serves it by the descriptor, as it serves a pad with no record (step 1 of the ladder). The controller detail and `ojd controller show` say that the record did not fit and name the rule `HIDDescriptor`. OJD does not fall back while an idle mode matches (D8), and a record or patch with `server` `System` keeps the pad with macOS (D16).

Reason: a record that describes one connection of a controller should not block a connection it does not describe. The GameSir G7 Pro dongle is the measured case; its bundled record gains the mode as data (task 8.16), so the fallback covers the next such device before anyone reports it.

This reverses the rule `wiki/Supported-Controllers.md:134` states, so the maintainer confirms it (Open Questions). Task 9.18 reads why that rule exists before it changes the classifier.

Alternative considered: no fallback, only the record fix. Rejected as the whole answer: each further device waits for a release or for its user to write a patch, and the reason it gives today has no text.

### D19. The menu bar item shows controllers and switches profiles

Purpose, in one sentence for the wiki and the audit: the menu bar item shows whether each controller works and changes its profile without opening the window. Its menu does five things: show each connected controller's state, choose a controller's profile, pause or resume a controller, open the window or Settings, and quit.

- **Rows.** Each connected controller is a row of the menu itself, with its name, its battery level when known, and the profile in force. LinearMouse, MonitorControl, and Karabiner-Elements put the device or the profile at the top level; OJD's "Controllers" and "Profiles" submenus add a level for the items people open the menu for.
- **Two levels.** A controller's submenu holds a checkmarked profile list with "No Profile", "Pause" or "Resume", "Test Input", "Show in Window", and "Disconnect" for a wireless controller. Nothing in it opens a submenu (`menus`: "Limit the depth and length of submenus."). The "Activate" and "Deactivate" lists go: a checkmark shows the profile in force (`menus`: "Consider using a checkmark to show that an attribute is currently in effect.").
- **Problems.** A problem that needs the user's action is the first row, named ("Input Monitoring is off", "The service is not running"), and choosing it opens its fix. The status line of three joined values goes.
- **Icon.** The symbol changes its shape while a problem row exists, and stays as it is with no controller connected.
- **Help commands** ("Activity Log", "Explain Error Code...", "Report Problem...", "Project Website") leave the menu and stay in the Help menu of the main menu, which shows while a window of the app is active. `docs/development/menu-bar-settings-architecture.md:78` already rules logs and reports out of the menu, and none of the five reference utilities holds a Help submenu.
- **Removal.** The item sets `behavior = .removalAllowed` (Rectangle, MonitorControl). Dragging it out with Command turns "Show in menu bar" off, turns "Show in Dock" on when it was off, and opens the main window (`the-menu-bar`: "Let people — not your app — decide whether to put your menu bar extra in the menu bar.").
- **A menu, not a popover** (`the-menu-bar`: "Display a menu — not a popover — when people click your menu bar extra.").
- Labels follow `LOCALIZATION.md`: an ellipsis only where the command needs more input, written `...` in English.

Alternative considered: keep one "Help" item that opens the Help area of the window. It costs one row and helps a user who runs OJD with no window open. Not taken in the specs; the maintainer can add it without changing another rule (Open Questions).

Alternative considered: a window under the item, as Apple's `sample-food-truck` shows with `.menuBarExtraStyle(.window)`. Rejected: the deployment target is macOS 12 and `MenuBarExtra` needs macOS 13, and the guideline asks for a menu.

### D20. Every control acts or says why, and the toolbar buttons stay

The rules, each a requirement in `specs/app-interface/spec.md`:

- A choice takes effect when chosen. A view that collects values before it applies them shows that changes are pending and shows the button that applies them.
- A control is unavailable while its request runs.
- A refused or failed request shows its reason beside the control that started it, and the control shows the value in force. The banner is for a problem that concerns no single control.
- A control offers only what the service accepts for the item in view.
- A control that cannot act is unavailable with its reason as text in its row. A tooltip is not enough: it needs a pointer held still, and VoiceOver users and people who do not know to hover never see it.
- A setting applies at once.

Each finding in Context becomes a task of group 12 only after task 10.5 reproduces it in the running app. The player indicator of Input Test is the first candidate for the report "the dropdowns do nothing": it is the one control that needs a second, separate click.

The toolbar buttons of the main window stay as they are. The maintainer chose that form, and Notes on macOS 27.2 uses the same one (Context, Reference apps). The one addition is a menu command for each of the 15 actions (`toolbars`: "Make every toolbar item available as a command in the menu bar."), which Notes also has, plus a Find command.

Sizes change only where a measurement shows a defect: the window minimum (960) exceeds what its columns need (790); one view sets a fixed point size; sheets use seven widths; spacing has no scale. The hit areas already meet the 28 pt guideline and stay.

Alternative considered: a redesign of the main window on `NavigationSplitView`. Rejected: it needs macOS 13, and no report names the window's structure.

### D21. One setting, "Interface", chooses Simple or Advanced

OBS Studio offers "Output Mode" with "Simple" and "Advanced" as a pop-up; MonitorControl offers a checkbox "Show advanced settings". OJD takes the OBS form the maintainer named: a pop-up button "Interface" in Settings > General, and the same two choices in the View menu.

- A fresh installation starts in Simple. An installation that migrates from 0.6.0-alpha.2 starts in Advanced, so no control its user had disappears.
- Simple shows the controller list, each controller's state and next step, the profile choice, Test Input, and the permission steps. Advanced adds the virtual gamepad kind, the choice of who serves a controller, tuning, identifiers, records and patches, and the activity log. Task 10.6 assigns every control to a level, and the maintainer confirms the list.
- The level hides controls and changes no behavior: the service never reads it, and `ojd` prints the same in both.
- A view in Simple that hides a value the user changed shows one row with the count and a button that switches to Advanced. Without it, Simple would hide the cause of what the user sees.
- The developer switch (`developerTools`) shows its tools only in Advanced.

The setting is the answer to "illiterate users, and everyday users alike, gamers and non-gamers, businesses and developers" together with D22 and the three controller states: a person who wants to play reads "Working", "Needs a step from you", or "Not supported yet", one sentence, and one button; a person who tunes or contributes switches one setting.

Cost: every view has two forms to test. The level decides only whether a row shows, never how it behaves, which keeps the second form a subset of the first.

Alternative considered: disclosure groups in each view (`disclosure-controls`). Kept as the tool inside Advanced for rarely used rows; rejected as the only tool, because each view would start with its own closed groups and the user would open them one by one on every controller.

Alternative considered: three levels with "Developer". Rejected: the developer switch exists and covers it.

### D22. One term names one concept, and the command line keeps its identifiers

`wiki/Glossary.md` defines each term the app, the prose of the command line, and the wiki show, with the words it replaces. A repository check reads the English strings for replaced words.

The command line keeps every command, flag, schema value, and error code (`Served by System`, `InterfaceSignature`, `NoProtocolMatch`, `SDLCompatible`): scripts and the other specs of this change read them. The window, the menu, and the wiki use the glossary's phrase, and the glossary entry names the command-line value it stands for. Advanced shows the identifier beside the phrase; Simple shows the phrase alone.

Proposed terms. Each is a proposal the maintainer settles before task 14.2 changes a string (Open Questions). The counts are values of `en-US.lproj/Localizable.strings` that hold the word, counted on 2026-11-11:

| Concept | Words in use | Proposed term |
| --- | --- | --- |
| A set of bindings for a controller | "profile", "remapping profile" | "profile", and nothing else carries that word |
| The gamepad OJD publishes to games | "virtual device" (6 strings), "virtual controller" (2), "Virtual HID profile" (2), "persona" (4) | "virtual gamepad", which 39 strings use |
| Its three forms (`SDLCompatible`, `GameControllerCompatible`, `Generic`) | "profile", "persona", the raw identifiers | "virtual gamepad kind", with the options "For Steam and SDL games", "For Apple Game Controller games", and "Generic HID gamepad" |
| Who reads the physical controller | "Served by", `System`, `OJD`, "Left to macOS", "macOS (native)", "OpenJoystickDriver (virtual)" | "Handled by macOS" and "Handled by OpenJoystickDriver" |
| OJD's DriverKit extension | "Xbox USB driver" (7 strings), "Driver Extension" (3), "system extension" (1), "DriverKit" (1), and more in the wiki | "Xbox USB driver" |
| How a controller reaches the Mac | "connection" (18 strings), "transport" (6), "Wireless Link" (2), "mode" | "connection": cable, receiver, Bluetooth |
| What the controller's own switch selects | "mode", "protocol" | "mode" |

"Backend" is in no English string of the app. The flag `--sdl-gamecontroller-backend` keeps its name, and `wiki/Command-Reference.md:48` and `wiki/Playing-Games.md` take the glossary's terms.

Alternative considered: rename the command-line values too. Rejected: it breaks scripts and the JSON output for a wording change, and D15 allows a breaking change only for a defect data cannot fix.

### D23. The interface is measured against named references before it changes

Group 10 writes `docs/development/interface-audit.md` before any task of groups 11 to 13 changes a view. Each row names the view, the guideline page it answers to, the Apple app or open-source app it was compared with, each difference, and "fix" with a task or "keep" with a reason. The toolbar reads "keep".

References, in the order they decide a question: the Human Interface Guidelines; an Apple app on the maintainer's Mac, read through Accessibility (roles, names, sizes; `evidence/interface-reference/`) and through screenshots the maintainer takes; an open-source app at a named commit. Apple publishes no source for Notes or System Settings, so its sample code (`sample-food-truck`, `sample-backyard-birds`) is the only Apple source and shows structure, not the look of a utility.

Reason: "as if it was designed by Apple's graphics designers" cannot be checked, and "two sheets of one kind are 470 and 480 pt wide, fixed in task 12.12" can.

### D24. Mapper features are written for OJD's data, and no InputConfig code is copied

InputConfig is under the MIT license and OJD under PolyForm Noncommercial 1.0.0. MIT allows reuse with its notice kept; this change copies no code and no preset file, so it adds no notice. Each feature is specified by its behavior in `specs/mapper-features/spec.md` and built on OJD's records, which is what lets it cover the 706 bundled records:

| Feature | What makes it work for every record |
| --- | --- |
| Live view | Drawn from the controls a record or a HID descriptor declares, by control kind; no drawing per model |
| Calibration view | Shows the raw value and the value after the record's tuning; task 16.2 reads which of the two the status RPC carries |
| Templates | Bind controls by their controller-independent `source` names |
| Conversion to another model | Same `source` names; a binding with no target control is listed and left out |
| Sort and notes | Profile data only |
| Pause shortcut | Calls the pause the menu already has |
| Idle disconnect | Bluetooth only; uses the disconnect the menu already has |
| System action bindings | Additions to the binding vocabulary |
| What changed | Reads `CHANGELOG.md` |

Not taken, each with its reason: a polling-rate setting (a per-model write with no capture behind it); adaptive trigger effects and profiles stored on the pad (each needs one vendor's protocol); MIDI input, keyboard and mouse as inputs, and Stream Deck support (outside a controller driver); press-to-assign (OJD has it).

InputConfig's 456 library presets are data under MIT. Task 16.10 measures whether an importer is worth writing: how its preset format maps to an OJD profile, and what the notice requires. No importer is in this change.

### D25. A profile applies to a list of apps

`applicationScope` of type `Application` holds `appIDs`, a list of one or more bundle identifiers; `appID` leaves the schema, the reader refuses it (`single_format`), and migration converts it. `--app` repeats on the commands that take it. The profile sheet and the editor offer running and installed apps with icon and name, plus "Other..." for an open panel. The menu bar item and the controller detail show the profile in force and name the app that selected it.

Reason: the service already selects a profile by the app in front; the gaps are the typed identifier, one app per profile, and no sign of which profile is in force.

A virtual gamepad kind per app stays research (task 9.14): replacing the published gamepad disconnects it from a running game, and that cost is not measured.

Alternative considered: keep `appID` and add `appIDs` beside it. Rejected by `single_format`.

### D26. A tester build is a public pre-release

A build that fixes a reported issue is published as a pre-release on GitHub Releases, signed and notarized by the release workflow, and linked from the issue. The update check finds it for a user who turned on "Include prerelease updates", a setting OJD already has; no second setting is added. The survey's most frequent ask (about 16 users, an agent's tally) is a build they can install without building from source.

Publishing is the maintainer's action each time.

### Release order

Groups 10 to 12, 14, and 17 fix what users and the maintainer report. Groups 13, 15, and 16 add features, and each can leave this release without changing another group. Within group 16 each task stands alone. The maintainer decides which stay (Open Questions).

## Risks / Trade-offs

- A layout that overrides a family decoder can hide a control the family decodes correctly → a layout changes only the controls it names, and `ojd record test` replays a capture against the record before it ships.
- A bootloader record a user cannot override is a rule that differs from every other record → the refusal names the reason, and the rule covers only the `Bootloader` reason.
- The identifier test can block a legitimate protocol constant → the test reads an allow-list file where each entry carries its reason.
- The detection of D16 can take a pad that macOS lists late → the settle time comes from a measurement (task 9.11), and a record or patch with `server` `System` keeps the pad with macOS.
- The 2C result comes from one Mac on macOS 27.2 → the `301B` record's `server` is explicit data, and a user on a Mac where macOS lists the pad runs `ojd controller release 2DC8:301B`.

- The format change touches every reader, writer, test, and script → land it in one commit with the migration step, and keep the equivalence snapshots (`Tests/EquivalenceSnapshots`) as the proof that decoded models did not change.
- XML is about twice the text of JSON for a hand-written record → the wiki shows `plutil -convert` in both directions, and `ojd migrate <folder>` accepts JSON.
- Editors lose JSON Schema hints for the documents → the validation output names the key path and the schema rule for each error.
- A crosswalk key left out does not show whether the author checked that standard → `test_crosswalk_table.py` keeps its coverage rule for the standards that need a value.
- Automatic migration rewrites user files → each original is kept in `Migrated/`, the run is logged, and `--dry-run` prints the plan.
- The direct route for `02D1`, `02DD`, `02E3`, `0B0A` has hardware proof for `02D1` only → the other three stay marked unverified until a reporter confirms.
- A user who relied on automatic activation for an Apple-held model gets macOS's own driver → the controller row says "Served by macOS" and offers Claim.
- The receiver hypothesis (D8) may be wrong → task 2.1 runs first and D8 names the other outcome.
- Removing descriptions loses knowledge → each removed fact that still holds moves to the wiki in the same commit (`stale_doc`).
- `2DC8:2027` may fail below OJD (libusb fails too) → the release notes list it as unsupported unless the reporter confirms a tester build.
- Generators are the least-tested part → group 6 depends on group 1 only, and can leave the release without changing any other group.
- The change holds 19 task groups for one alpha release → groups 13, 15, and 16 are separable (Release order), and the maintainer cuts them without touching a fix.
- The interface findings come from reading source, not from the running app → task 10.5 reproduces each one before group 12 changes it, and a finding that does not reproduce is closed in the audit with its steps.
- Simple can hide the control a user needs → the row for changed hidden settings, the View menu items, and Advanced as the level after migration.
- Two levels double the views to test → the level only hides rows, and one test per view asserts that Simple's rows are a subset of Advanced's.
- A renamed label breaks a user's memory, screenshots in issues, and every translation → the glossary lists each replaced word, and the terms are settled once, before task 14.2.
- The HID fallback (D18) can serve a device through an interface its record's author meant to skip → the fallback never runs while an idle mode matches, the detail says that the record did not fit, and a patch with `server` `System` turns it off for a model.
- Mode merge by `id` changes what an existing `v1alpha2` patch with `modes` means → migration adds the path `modes` to the `remove` list of such a patch, so the patch still replaces the whole array (task 9.15).
- A menu with no Help submenu leaves a user with no open window one step further from "Report Problem..." → "Open OpenJoystickDriver" is in the menu, and the alternative in D19 costs one row.
- Removal by Command-drag can leave a user without the item by accident → the main window opens at once, and Settings holds the switch.
- A public tester build reaches users who did not ask for it → only through "Include prerelease updates", which is off by default.
- A feature specified from InputConfig's behavior can drift into copying its text or layout → D24 names what is taken as behavior only, and task 16.10 handles its data and notice separately.

## Migration Plan

1. Land the `v1alpha3` schemas, the property-list readers and writers, the converted bundled data, and the `AlphaTwoToAlphaThree` step in one commit.
2. Land the start-time migration and the app entry points.
3. Publish schemas under `schemas/v1alpha3/`.
4. Rollback: restore files from `Migrated/` and install alpha.2.

## Open Questions

- Do the rear buttons of the 2C have their own bits in each wireless mode? (task 2.3)
- What are `2DC8:301D` and `2DC8:3109`? Their records are unverified. (task 2.7)
- Why does `gamecontrollerd` not take the 2C's HID service over Bluetooth LE while `supportsHIDDevice` answers yes, and which other HID pads behave so? (tasks 2.11, 9.11)
- A pad OJD serves reaches a GameController game only after the user sets the `GameControllerCompatible` profile, because automatic selection never picks it and SDL reads no input from it (`wiki/Playing-Games.md:24,34`). Can one profile serve both, or can OJD pick the profile by the app in front? The maintainer chose research on both for this release (tasks 9.13, 9.14); no task in this change alters profile selection.
- Can OJD serve `045E:02EA`, `0B00`, and `0B12` through Apple's HID device, which would allow removing the extension? (task 4.9)
- Should OJD ship a type declaration file for generator scripts? (task 6.7)
- Which terms does the maintainer choose from the table in D22? In particular "Handled by" against the "Served by" the command line prints, and the three names of the virtual gamepad kinds. (task 14.1)
- Which of the feature groups 13 (Simple and Advanced), 15 (per-app profiles), and 16 (mapper features) stay in 0.6.0-alpha.3?
- Does the maintainer accept the HID fallback of D18, which reverses `wiki/Supported-Controllers.md:134`? (task 9.18)
- Does the menu keep one "Help" item for a user with no open window? (D19)
- The deployment target is macOS 12 (`Package.swift:33`). `NavigationSplitView` and `MenuBarExtra` need macOS 13. Does the target stay?
- Should the toolbar be customizable, as Notes offers through "Customize Toolbar…"? No spec asks for it.
- "Businesses": PolyForm Noncommercial 1.0.0 does not permit commercial use. What does the maintainer want for a company that deploys OJD, and is a managed installation (a configuration profile that approves the driver extension and the permissions) in scope for a later change? The wiki start page "set up OJD on several Macs" states only what the license and macOS allow today.
- Can a profile leave out `device` and apply to every controller that has its source controls, which would make conversion unnecessary? (task 16.4)
- Is an importer for InputConfig's preset library wanted, with its MIT notice? (task 16.10)
- Which users reported that dropdowns do nothing, and on which view? No issue names it; a pointer from the maintainer lets task 10.5 start at that view.
