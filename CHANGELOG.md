# Changelog

All notable project changes are recorded here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Catalog the Microsoft Bluetooth Xbox controllers SDL lists (Xbox One S `045E:02E0`/`02FD`, Elite 2 `0B05`/`0B22`, Adaptive `0B0C`/`0B21`, and Series `0B13`/`0B20`) as `hid.descriptor`. The layout now comes from the report descriptor: the Linux firmware mode (Z/Rz right stick, Brake and Accelerator triggers, View on Consumer AC Back, Share on Consumer Record, Guide on Consumer AC Home) and the Windows mode (Rx/Ry right stick, Z/Rz triggers, Guide on System Main Menu) are both mapped, following xpadneo's recorded descriptors. The GameSir G7 SE is now recognized by its descriptor instead of a product-ID list. Rumble over Bluetooth (output report `0x03`) is not sent yet. None is hardware-verified.
- Map the 8BitDo Ultimate 2C Wireless over Bluetooth LE (`2DC8:301B`) and its HID receiver identity (`2DC8:301C`) through `hid.descriptor` with the GameSir G7 SE layout: Z/Rz right stick, Accelerator as RT, Brake as LT, and Android-order buttons with Home. The rear buttons stay unmapped. `301C` is not hardware-verified.
- Add the `vendor.ps3-third-party` family for non-Sony PS3 controllers and route every non-Sony `PS3Controller` identity in SDL's list to it. As SDL's `PS3ThirdParty` driver does, a feature-report probe identifies the fixed report format, and a device that fails it keeps the descriptor mapping. Input is decoded from the raw report because the descriptor's axis ranges are wrong. The Ant Esports GP100 (`2563:0575`) is read from its hardware-verified bytes only. The ShanWan DS3 (`2563:0523`) joins `sony.sixaxis`, and HORI `0F0D:0086` joins `xbox.xusb`, matching the SDL driver that claims each one. Only the GP100 has hardware evidence, and it is the only one with rumble: output report 2, confirmed with an owner's script. The report comes from the GP100's record (`output.rumble`), not from the driver. OJD sends it even when macOS serves the GP100 natively, because macOS has no driver for that report.
- Catalog the 11 non-Sony `PS5Controller` identities in SDL's list (HORI, PDP Victrix, Razer, NACON, Backbone One PlayStation Edition) as `sony.dualsense`. For a non-Sony controller the DualSense driver follows SDL's `HIDAPI_DriverPS5`: it reads feature report `0x03` for the controller's features and limits output to them, never sending adaptive triggers. It decodes SDL's alternate report layout, and it waits on a wireless receiver's packet sequence to connect or disconnect the controller. The Razer and NACON quirks come from SDL. The Backbone One PlayStation Edition Gen 2 (`358A:0304`) is catalogued as `hid.descriptor`, because SDL says it does not use the DualSense protocol. None is hardware-verified.
- Map the 20 wired Switch pads SDL lists as `SwitchInputOnlyController` (HORIPAD, PDP Faceoff, PowerA wired pads, ZUIKI MasCon and others) to `nintendo.switch1` with the new `input-only` quirk. The `SwitchInputOnlyDriver` decodes their fixed report by byte offset. These pads previously had no catalog record. No output is sent. None of these pads is hardware-verified.
- Support the 2026 Steam Controller (Triton): `28DE:1302` over USB, `1303` over Bluetooth LE, and the `1304`/`1305` dongles. The new `triton` quirk selects `SteamTritonDriver`, which decodes buttons, rear buttons, trackpads with pressure, motion and battery, and holds rumble with a 40 ms resend. A dongle runs one controller per interface 2 to 5. These identities previously had no catalog record. None is hardware-verified.
- Support the original Steam Controller over Bluetooth LE (`28DE:1105`, `1106`, and the HEADCRAB `1202`) and the wired prototype IDs `1101` (CHELL) and `1201` (HEADCRAB). OJD joins the report `0x03` segments into one packet, keeps the chunks that a packet leaves out, and sends settings as segments, as SDL `SDL_hidapi_steam.c` does. Records now store the new `bluetooth-le` variant. None is hardware-verified.
- Support the Switch 2 Pro Controller (`057E:2069`), the Joy-Con 2 (`2066` right, `2067` left) and the NSO GameCube controller (`2073`) over USB. The new `switch-2` quirk selects `Switch2Driver`, and `gamecube` selects the GameCube layout. The driver follows SDL `SDL_hidapi_switch2.c`: it sends the init sequence on the vendor bulk interface, reads the stick calibration from flash, decodes report `0x05`, sets the player LEDs, and sends HD rumble (PWM rumble on the GameCube controller). Motion is not supported yet. None is hardware-verified.
- Connect the Switch 2 Pro Controller, Joy-Con 2 and NSO GameCube controller over Bluetooth LE. OJD scans for a controller in sync mode, connects over GATT without pairing, and runs the same `Switch2Driver` over the GATT input, command and vibration characteristics. Press the sync button each time the controller connects. macOS asks for Bluetooth access on first start. Two Joy-Con 2 can be paired as one controller like the first-generation Joy-Con. The transport follows ndeadly's `switch2_controller_research` and `joycon2cpp`. It is not hardware-verified.
- Support the Steam Deck's built-in controller (`28DE:1205`) when macOS runs on Deck hardware. The new `neptune` quirk selects `SteamDeckDriver`, which decodes buttons, rear buttons, sticks with touch, analog triggers, trackpads with pressure and motion, turns off lizard mode and its watchdog, and sends rumble. It is not hardware-verified.
- Support the NVIDIA SHIELD controllers with the new `vendor.nvidia-shield` family: the 2015 controller (`0955:7210`, V103) has input, touchpad click and rumble, and the 2017 controller (`0955:7214`, V104) is input-only on macOS. The report layouts follow SDL `SDL_hidapi_shield.c`. SDL disables V104's command-report rumble and battery on macOS because the write hangs, so OJD does not send it.  `0955:7210` previously had no record. Not hardware-verified.
- `ojd permission list|request`, `ojd extension status|activate|deactivate`, `ojd setting list|get|set`, `ojd log path|show`, `ojd diagnose [--bundle PATH] [--soak SECONDS]`, and `ojd update check [--prerelease]`. See the [command reference](docs/Command-Reference.md).
- User controller records: an `add` or `patch` file in `~/Library/Application Support/OpenJoystickDriver/Controllers` adds a controller model or changes the `protocol`, `usb`, `ownership`, `output`, or `input` fields of a bundled one, and the running service applies it when the folder changes. OJD skips a file that is not valid and names it in `ojd status`, the `controller-records` check of `ojd diagnose`, and `ojd record list`. `ojd record list|show|validate|install|remove` manage the files. See [Adding or changing a controller record](docs/Controller-Records.md).
- The Settings section of the app has an Install Command-Line Tool action that links `/usr/local/bin/ojd` to the app and removes the link again. macOS asks for an administrator password when the folder is not writable, and the action never replaces a file that is not a link.
- Add the `hid.report-layout` family. Its records describe a fixed input report in a new `input` field: report ID and length, buttons as byte and bit mask, 8- or 16-bit stick axes with signedness, range and inversion, hat sources (8-way bits or one bit per direction), and analog or digital triggers. The Ant Esports GP100 (`2563:0575`) and the Logitech ChillStream (`046d:cad1`) move from `vendor.ps3-third-party` to this family, so their input is data in their records. The ChillStream no longer advertises a Home button, which it never sent, and the record reads its reports of 19 bytes or more with the 18-byte offsets. The Saitek Cyborg V.3 (`06a3:f622`) stays in `vendor.ps3-third-party` with the new `dpad-pressure` quirk in its record. Not hardware-verified after the move.
- Controller records take two new fields. `ownership: ojd` makes OJD open a controller exclusively even when macOS serves it natively; `macos`, the default, leaves it to macOS. Raw-USB families do not take the field. `output.rumble` names a `hid.report-layout` or `vendor.ps3-third-party` controller's rumble report: its kind, report ID and length, and the byte of each motor. Lighting and player-indicator templates are not supported yet. See [Adding or changing a controller record](docs/Controller-Records.md).
- Controller records take `output.startup`: 1 to 16 fixed HID output or feature reports that OJD sends, in order, after the protocol driver's startup when it opens a controller. Each write can wait up to 1000 ms first and can be limited to one transport. The DualShock 3 Bluetooth enable report (`F4 42 03 00 00`) moves from `SixaxisDriver` into the `054C:0268` and `2563:0523` records with `transport: bluetooth-classic`; the bytes sent are unchanged. See [Adding or changing a controller record](docs/Controller-Records.md).
- `ojd record draft CONTROLLER [--duration SECONDS]` prints a starting record for a connected controller. It maps the buttons, sticks, triggers, and hat its HID report descriptor states plainly as `hid.report-layout`, and lists the report bytes that changed while you pressed each control. Not hardware-verified.
- `ojd controller show` names the record for the controller's model: bundled, one of your records with its file, or none. `--json` reports it as `controller.record`.
- `ojd binding clear` warns when it leaves an active profile with no input binding.
- `ojd virtual feed --as PROFILE` publishes a virtual gamepad that JSON lines on standard input drive, and prints the rumble commands games send to it. See [Automating OpenJoystickDriver](docs/Automating-OpenJoystickDriver.md).
- Unit IDs: `ojd controller list` and `show` report a `U-` ID for each controller with a location ID. It comes from the model, USB port, and interface under a key kept per installation, never the serial number, and it stays the same across service restarts while the controller uses the same port. `CONTROLLER` accepts it. `ojd virtual set|reset --unit` stores a virtual gamepad choice for one controller, and a profile's `device.unit` limits it to one controller. See the [command reference](docs/Command-Reference.md).
- `Resources/Schemas/cli-output.schema.json` describes the `--json` output of every `ojd` command, one `$defs` entry per command. The CLI tests validate each `--json` document they print against it.
- `Resources/Schemas/profile.schema.json` describes the profile file that `ojd profile export` writes. `ojd profile validate FILE|-` checks a file against the schema and the cross-field rules without the service.
- `ojd profile get PROFILE KEY` and `ojd profile set PROFILE KEY VALUE` read and change one value in a profile file by its path, such as `stickMappings.0.tuning.innerDeadzone`. `set` checks the whole profile before it saves it.

### Changed

- **BREAKING:** The command line is a separate program, `ojd`. The app executable runs it when started under the name `ojd`, for example through a link named `ojd` on your `PATH`, and runs the app under any other name, so `--headless` is gone. Every command takes the global options `--json`, `--plain`, `--quiet`, `--no-color`, `--no-input`, and `--timeout`, prints errors as `ojd: <message>` to stderr, and exits with 0, 1, 64 (usage), 69 (service unavailable), 77 (permission), or 130 (interrupted). See [Using the command line](docs/Command-Line.md).
- **BREAKING:** Commands no longer start the service implicitly. Run `ojd service start` first; a command that needs the service exits with code 69 while it is stopped.
- **BREAKING:** `ojd status` replaces `status` and `app status`. It works when the service is stopped, and its `--json` object and `--plain` lines have the new shape in the [command reference](docs/Command-Reference.md).
- **BREAKING:** The minimum system is macOS 12 (was 10.15), and iOS and iPadOS 15 for companion apps.
- **BREAKING:** Saved remapping profiles now decode strictly at every level. A profile with an unknown field anywhere, such as the removed `gyroOutput.virtualMotion`, or a field that belongs to another source, destination, output, or scope type, loads as a damaged profile that can be recovered or removed in the Profiles UI instead of being silently accepted.
- Automatic virtual output publishes one of two profiles chosen only from the controller's declared controls: Xbox One S Bluetooth (`hid-xbox-one-s-bt`, `045E:02FD`) when they fit, OJD generic HID (`hid-generic`) otherwise. Browser- and consumer-based routing and the automatic DualShock 4, DualSense, Switch Pro, and Xbox Series (`045E:0B13`) identities are removed. A per-model override can still pin either profile with `ojd virtual set`. Consumer binding of `045E:02FD` is not yet hardware-verified.
- **BREAKING:** Remove the `compat` command family and compatibility identities. Choose between the two virtual HID profiles per controller model with `ojd virtual set
  <hid-xbox-one-s-bt|hid-generic>` and `ojd virtual reset`; `status` now reports each
  controller's virtual profile and whether it came from an override or automatic selection.
- **BREAKING:** Remove the old compatibility RPCs, client methods, and status identity fields. Per-controller status now carries `profile`, `source` (`automatic`, `override`, or `automatic-after-rejecting`), `override`, and `unavailable` instead.
- **BREAKING:** Rename the remapping wire route `compatibility` to `virtual-gamepad` and the status field `compatibility_output_suppressed` to `virtual_output_suppressed`.
- **BREAKING:** `hid-generic` is input-only and publishes as `1209:4A4F`, a vendor and product ID that pid.codes allocated to OJD. Its descriptor no longer declares the vendor rumble output report, so apps cannot rumble a controller through it, and the new ID keeps hosts from reusing a descriptor cached for the former `4F4A:4449`.
- **BREAKING:** Remove virtual motion (gyro relayed through the virtual controller) and the Xbox 360 Mac/DirectInput, DS4/DualSense USB, and Switch Pro USB virtual formats and their host protocols.
- **BREAKING:** Remove the unused `listDevices` and `runVirtualDeviceSelfTest` application-service RPCs.
- **BREAKING:** Remove the PlayStation, Nintendo, and Steam glyph families from Input Test; it shows Xbox or generic glyphs.
- Send physical output through one application-service request, `sendControllerOutput`, which carries one output command (`set-rumble`, `stop-rumble`, `set-player-indicator`, `set-rgb`, `set-light-brightness`, or `set-adaptive-trigger`) and returns a `ControllerOutputResult` (`outcome` plus `droppedRumbleChannels`). It replaces `sendPhysicalRumble`, `setPhysicalPlayerIndicator`, `setPhysicalColor`, and `setPhysicalBrightness`; older clients must be updated with the app.
- `ojd controller rumble|player|light` no longer pre-check capabilities in the CLI; the app decides support and the CLI reports its result. `rumble` no longer refuses a request that names a trigger motor the controller lacks: it drives the channels the controller has, warns about each missing trigger motor, and exits successfully; a request whose every channel is missing fails. Through the application service and the GUI such a request (for example a DualShock 4 trigger-only rumble) previously reported success silently; the result now lists the dropped channels. `rumble --duration` returns once the app accepts the command, and the app stops the rumble when the duration ends instead of the CLI sending a second stop.
- A stop-rumble, including every all-zero rumble report an application writes to a virtual controller, writes the physical controller once instead of twice and cancels a pending timed stop.
- Reuse canonical GIP, GameSir, DualShock 3, Steam Controller, and Switch Pro packet construction, and share test-only protocol fixtures with the macOS 14 compatibility harness.
- Keep local commit and push hooks fast by reserving full lint, build, test, and network-backed catalog validation for explicit checks and CI.
- Use IOKit HID on every supported macOS: physical controllers through `IOHIDManager` and virtual controllers only through `IOHIDUserDevice`. CoreHID is no longer linked.
- Tear every controller session down on system sleep and rediscover controllers through normal hot-plug on wake. A controller suspended before sleep stays suspended after wake.
- Expose one typed raw-USB transfer contract (bulk and interrupt endpoints plus control transfers) on both the IOUSBHost and USBDriverKit backends.
- Build scripts use the Xcode chosen with `xcode-select` instead of the newest installed Xcode.
- Bind controllers through one protocol classifier and driver registry. A device no driver binds is no longer driven as generic HID; `status` lists it with a typed reason, and OJD releases its claim so macOS keeps the device.
- Bind uncatalogued wired Xbox-protocol controllers by their USB protocol signature (for example the Razer Wolverine Tournament Edition), and read each raw-USB controller's interface and endpoints from its own configuration descriptor instead of assuming protocol defaults. This fixes Razer controllers whose LED stayed off because OJD used the wrong endpoints.
- Restart the Xbox One (GIP) startup sequence when a freshly plugged-in controller announces itself before sending input, so controllers that were still booting no longer stay silent.
- Recognize 218 more wired controllers from SDL's pinned controller list (Xbox One, Xbox 360, DualShock 4-compatible and Switch Pro-compatible pads). Rows that SDL itself drives with a different protocol or report layout are left out.
- Run HID input seize, release and retry on the main thread, where `IOHIDManager` removes devices, so a device that detaches during an open no longer loses its plug-in on another thread. This may relate to the hotplug crash in the known issues; that is not confirmed.
- The catalog generator now handles the SDL rows it used to skip, and the catalog holds 696 records. It catalogs the DualShock 4 USB wireless adapter (`054c:0ba0`), the STRIKEPAD grip add-on (`054c:05c5`) and the PlayStation Access Controller (`054c:0e5f`) from their SDL types, and the DragonRise generic USB PCB (`0079:0006`) as `hid.descriptor`. It marks the PDP Afterglow Wireless (`0e6f:0186`) and HORI Wireless Switch Pad (`0f0d:00f6`) with the new `bluetooth-only` quirk, so OJD binds only their Bluetooth link because USB only charges them. It writes no record for virtual identities that no USB device carries (Apple's MFi identities, the Joy-Con pair, Steam's virtual gamepad, NVIDIA's streaming controller). It writes no record for SDL's XInput PlayStation and Switch pads, or for an Xbox One row that carries a Microsoft Xbox 360 product ID, and leaves them to the USB interface signature instead of pinning one protocol that the firmware mode decides. It accepts Linux xpad Xbox One rows flagged `FLAG_DELAY_INIT`, because the GIP driver already waits for the announce packet. None is hardware-verified.
- A record of one Xbox USB family now binds by the other family's interface signature when the device exposes only that one, because a pad can ship either firmware mode under one VID:PID.
- Apply DualShock 4 factory motion calibration only to Sony controllers; third-party pads keep nominal scaling.
- Fix memory corruption after a HID controller's input stream closed (for example on sleep or a permission change): IOKit could write a late input report into a buffer OJD had already freed.
- Each controller protocol is now one driver that owns its startup, keep-alive and output encoding. Keep-alive packets no longer wait for controller input (idle Xbox One pads now get their 4-second status packet), and a failed startup report no longer stops the remaining ones.
- Each Xbox 360 wireless receiver slot and each Steam Controller dongle slot is now its own controller: it appears when a pad connects, disconnects on its own, and shows its slot's player LED. Receivers now ask the receiver which pads are present instead of assuming one.
- Xbox 360 wireless receiver slots, including uncatalogued 2.4 GHz dongles that bind as receivers (for example the ZD Ultimate Legend `413D:2204`), now take their ring-LED player slot from the same pool as wired pads. The manager assigns it and the LED lights when the pad connects. Before, every single-slot receiver showed player 1.
- Read the rumble magnitudes of the Xbox One output report (`0x03`) on 0–100, the range the virtual controller's descriptor declares and SDL sends. Before, full strength from a game arrived at 39%.
- `controller list` and `status --json` show a controller's USB interface number (`if=N`).
- Remove the extra 8% stick dead zone that six drivers applied on top of the remapping and virtual-output dead zones, and report L2/R2-style trigger buttons from the controller's own digital signal when it has one (otherwise from one shared threshold). Disconnecting now releases every stick and trigger to exactly neutral.
- Fix inverted vertical stick axes on the DualSense and DualShock 3 in remapping, and on generic HID controllers.
- Touch contacts report a slot, an active flag and X/Y from 0 to 65535 across the surface, with the top edge at 0, and each touch frame carries one monotonic timestamp. This fixes inverted up/down swipes, grid rows and pointer motion on the Steam Controller trackpads. The touch JSON of `getControllerState` changes shape: it no longer has raw coordinates, a touch counter, a history index or surface dimensions.
- Read the Xbox Series X|S Share button from the correct report byte.
- A remapping profile that binds a trigger no longer leaks that trigger's click to the virtual controller, and remapping onto a trigger also sets the virtual controller's digital trigger button.
- Controllers now report complete input snapshots instead of individual changes. `controller input` prints the full state, the RPC method is `getControllerState`, and remapping compares each controller's snapshot with the previous one. This fixes a button that shares a virtual-pad bit with another (for example Start and Options) being released while the other is still held, a remapped press lost after switching to passthrough and back, and a held Guide button reappearing after the controller session resumes.
- Battery and connection details are reported as the controller gives them: a DualShock 4 shows its battery bucket (`0-9%`) instead of a made-up midpoint, `cable` becomes `wired-power`, and `status --json` and support reports carry a `connectionState` with the controller-side link (`usb`, `bluetooth-classic`, `proprietary-radio-receiver`, or none when unknown) instead of `battery`.
- Controllers that macOS supports natively (for example DualShock 4 and DualShock 3) stay macOS gamepads: OJD reads them without taking exclusive access, runs remapping profiles on them, and publishes no virtual pad. `status` marks them `native=macos virtual=none`. OJD writes to them only where macOS leaves something undone (the DualShock 3 player LED).
- Controller records name their protocol by family and stored variant (`"protocol": {"family": "xbox.xusb", "variant": "receiver"}`) with no `transport` field; `status`, `list`, JSON output and support reports show a `protocolBinding` such as `xbox.gip:usb` instead of `parser` and `protocolVariant`.
- Controller records use typed protocol-scoped quirks (`share-offset`, `joy-con-left`, `joy-con-right`), capability data (`capabilities.absent`/`present`, `rumble: "absent"`) and named GIP initialization actions (`xbox.gip/power-on`, ...) instead of quirk strings and `startupPackets`; GameSir variants are `usb` and `enhanced-hid`, with the G7 Pro 8K and Cyclone 2 differences expressed as the quirks `inner-grips` and `lighting-slots`. The `quirks=` field of `list`, `status` and support reports and the record probe's `startup=` field print these new names.
- Each controller reports the controls it provides (`capabilities` in `status --json`, replacing `physicalInputCapabilities`); the profile editor offers only those controls.
- Check a raw USB controller's interface class and endpoints against its protocol before the first write; a mismatched device is listed as unbound instead of being written to.
- Controller records reject vocabulary no runtime consumer reads: the `XboxAdaptiveJoystick` driver, `unknown` protocol variants, `usb.interface`, and unconsumed per-driver quirks.
- Controller-record validation rejects protocol-default USB endpoints for every driver, not only GIP and Xbox 360, so such a record fails the catalog checks instead of the app at launch.
- Replace the repository agent skills with `ojd-controller-catalog`, `ojd-hardware-evidence`, `ojd-swift-change`, `ojd-app-ui`, `ojd-repo-tooling`, and `ojd-build-sign-release`, also exposed to Claude Code through `.claude/skills`. The retired skills are `add-controller-openjoystickdriver`, `debug-controller-openjoystickdriver`, `design-openjoystickdriver`, `maintain-openjoystickdriver`, `organize-openjoystickdriver`, and `test-openjoystickdriver`.
- Revise the command-line translations of 66 locales: consistent terms, native quotation marks, and decimal points in typed option values.

### Removed

- **BREAKING:** Remove every command of the old command line, with no aliases. Each is replaced as follows:
  - `--headless` → run the executable as `ojd`; `--json-lines` → `--json`
  - `status`, `app status` → `ojd status`
  - `app ready` and implicit service launches → `ojd service start|stop|wait`
  - `controller list`, `controller output list` → `ojd controller list`
  - `controller state` → `ojd controller show`
  - `controller watch`, `test` → `ojd controller watch`
  - `controller packets`, `controller trace` → `ojd controller capture`
  - `controller output rumble` → `ojd controller rumble`; `--duration-ms` → `--duration` in seconds
  - `controller output color`, `controller output brightness` → `ojd controller light --color|--brightness`
  - `controller output player` → `ojd controller player`
  - `controller output plan` → the Output checks section of `ojd controller show`
  - `controller disconnect`, `controller resume` → `ojd controller suspend|resume`
  - `controller disconnect-wireless` → `ojd controller disconnect`
  - `controller virtual set|reset` → `ojd virtual set|reset`; `ojd virtual show` lists each controller's profile
  - `map list` → `ojd profile list`; `map show` → `ojd profile show`
  - `map create` → `ojd profile create`; `map update` → `ojd profile rename` for the name and `ojd profile edit` for every other setting, including the `--stick-` and `--motion-` options
  - `map delete` → `ojd profile delete`; `map import`, `map export` → `ojd profile import|export`
  - `map enable`, `map disable` → `ojd profile activate|deactivate`
  - `map bind` → `ojd binding set`; `map unbind` → `ojd binding clear`
  - `map chord`, `map sequence`, `map layer` → `ojd profile edit`
  - `map restore-default-input`, `map clear-inputs --confirm` have no replacement; `ojd binding clear --all` removes bindings, chords, sequences, and layers, and `ojd profile edit` changes the rest
  - `map calibration` → `ojd controller calibrate`
  - `map joy-con pair|unpair` → `ojd controller pair|unpair`
  - `diagnose catalog` → the `appleGameControllerAudit` object in `ojd diagnose --bundle PATH`; `ojd record list --bundled` lists the bundled controller records
  - `permissions`, `map permission` → `ojd permission list|request`; `permissions open` has no replacement
  - `extension status|enable|disable` → `ojd extension status|activate|deactivate`
  - `app login enable|disable` → `ojd setting set launch-at-login true|false`
  - `app logs show|path` → `ojd log show|path`; `app logs open` has no replacement
  - `diagnose runtime` → `ojd diagnose [--soak SECONDS]`; `diagnose report` → `ojd diagnose --bundle PATH`
  - `diagnose usb-passive` → `./Scripts/ojd diagnose usb-passive VID PID` (contributor checkout only)
  - `update check` → `ojd update check`; `update check --open` has no replacement

### Fixed

- Stop a USB pipeline that a detach stopped before admission started it from opening a session that nothing closed.
- Accept a report descriptor that ends with zero padding after its last End Collection, as the Xbox One S Bluetooth descriptors do. The HID descriptor contract previously rejected those controllers.
- The DragonRise generic USB PCB (`0079:0006`) no longer reads its face buttons one position off or its digital L2 and R2 as View and Menu. The descriptor fallback now uses the button order shared by SDL's two mappings for this ID, with Z and Rz as the right stick. Not hardware-verified.
- `./Scripts/ojd release bump-version` (`just release-bump-version`) no longer fails looking for README version patterns that were removed, and no longer requires a dated `CHANGELOG.md` heading, so the app `Info.plist` version can be bumped at the start of a cycle. The missing heading had left beta.5 development builds reporting `0.5.0-beta.4`.
- Restore prompt controller inventory updates, cancel stale HID initialization after removal, keep suspended controllers out of compatibility identity transitions, and preserve backend failure details when an identity change rolls back.
- Show why disconnecting, resuming, or wirelessly disconnecting a controller failed in that controller's details. The failure was recorded but never displayed.
- Release a Bluetooth controller's HID claim before disconnecting it, confirm the physical link closed, and restore the prior active session when disconnection fails or times out.
- Report typed HID, Bluetooth, and disconnect-stage failures instead of reducing them to generic Boolean or unavailable results.
- Restore the authenticated GitHub fallback when raw catalog source downloads are rate limited.
- Neutralize rumble and lighting before a sleeping or stopping controller's session closes, and keep a late output request from re-enabling them.
- Roll back only the output channels a failed write changed, so one controller's rejected write no longer undoes other outputs.
- Keep the wireless-disconnect timeout on time when Swift's shared thread pool is busy.
- Cut per-report CPU in output routing: eligibility checks describe only the reporting controller instead of every connected one, runtime identity tokens are computed once per controller, and remapping tracks the foreground app from activation notifications instead of querying it for each report.
- Publish virtual controller reports only when their state changes: the 8 ms idle keepalive is gone, and input the virtual profile cannot carry no longer republishes an identical report.
- Publish the virtual controller again after wake. A controller that returned with the same identifier as before sleep stayed without a virtual controller until it was reconnected.
- Watch for controllers through a new HID manager each time controller discovery starts, so discovery after wake no longer depends on the manager that sleep stopped.
- Reset a raw USB controller's port once when its startup write reports the device as disconnected, so the host enumerates it again as a replug does. A Razer Wolverine Tournament Edition (`1532:0A15`) that stayed attached through sleep failed every startup after wake until it was replugged.
- Open each physical HID controller once: a DualShock 4 no longer delivers every report twice, and OJD no longer opens its own virtual gamepads.
- Keep DualShock 4 input live: a duplicated report could hide its sensor timestamp advance, so OJD waited for a neutral report and dropped stick input and physical output.
- Quit within a second on SIGTERM or SIGINT instead of hanging in AppKit's termination loop.
- Send the full 49-byte DualShock 3 and Sixaxis output report so player LEDs change over USB.
- Start the menu-bar app without an app bundle instead of crashing on notification setup.

## [0.5.0-beta.4] - 2026-09-15

### Added

- Decode Flydigi Vader 4 Pro over Bluetooth Low Energy (`D7D7:0041`). Face buttons, D-pad, sticks, analog triggers, bumpers, Select, Start, stick clicks, and Home map from the captured 15-byte report. C, Z, and M1–M4 stay diagnostic-only. The 2.4 GHz dongle and wired identities are out of scope.
- Map the WR-007 USB HID receiver (`11C1:5600`) through Generic HID: sparse Xbox-style buttons, Z/Rz as the right stick, and Simulation Accelerator/Brake as analog triggers. Apple GameController identity is available so `GameController.framework` consumers can see the virtual device. Physical rumble is not claimed.
- Run Ruff, Pyright, ShellCheck, swift-format, SwiftLint, Python unittest, and SwiftPM directly from Just and CI. Keep `./Scripts/ojd` for repository-specific operations.
- Add source-backed XID input and independent 16-bit motor output for cataloged original-Xbox controllers. Physical rumble remains unverified; virtual output remains Generic HID because XID is not HID.
- Add GameSir G7 Pro, Cyclone 2, and G7 Pro 8K PC input, heartbeats, extra controls, telemetry, and model-specific lighting. G7 Pro `3537:100A` and `3537:1022` stay input-only until a configuration-ready mode is hardware-verified.
- Add wired SCUF Envision Pro `2E95:434D` Generic HID input from report 6. Existing `2E95:0504` GIP behavior is unchanged.
- Add selectable DualShock 4 (`dualshock4`, `054C:09CC`), DualSense (`dualsense`, `054C:0CE6`), and Switch Pro (`switchpro`, `057E:2009`) USB HID packers and captured-layout descriptors. Switch Pro reports are padded to 64 bytes.
- Let the picker and CLI publish those first-party identities from a GIP pad for consumer testing; automatic GIP routing remains Xbox Series.
- On macOS 15+, correlate CoreHID and IOHID snapshots for `GCController.supportsHIDDevice` diagnostics, and report provisioning profiles that exclude the current Mac.

### Changed

- Consult device-level compatibility availability when exposing a virtual identity, rather than the physical-family overload alone.
- **BREAKING:** Repository automation now uses `Scripts/` and `Tools/`. `./Scripts/ojd` is the only supported script entry point; lowercase aliases were removed.
- **BREAKING:** OpenJoystickDriver JSON now has one unversioned lowerCamelCase contract. Profiles and remapping libraries reject schema-version tags and legacy snake-case names.
- Name wire families XID, XUSB, GIP, and HID; rename catalog driver `Xbox360` to `XUSB`. Automatic publishing is family-specific: XUSB uses Xbox 360, GIP uses Xbox Series, matching HID dialects use their first-party identity, and other HID or XID devices use Generic HID.
- Show the published identity's official product name, VID/PID, symbol, and glyphs throughout the UI. Consumer-bind results, report details, and evidence limits are recorded in [consumer-binding evidence](contributing/testing/consumer-binding.md), [wire protocols](contributing/development/wire-protocols.md), and the [GameSir record](contributing/testing/gamesir-family.md). Automatic GIP routing remains Xbox Series.

### Removed

- Remove standalone HID set-report, haptics-backend, and DMG-background probes, plus the undispatched build `nuke` route. Supported diagnostics remain under `./Scripts/ojd diagnose`.
- Remove repository-local source-layout, source-size, script-prose, and SwiftLint-wrapper checks, plus generic dispatcher lint, format, aggregate-check, capability-test, and Swift-test routes.

### Fixed

- Exclude Apple GameController synthetic HID nodes before opening them. This avoids creating new wedged `GamePad-1` clients; existing stuck clients still require a reboot. See [Apple controller ownership](contributing/development/apple-controller-ownership.md).
- Keep Input Monitoring across development rebuilds by signing the host with a stable team and bundle-ID requirement.
- Complete TCC Quit & Reopen through Launch Services after the old process exits. Normal Quit and SIGTERM do not relaunch the app.
- Write rumble and player-indicator packets for ZD Ultimate Legend (`413D:2104`) to interrupt OUT `0x02`. The Xbox 360 default OUT `0x01` is absent on this pad, so those writes failed with `notFound`.

## [0.5.0-beta.3] - 2026-09-04

### Added

- Install from a signed DMG with plug-and-play setup. Only macOS-owned approvals stay manual.
- Translate GUI and CLI copy for packaged locales. Keyboard destinations use SF Symbols when macOS provides them, with localized text as fallback.

### Changed

- Map extra buttons from packets. GameSir-style 32-byte GIP reports emit Share from payload byte 14. DualSense Mute stays packet-mapped.
- Hide periodic GIP announce frames from packet-capture console and Copy All. Export still includes them.
- Promote empty remapping libraries from the retired schema on load so a blank Profiles store no longer fails as unsupported.
- Persist automatic compatibility as `automatic` and resolve only catalog-backed physical modes. Unrelated or unproven identities fall back to Generic HID.
- Rename catalog and RPC `flags` to `quirks`.
- Treat ASTRO C40 `9886:0024` as SDL/PCSX2/Steam-specific. Do not recommend Xbox One Bluetooth `045E:02FD` for SDL after reported no-input results. Treat C40 PS4 `9886:0025` as research-only.

### Removed

- Remove the `xone-hid` compatibility identity. Sanitize unknown persisted identities to `automatic`.

### Fixed

- Relaunch the menu-bar extra after macOS Quit & Reopen from a permission grant.
- Stop Launch Services from re-opening the menu-bar app during install probes, which showed “The application is not open anymore” and left a blank extra.
- Start the signed app after local replace so LaunchServices `open` does not fail with -600.
- Give the DriverKit extension a legal build version. Semantic prereleases no longer ship as `500001` or `500002`.
- Replace a stale DriverKit extension and recover bounded activation failures.

## [0.5.0-beta.2] - 2026-08-27

### Added

- Manage profiles in the GUI: create, edit, import, delete, and activate, with device and application scope, binding capture, turbo, long-hold, double-tap, chords, sequences, layers, and axis tuning.

### Fixed

- Tolerate optional Xbox 360 player-1 ring LED startup output rejections.

## [0.5.0-beta.1] - 2026-08-25

### Added

- Add a native menu-bar and settings app with Overview, Controllers, Profiles, Console, and Settings, plus About, launch-at-login, and GitHub access.
- Add an application-service console with stream filtering, refresh, and copy.
- Notify on controller and active-profile events, with independent event and sound preferences.
- Use IOHID on macOS 10.15–14 and CoreHID on macOS 15+ for physical HID and virtual devices.
- Open raw USB with IOUSBHost, or USBDriverKit for interfaces owned by the restricted system extension.

### Changed

- BREAKING: Remove the daemon and relay. The app owns controller semantics, virtual output, and the local command service.
- BREAKING: Remove SwiftUSB and libusb. Raw USB uses IOUSBHost or USBDriverKit.
- Make Apple GameController the recommended default compatibility identity.
- Target consumer APIs: `sdl2-3` for SDL 2/3, `apple-gamecontroller` for `GCController`, and `generic-hid` as fallback. Fold the hardware-verified ASTRO Xbox 360 HIDAPI path into `sdl2-3` and drop `x360-hid`.
- Limit USBDriverKit to Apple's approved Microsoft GIP family: `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12`.
- Rework the menu-bar menu around Show, Refresh, Settings, connected controllers, Help, About, and Quit.

### Removed

- Remove browser diagnostics and obsolete application-service start/restart paths.
- Remove foreground-consumer HID routing, per-application virtual-device replacement, and the bundled SDL mapping file.

### Fixed

- Keep controller and profile UI updates from replacing visible state with loading placeholders.
- Stop classifying ordinary application-service startup as a console error.
- Keep Compatibility virtual gamepads stable across foreground-app changes. `sdl2-3` publishes the hardware-verified ASTRO `9886:0024` identity.
- Prevent superseded delayed rumble stops from silencing newer accepted output.
- Fix an IOUSBHost crash from resizing kernel-backed transfer buffers.
- Deduplicate wired discovery when HID and raw USB report the same device.
- Require the USB transport entitlement in DriverKit signing diagnostics.
- Let controllers such as the GameSir G7 SE select configuration 1 before the GIP interface exists.
- Accept an activated idle DriverKit extension when no entitled Microsoft device is connected.

## [0.5.0-alpha.5] - 2026-07-12

### Added

- Reach the running app from headless commands over a local authenticated RPC.
- Generate the controller catalog from pinned Linux kernel sources.

### Changed

- BREAKING: Move controller processing into the main app. Remove the embedded daemon, LaunchAgent, and XPC helper.
- Register the main app as the login item and make it the sole owner of Input Monitoring and Accessibility requests.
- Make the Compatibility virtual device the sole consumer-gamepad output.

### Fixed

- Clear the internal option flag from GIP rumble frames so Xbox One controllers accept rumble.
- Select the greatest valid GitHub tag for manual update checks.
- Report permission status from the main app instead of a helper-selection workflow.
- Leave unsupported vendor-specific USB devices unclaimed.
- Use hardware-reported endpoints for Xbox One Controller 1537 and Logitech F310 XInput.

## [0.5.0-alpha.4] - 2026-06-10

### Fixed

- Send the player-1 solid ring-of-light command on wired Xbox 360 attach instead of leaving the controller flashing.

## [0.5.0-alpha.3] - 2026-06-08

### Added

- Add Sparkle 2 updates from the notarized DMG feed.
- Add a local install that matches the packaged app.

### Changed

- Keep release builds universal and package them as Finder-styled DMGs.
- Register the daemon LaunchAgent with SMAppService on modern macOS.

### Fixed

- Launch the packaged app by adding the Sparkle runtime search path.
- Notarize embedded Sparkle helpers and XPC services.
- Request daemon Input Monitoring under the daemon identity.
- Let launchd terminate and reopen the daemon helper cleanly.
- Name the failing stage when an update check fails.

## [0.5.0-alpha.2] - 2026-06-06

### Changed

- Improve Steam Controller tester diagnostics after wired `0x28de:0x1102` showed lizard-mode keyboard input without an exact IOHID match.

## [0.5.0-alpha.1] - 2026-06-06

### Added

- Add experimental Steam Controller USB and wireless receiver support for `10462:4354` and `10462:4418`.
- Add experimental DualSense USB and Bluetooth support for `1356:3302` and `1356:3570`.
- Add experimental DualShock 3 support for `1356:616`.
- Add experimental Nintendo Switch Pro USB support for `1406:8201`.

## [0.4.1] - 2026-05-31

### Changed

- Reduce background polling while the menu-bar popover is closed.

### Fixed

- Reduce launchd health-sampling overhead.

## [0.4.0] - 2026-05-24

### Changed

- Clarify menu-bar and Input Test workflows for permissions, profiles, live input, packet log, and rumble.
- Open the popover on right-click.

### Fixed

- Neutralize virtual output when a controller disconnects or a USB input loop exits, so buttons do not stay held.

## [0.3.1] - 2026-05-24

### Fixed

- Include the expected SDL HIDAPI state packet header in Xbox 360 HID reports so LB/RB no longer stick.

## [0.3.0] - 2026-05-24

### Added

- Route Compatibility per SDL consumer so simultaneous SDL apps can share controllers.
- Gate idle controllers: neutralize forwarded state and stop keep-alives.

### Fixed

- Stop simultaneous SDL apps from hijacking each other's controller route.
- Fix a foreground-consumer misclassification that could freeze input mid-game.

## [0.2.0] - 2026-05-21

### Added

- Add SDL HIDAPI-compatible Xbox 360 rumble for SDL apps.

### Changed

- Distribute releases as a standard macOS DMG.

## [0.1.0-rc.2] - 2026-05-13

### Added

- Add DualShock 4 Bluetooth input and rumble through Sony HID report `0x11`.

## [0.1.0-rc.1] - 2026-05-13

### Added

- Add DualShock 4 USB input and rumble.
- Forward app rumble to Compatibility devices through supported Xbox One, Xbox 360, and compact rumble reports.
- Add Input Test controls for live input, packet logs, physical rumble, and button glyphs.
- Add user-space compatibility identities for SDL 2/3, Apple GameController, Generic HID, Xbox 360 HID, and Xbox One HID.

### Changed

- Keep the app menu-bar-only with a reliable status item.

### Fixed

- Show held D-pad directions in Input Test.
- Fix an output-dispatcher race when creating virtual devices.
- Keep the menu-bar app alive after launch.

[Unreleased]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.4...HEAD
[0.5.0-beta.3]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.2...0.5.0-beta.3
[0.5.0-beta.2]: https://github.com/xsyetopz/OpenJoystickDriver/compare/0.5.0-beta.1...0.5.0-beta.2
[0.5.0-beta.1]: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1
