## Context

See `proposal.md` for the reason. This change is planning only: it holds specs and tasks, no code.

Sources: WiiBrew (Wii Remote, Extension Controllers, Wiimote Extension Controller pages) is the reference for every byte below. wiiuse (GPL-3+) and wiimacmote (no license) were read for facts only, such as the macOS call pattern in wiimacmote's `WiimoteHIDController.swift` and its note that the report mode is lost after a status report. OJD moves to PolyForm Noncommercial 1.0.0 plus a commercial license (user decision, 2026-10-25), which cannot combine with GPL code, so no code or wording is copied from either; the Swift code is written independently from WiiBrew facts and captures. Every byte value in this document is a WiiBrew fact that the recorded fixtures of task 1 re-check; a fixture that disagrees wins and the document is corrected.

Constraints from the repository `CLAUDE.md`: no compatibility layer before `v1.0.0`; no hidden behavior (every behavior has a name, a test and user-facing text); generated `Controllers` are never hand-edited; docs state current behavior only.

The closest family is `NintendoSwitch1` (`Switch1Driver.swift`): Bluetooth HID, a rolling output counter, subcommands with replies, SPI reads for calibration, a description that owns the fixed requests. The Wii Remote differs in four ways: its output reports carry the rumble bit in every report, a reply arrives as a separate input report (`0x20` to `0x22`) and not as a field of the full report, the report layout of the input stream changes with a mode the host chooses, and an extension adds a second device behind the remote.

## Goals / Non-goals

Goals: one family for both product IDs; every feature of the remote that WiiBrew documents and the user named (buttons, accelerometer, extensions, Motion Plus, IR, speaker, LEDs, rumble, battery); each behavior named and tested from recorded fixtures.

Non-goals: see `proposal.md`, Out of scope.

## Decisions

### D1. One Family, `NintendoWii`, One Variant

The family has the single variant `BluetoothClassic`. Reason: no Wii Remote speaks USB. Both records select the family; `0330` differs only in revision, so the two records differ in `id` and display name and share one mode.

Alternative: extend `NintendoSwitch1`. Rejected: the report vocabulary, the memory access (`0x16`, `0x17`) and the stream-mode model share nothing with the Switch subcommand header, and `Switch1Driver` already holds three layouts.

### D2. What Is Data and What Is Swift

The description and records hold what a table can state. The split follows the code/data rule of `protocol-descriptions` ("Code keeps only algorithms") and uses the primitives of `declarative-input-layouts` where that change provides them.

Data (description `Resources/Protocols/nintendo-wii.json` and the records):

- The output report ids and lengths (`0x10` to `0x1A`) and the input report ids (`0x20` to `0x22`, `0x30` to `0x3F`).
- Each report mode `0x30` to `0x3F` as a layout: which blocks it carries (core buttons, accelerometer, IR bytes, extension bytes), their byte offsets and lengths. Conditional layouts by report id come from `declarative-input-layouts`.
- The core button bits (two bytes: D-pad, Plus, Minus, A, B, 1, 2, Home) mapped to canonical control ids, and the bit positions of the accelerometer's low bits in the button bytes.
- The Nunchuk button bits and stick/accelerometer byte positions, and the Classic Controller button bits, as extension layouts selected by extension ID (an "extension slot" of `declarative-input-layouts`).
- The extension ID table: six-byte ID to extension kind.
- The register addresses and fixed values of the handshake (`0x55` to `0xA400F0`, `0x00` to `0xA400FB`, read six bytes at `0xA400FA`; Motion Plus `0x55` to `0xA600F0`, mode byte to `0xA600FE`), the seven IR setup steps with their sensitivity blocks, the speaker setup writes and the report ids they use. A handshake or setup is a list of register writes and reads in the description's `requests` section, as `nintendo-switch1.json` holds its fixed requests; this change adds the Wii entries to `protocol-description.schema.json`. The order, the waits and the reply checks stay in `WiiDriver`, because `declarative-input-layouts` leaves scripts and extension slots out of scope. The Wii description gives the 50 ms IR spacing and the reply timeouts as typed tuning keys.
- The player-indicator bit of each LED (`0x11`, bits 4 to 7), the rumble bit position (bit 0 of the first data byte of each output report), the report-mode choice table (which features need which mode).
- Names of the user-facing failure codes (D9).

Swift (the driver):

- The state machine that sequences the handshake, tracks the extension kind, chooses the report mode and re-sends it (D4).
- Reassembly of memory replies (`0x21` carries up to 16 bytes with a size field and an error nibble) and acknowledgement matching (`0x22`).
- Split bit fields where a layout primitive lacks them: the Classic Controller's right stick and triggers span byte boundaries. If `declarative-input-layouts` has no split field, the Classic decode stays in Swift and task 6.3 lists it.
- Accelerometer and Nunchuk calibration (zero and gravity from EEPROM `0x0016` and from the extension at `0xA40020`), applied as math on the raw 10-bit and 8-bit values.
- Motion Plus: slow/fast scale flag per axis, calibration at rest, and demultiplexing of passthrough frames, which alternate gyro and extension data.
- Interleaved report modes `0x3E` and `0x3F` (36 IR bytes split over two reports).
- IR parsing and pointer math: points to touch contacts, midpoint of the two points the sensor bar makes, roll compensation with the accelerometer.
- The speaker path: Yamaha ADPCM encoding (step and index tables and the encoder state), resampling to the speaker rate, packetizing into 20-byte `0x18` reports, pacing.
- Rumble state carried into every output report.

Reason for the cut: a table can state a fixed byte at a fixed address; it cannot state a decision that depends on a reply, a calibration that depends on data read from the device, or a codec.

### D3. Matching: By Product String, Because the Product IDs Are Shared

`057E:0306` is also the Wii Balance Board and `057E:0330` is also the Wii U Pro Controller. A record mode therefore declares a product-string match key (`Nintendo RVL-CNT-01` for `0306`, `Nintendo RVL-CNT-01-TR` for `0330`; the strings are WiiBrew facts that Hardware Check 1 confirms). A device with the shared VID:PID and any other product string matches no mode of these records. These records have no `default` mode, so the device is unsupported with the reason `NoModeMatched` and receives no traffic. This uses the `device-matching` requirement on match keys (interface signature, strings) and adds no new probe.

Risk: a clone or a firmware that reports another string is unsupported until a patch adds a mode. That is a visible no-match, not a fallback.

### D4. Report Mode: Choose by Feature, Set with `0x12`, Restore after Every Status Report

The driver chooses the smallest report mode that carries the enabled features (core only: `0x30`; with accelerometer: `0x31`; with IR in the extended format: `0x33`; with extension bytes: `0x32`, `0x34`, `0x35`, `0x36`, `0x37`, `0x3D` or `0x3E`/`0x3F` by the table in the description), and sends it with `0x12`. Bit 2 of `0x12` (continuous reporting) is set whenever the mode carries accelerometer, IR or extension data, because the remote otherwise reports only on a button change.

A status report (`0x20`) arrives after a status request, after an extension is plugged in or out, and after some writes; the remote then resets its report mode to `0x30`. The driver sends `0x12` again with the chosen mode on every `0x20` (behavior name `ReportModeRestore`). Source: WiiBrew and the wiimacmote notes. The restore is not a retry: it follows an observed status report and nothing else.

Alternative: pin mode `0x31` always. Rejected: IR and extension data need other modes, and the user asked for the full range `0x30` to `0x3F`.

### D5. Extension Detection and Hot-Plug

On connect the driver sends a status request (`0x15`). Bit 1 of the status flags says an extension is connected. The driver then runs the handshake: write `0x55` to `0xA400F0`, wait for the acknowledgement, write `0x00` to `0xA400FB`, wait, read six bytes at `0xA400FA`, look the ID up in the table. The handshake disables extension data encryption, so reports carry plain bytes.

Extension kinds: Nunchuk, Classic Controller, Classic Controller Pro, Motion Plus (inactive), Motion Plus with Nunchuk passthrough, Motion Plus with Classic passthrough, and `Unknown(id)`. An unknown ID is shown to the user as the six bytes in hex; the driver decodes only the core buttons and accelerometer then.

Hot-plug: every status report is compared with the previous extension flag. Plug-in starts the handshake; removal drops the extension controls (their state returns to neutral, not to the last value) and, for Motion Plus passthrough, the gyro stays active only while the Motion Plus is attached. Behavior names: `ExtensionHandshake`, `ExtensionRemoved`, `UnknownExtension`.

A handshake step whose acknowledgement carries an error code, or whose reply does not arrive within the typed timeout, ends the handshake with the named failure `ExtensionHandshakeFailed` (user text: the extension could not be read, with the step and error). There is no silent retry. The user can unplug and replug, which starts a handshake again, or run `ojd controller show` to see the state.

### D6. Motion Plus

Motion Plus sits at I2C address `0xA6`. The driver initializes it with `0x55` to `0xA600F0`, then writes the mode to `0xA600FE` (Motion Plus alone, Nunchuk passthrough or Classic passthrough, by the extension that was present). An inactive Motion Plus answers the ID read at `0xA600FA` (`00 00 A6 20 00 05`), not at `0xA400FA`; after activation the ID read at `0xA400FA` identifies the passthrough combination. Gyro samples are 14-bit per axis with a slow/fast flag per axis; the driver scales by the flag and subtracts a rest offset measured while the remote reports a still accelerometer (behavior `GyroRestOffset`, with a documented window and a user-visible state while it is measured).

Motion is exposed through the existing `motion` capability (accelerometer and gyroscope samples). The same sample type as `Switch1Driver`'s motion output is used; units are documented in the wiki.

### D7. IR Camera, Touch Contacts and the Pointer

Vocabulary today (`Resources/Schemas/vocabulary.schema.json`) has gamepad buttons, stick and trigger axes, paddles, auxiliaries, and the stick/trackpad touch and click ids. It has no pointer. Touch frames exist in Swift as `ControllerCapabilities.touchContactCount` (used by the DualShock 4, DualSense and Steam drivers).

Decision:

- The IR camera's points (up to four, 1024 by 768 raw) are exposed as touch contacts: `touchContactCount` is 4 while IR is on, 0 otherwise. This reuses the touch pipeline and needs no new id.
- Three new control ids carry the derived pointer: `PointerX` and `PointerY` (axes, -1 to 1, Y positive down, as the vocabulary rule for axes) and `PointerTracking` (digital, true while the driver computes a pointer from two visible points). They are added to `vocabulary.schema.json`, the Swift `Control` enum, the crosswalk generator (no W3C, SDL, evdev or Apple equivalent: the crosswalk marks them as none) and the profile sources, so a profile can send `PointerX`/`PointerY` to `MouseMovement`.
- The pointer is raw geometry: the midpoint of the two brightest points, mirrored because the camera sees the bar from the front, and rotated by the roll the accelerometer gives. It has no smoothing and no screen calibration; both belong to the profile layer. When fewer than two points are visible, `PointerTracking` is false and `PointerX`/`PointerY` hold their last value (documented; not hidden, and tested).
- The virtual personas carry no pointer. `SDLCompatible` and `Generic` publish gamepad controls only; the pointer reaches profiles and the endpoint. The wiki says so.

IR setup is the WiiBrew seven-step sequence: enable the IR camera pixel clock (`0x13`), enable the IR logic (`0x1A`), write `0x08` to `0xB00030`, write the sensitivity block 1 to `0xB00000`, write sensitivity block 2 to `0xB0001A`, write the mode (basic, extended or full) to `0xB00033`, write `0x08` to `0xB00030` again. At least 50 ms separate consecutive writes (WiiBrew). The spacing is a tuning key `irWriteIntervalMs` (default 50, minimum 50, a lower value is rejected), and the driver waits the full interval after each write even when the acknowledgement arrives sooner (behavior `IRSetupSpacing`). Sensitivity levels are description data.

IR needs the extended format (12 bytes) in report mode `0x33` or the basic format (10 bytes) in `0x36` and `0x37`; the choice follows the report-mode table of D4. The driver asks for the basic format by default, and the table has the row `Accelerometer` + `IRBasic` for `0x37` so the basic format runs without an extension. Alternative: always full mode. Rejected: it needs the interleaved `0x3E`/`0x3F` pair and halves the update rate.

### D8. Speaker as an Output

The speaker is an output capability, not a control. `PhysicalControllerOutputCapabilities` gains a speaker capability (a value that states 4-bit Yamaha ADPCM at the remote's rate). The driver sequence from WiiBrew: enable the speaker (`0x14`), mute (`0x19`), write `0x01` to `0xA20009`, `0x08` to `0xA20001`, the seven configuration bytes (format, rate divisor, volume) to `0xA20001`, `0x01` to `0xA20008`, unmute, then stream 20-byte data packets in `0x18` reports at the rate the configuration gives. Stopping mutes and disables the speaker (`0x19`, `0x14`). The setup writes and bytes are description data; the encoder, resampler and pacing are Swift.

User surface: `ojd controller speaker play CONTROLLER FILE` (mono or stereo PCM WAV, mixed down and resampled to the speaker rate; any other file is refused with a named error), `ojd controller speaker stop CONTROLLER`, and `--volume 0..1`. Clip length is bounded (tuning key `speakerMaxSeconds`, reason: the 4-bit codec at this rate has low fidelity and the stream holds the output queue). The speaker also needs the rumble bit preserved in each `0x18`, `0x19`, `0x14` report (D10).

Alternative: expose as an SDK endpoint output. Deferred (Out of scope); the endpoint owner adds a message once the CLI path has a hardware check.

### D9. Every Behavior Is Named, Tested and Has User Text

| Behavior name | Test (fixture-driven unless noted) | User-facing text |
| --- | --- | --- |
| `ReportModeSelect` | feature set to mode, all 16 modes | `ojd controller show`: current mode |
| `ReportModeRestore` | status report triggers one `0x12` with the chosen mode | none (not a visible state); wiki "how it works" paragraph |
| `RumbleBitCarry` | every output report carries the current rumble bit | `ojd controller rumble` result |
| `PlayerIndicator` | LED report from the player slot | wiki |
| `BatteryReport` | status byte 6 to percent, low flag | controller detail battery |
| `ExtensionHandshake` | handshake script against fixture replies | `ojd controller show`: extension kind |
| `ExtensionRemoved` | unplug returns extension controls to neutral | same |
| `UnknownExtension` | unknown ID yields kind `Unknown` with the ID | `ojd controller show` prints the ID |
| `ExtensionHandshakeFailed` | error nibble or timeout | error code and localized text |
| `MotionPlusActivate` | mode byte per extension | `ojd controller show` |
| `GyroRestOffset` | still-sample window | `ojd controller show`: calibrating / ready |
| `IRSetupSpacing` | writes at least 50 ms apart (injected clock) | wiki |
| `IRPointerLost` | fewer than two points | `PointerTracking` false; wiki |
| `SpeakerStream` | encoded bytes against a reference ADPCM vector | `ojd controller speaker` output |
| `SpeakerUnavailable` | speaker command on a record without the capability | error code |
| `DisconnectNotice` | no power-off report | wiki: disconnect in macOS Bluetooth |

Where the rows are shown: the `ojd controller show` rows (Report mode, Extension, Motion Plus, with `wiiRemote` in `--json`) and the matching rows of the Controllers detail come from `WiiRemoteStatus` in `ControllerConnectionState`, filled by `WiiDriver.wiiRemoteStatus`. Their texts are `cli.controller.show.labelReportMode`, `labelExtension` and `labelMotionPlus`, the extension names `term.wiiExtension.*`, and `status.wiiExtensionUnknown`, `status.motionPlusOff`, `status.gyroCalibrating` and `status.gyroReady`. Battery, rumble result and error texts reuse the generic `ojd controller show`, `ojd controller rumble` and `error.E2038` to `error.E2040` texts; `ojd controller speaker` texts belong to task 5.5.

Error codes go in `Resources/ErrorCodes.json`; run `./Scripts/ojd errors regenerate --write`. Localized strings follow `LOCALIZATION.md` (Meaning, Punctuation) and are reviewed, not only run through `LocalizationTests`.

### D10. the Rumble Bit Rides on Every Output Report

Bit 0 of the first data byte of every output report (`0x11`, `0x12`, `0x13`, `0x14`, `0x15`, `0x16`, `0x17`, `0x18`, `0x19`, `0x1A`) drives rumble. A report that is not a rumble command must still carry the current rumble state, or it silences or starts the motor. The driver therefore keeps the rumble state and ORs it into each report it builds (`RumbleBitCarry`). `0x10` carries only the rumble bit. The remote has one motor, binary: it is a binary rumble motor in `PhysicalControllerOutputCapabilities`, and any intensity above zero means on. Rumble resend is not needed.

### D11. macOS Transport

Pairing happens in macOS Bluetooth settings; OJD does not pair. After pairing, pressing any button reconnects the remote (the remote initiates). The driver opens the remote as an `IOHIDDevice` with the existing HID backend and sends reports with `IOHIDDeviceSetReport` (report type Output, report id as byte 0, the layout the existing Nintendo HID path uses). There is no public power-off report, so OJD offers none; the user disconnects in macOS Bluetooth or lets the remote time out.

Reads of memory (`0x17`) arrive as `0x21` reports on the same input stream. The driver matches a reply to its request by address; it has at most one outstanding read.

### D13. Shape of the Extension Layout and the Tuning Keys

`extensions[].layout` is set for `Nunchuk`, `ClassicController` and `ClassicControllerPro`; the Motion Plus kinds have none, because `WiiDriver` decodes them (D6). The layout reads the six data bytes (the `data format 0x01` of the Classic Controller; the driver disables encryption in the handshake).

- A value is a field of one to three parts, most significant part first. A part is `{byte, mask}` with a contiguous mask; the shift and width follow from the mask. The Classic Controller's 5-bit right stick X is three parts (bits 7-6 of byte 0, bits 7-6 of byte 1, bit 7 of byte 2), its 5-bit left trigger two.
- `buttons` are `{control, byte, mask, pressedWhen}` with `pressedWhen` `Set` or `Clear` (both extensions clear the bit while a button is down). The digital full-press bits of the Classic L and R triggers are left out: the analog triggers carry the same information. The Nunchuk C maps to `LeftShoulder` and Z to `LeftTrigger`; the Classic ZL and ZR map to `LeftShoulder` and `RightShoulder`, and its `a`, `b`, `x`, `y` to `East`, `South`, `North`, `West`.
- `sticks` are `{control, parts, halfRange}`; `triggers` are `{control, parts}` and run from 0 to `2^bits - 1`; `accelerometer` has `x`, `y`, `z` fields of up to 10 bits (Nunchuk).
- `stickCenter` is `FirstSample` exactly when `sticks` is set: the first sample after the handshake is the center and `halfRange` is the fixed half-range per kind (128 for the Nunchuk, 32 for the Classic left stick, 16 for its right stick). This is `ExtensionCenterFromFirstSample` of the Open item below, taken as proposed.
- No two fields share a bit and no control appears twice in a layout; the description rejects both.

The tuning keys `irWriteIntervalMs` (50 to 1000), `speakerMaxSeconds` (1 to 60) and `replyTimeoutMs` (10 to 10000) are record and patch tuning keys, read through `tuningKeys` and `defaults.tuning` of the description like the other families' keys; `ControllerTuning` holds them and the controller, controller-patch and cli-output schemas list them.

### D12. Sources and Licenses

All driver, description and test code is written independently from WiiBrew facts and recorded captures. wiiuse (GPL-3+) and wiimacmote (no license) are facts-only references: a register address, a byte value or a documented behavior may be taken from them; no code, structure, comment or wording is. Reason: the project license is PolyForm Noncommercial 1.0.0 plus a separate commercial license, which cannot include GPL code, and an unlicensed source grants no right to copy. Fixture headers name WiiBrew or the hardware capture as the source.

## Risks / Trade-Offs

- Pairing. Recent macOS versions have asked for a PIN or refused remotes that the older ones pair with (the DS3 case in `platform-neutral-redesign` shows the pattern). Hardware Check 2 records which macOS versions pair a remote and by which path (1+2 or the red SYNC button). If macOS refuses, OJD reports the OS reason in the wiki and does not work around it.
- Sleep. The remote disconnects after a period of inactivity and when the Mac sleeps; on wake it reconnects only when a button is pressed. The driver treats a disconnect as a session end (state to neutral, speaker and IR state dropped) and a reconnect as a new session with the full startup. Report mode, IR and speaker setup do not survive a power cycle, so nothing is restored from memory (no hidden persistence).
- Extension hot-plug. A plug-in during an IR setup or a speaker stream interleaves a status report with the script. The state machine finishes the current step, then handles the status; a conflicting setup is aborted with `ExtensionHandshakeFailed` or its own named failure. Fixtures for interleaved cases are recorded in Hardware Check 4.
- Memory writes while rumbling. A `0x16` carries the rumble bit; a missed `RumbleBitCarry` would make the motor twitch during setup. The test iterates every output builder.
- Calibration reads can fail or return zeros on clones. The driver reports uncalibrated accelerometer data as uncalibrated (documented) and never invents a default.
- IR sensitivity levels vary by remote batch. The level is a tuning key; the description carries the WiiBrew levels and Hardware Check 5 records which one works.
- Third-party remotes (Wii Remote clones with the same VID:PID and product string) may fail the handshake or speaker setup. They show the named failure.
- `declarative-input-layouts` is in draft. If a primitive named here is not in that change, the part stays in Swift and task 6 lists it. This change does not extend that change.
- Product-string matching depends on the HID Product string of the remote; it is readable without pairing quirks, but Hardware Check 1 confirms.

## Open Questions

- Whether the Wii U Pro Controller, which shares `057E:0330` and the same report family, should be a mode of these records. Left out; decided after Hardware Check 7.
- Whether the speaker belongs in the SDK endpoint; asked to the endpoint owner after Hardware Check 6.

## Open

Each item blocks the task named; the proposal is for the maintainer to accept or change.

- Extension calibration source (task 4.6). WiiBrew documents no layout for a calibration block at `0xA40020`: the Nunchuk page states the mechanism is unknown, and the Classic Controller page says Nintendo games take the stick centers at power-up or insertion. Proposed: the driver takes each stick's center from the first sample after the handshake and uses a fixed half-range per extension kind (Nunchuk stick 0 to 255 about 128; Classic left stick 6 bits, right stick 5 bits), as `ExtensionCenterFromFirstSample`. Hardware Check 4 records the real `0xA40020` bytes; if they hold a calibration block, a later change reads it.
- Motion Plus activation (task 4.7). D6 says how Motion Plus is activated but not when. Implemented: the handshake's ID read names an inactive Motion Plus (`00 00 A6 20 00 05`, the description's `MotionPlusInactive` row), the driver runs the `motionPlus` script with the mode byte of the Nunchuk or Classic kind the handshake last identified (`standalone` when none), then reads the ID again without the handshake writes, because `0x55` to `0xA400F0` switches Motion Plus off. WiiBrew says activation can raise a status report that shows the extension removed and plugged; the driver then reads the ID only while the activation stands. Hardware Check records the real status sequence. The tuning key `motionPlusActivation` is not implemented; the gyro rests on a window of 64 still frames (accelerometer axes within 4 units of the previous frame, no fast flag), and `ojd controller show` wiring of `isGyroRestReady` is open.
- Speaker command path (task 5.5). `ojd controller speaker play|stop` needs a service message and an endpoint command that the existing output commands do not have. Proposed: a `ControllerSpeakerCommand` carried over the same endpoint path as rumble commands, with the WAV decode in the CLI and the encoded stream in the driver; the SDK endpoint question stays open as written above.
- IR path (tasks 5.2, 5.3, 5.6). The setup runs after the calibration read of each session, one step per 50 ms (`irWriteIntervalMs`) measured from the previous write, driven by the timestamps of parsed reports; it needs the continuous reports the IR modes set. Points are decoded only after the seventh step is acknowledged. The capabilities are fixed at driver creation, so `touchContactCount` is 4 when the driver requests IR and 0 otherwise, not "while IR is on"; the contacts travel in the event's touch frames. `ControllerState.pointer` carries `PointerX` and `PointerY`, and the engine reads them as the axis sources `PointerX` and `PointerY`; they are sources only, and a `GamepadAxis` destination for them is rejected. The pointer signs (a point reflection of the camera image, the roll direction) follow D7 and are assumptions that Hardware Check 5 confirms. The driver requests the basic format at creation (`irFormat`, `irBasic` by default), so every session runs the setup. The extended and full formats work only without a known extension, because the report-mode table has no row that joins them with one.
