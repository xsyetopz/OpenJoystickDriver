# Remapping Input Samples

This page defines motion, touch, extra-control, and paired-controller input. Start with the [remapping overview](remapping.md).

## Motion and Touch Sample Transport

DS4 and DualSense parsers append typed motion samples and touch frames to control events. Normalization preserves repeated samples and their relative order while retaining control-state coalescing. Snapshot control state retains the latest complete frame for each explicit surface so native capture can detect a new contact; payloads without that field decode to no touch samples. Virtual output continues to ignore sample variants.

The packet layout and touch dimensions follow [Linux hid-playstation at the reviewed revision][1]. Motion samples carry acceleration in m/s² and angular velocity in rad/s in the canonical controller frame: right-handed, +X to the controller's right, +Y away from the player along the face, +Z up through the face. Each producer applies factory calibration where available, otherwise the nominal device scale, and records which in `calibrationSource`. Timestamps retain the raw device counter, rational nanoseconds per tick, and a sequence index. Their time is receipt-anchored sensor time: the `MonotonicTimestamp` receipt time of the parser session's first sample plus the device ticks elapsed since it. DS4 uses a 16-bit counter at 16000/3 ns; DualSense uses a 32-bit counter at 1000/3 ns. Fractional remainders carry between samples. Ticks count at that nominal rate with no rate correction, so sample time can drift from the receipt time in `ControllerEvent.timestamp`. A counter decrease denotes one wrap. This assumes ordered reports; a device reset or multiple wraps during a gap cannot be distinguished from the counter alone, so a gap of a whole counter period or more (about 350 ms on DS4) is not recovered. A transport session reset (`resetProtocolState`) re-anchors time at the next report and keeps the sequence index counting, so the remapping engine sees a gap, not a reversal.

Touch frames follow the spec's contact contract. Each contact has a slot, an active flag, normalized unsigned 16-bit X and Y, and optional `UnipolarValue` pressure; no current producer reports pressure. Each frame has a surface and a `MonotonicTimestamp`.

- The slot is the contact's index in the report, as in hid-playstation's `input_mt_slot` loop. The seven-bit per-finger tracking counter is not published.
- X and Y span the whole surface. 0 is the left or top edge and 65535 the right or bottom edge on every surface. Each producer declares its raw origin and span once (`ControllerTouchGeometry`): DS4 1920x942, DualSense 1920x1080.
- Normalization clamps the raw offset to `0...span-1`, then computes `(offset * 65535 + (span - 1) / 2) / (span - 1)` in integer arithmetic, rounding half up.
- Sony raw Y already grows downward, so it is not flipped.
- Sony frames carry the report's sensor-clock time, the same `monotonic` value as its motion sample.

DS4 keeps up to three USB or four Bluetooth history frames in packet order. The raw touch counter has no time unit and is dropped, so every history frame of a report carries that report's time. A malformed history count omits touch history but keeps the valid motion data. Short DS4 control-only reports emit no synthetic sensor samples.

Focused tests cover signed decoding, counter wrap and fractional ticks, repeated sample delivery, touch history, short reports, and DualSense Bluetooth CRC rejection before sensor-clock updates. The active parser exposes `capabilities` through the connected-device payload: motion support and maximum contacts per touch frame. This describes decoding, not hardware validation. The payload requires the `capabilities` key; a payload without it fails to decode. Tests exercise both DS4 revisions, DualSense, and DualSense Edge through the device manager and the encoded payload, preserving the runtime device identifier.

Factory calibration for the supported families is applied before remapping. Other controller families do not advertise calibrated motion; physical validation remains external. Nintendo timing uses explicit estimation: [Linux hid-nintendo][2] documents that reports lack a reliable sample timestamp and contain three IMU samples. The Switch Pro parser converts all three samples in wire order to SI units in the canonical frame and requests IMU enablement (`0x40`, value `1`) during HID startup. It advertises motion decoding through the same capability contract. Short control-only reports do not advance its sensor clock.

The pipeline captures host receipt time before parsing and supplies it through the shared parser hook. Nintendo timestamps have `hostEstimate` basis, retain the raw report counter as metadata, and leave device tick units absent. Sample time is the first report's receipt time plus the estimated elapsed time, so each report's newest sample is dated up to 10 ms after its receipt. The first report uses nominal 5 ms sample spacing; subsequent spacing follows a bounded moving average of host report intervals. Backward receipt times clamp, and gaps above 30 ms preserve elapsed gaps rather than stretching three samples across the gap. This estimates rather than measures hardware sample timing. Device-counter timestamps retain their distinct `deviceCounter` basis. Tests cover both parser dispatch paths, sample order, signed values, backward receipt time, long gaps, short reports, and the IMU startup command.

[1]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-playstation.c
[2]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-nintendo.c

### Steam Controller Full-State Motion

The Steam Controller parser converts accelerometer and gyro vectors from full state messages (type `0x01`) to SI units at the nominal device scale, following the packet fields used by [SDL's Steam HID parser][3] and the layout documented in [Linux hid-steam][4]. Startup settings request raw accelerometer and gyro output with IMU mode `0x18`; shutdown retains the existing default-settings restoration. Motion is exposed in parser capabilities. Its axis mapping follows SDL; gyro and accelerometer mappings differ by a reflection, so handedness remains unverified until a hardware capture settles it.

Packet sequence numbers remain metadata. Motion timestamps use host receipt time: the first accepted motion report's receipt anchors the session, backward receipt times clamp, and there are no device tick units. An immediately repeated sequence number does not emit another motion sample. Counter wrap accepts the next report. Receiver disconnect/connect transitions and transport session resets re-anchor timing and reset duplicate tracking; reports received while disconnected do not advance motion state.

This covers full-state packets on the supported wired/receiver path. BLE chunked packets are not advertised as supported input; hardware delivery validation remains external. Tests establish decoding, nominal scaling, and lifecycle behavior, not physical accuracy or wireless firmware delivery.

[3]: https://github.com/libsdl-org/SDL/blob/634dff3725b8419902b832d1c84363da211a3596/src/joystick/hidapi/SDL_hidapi_steam.c
[4]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-steam.c

### Steam Trackpad Samples

Full state packets emit separate `left` and `right` touch surfaces, each with one contact in slot 0. The raw pad coordinates are signed 16-bit values: origin -32768, span 65536. X maps through unchanged (`raw + 32768`). Raw Y grows upward, like the stick Y that shares the right-pad fields (the driver negates it for sticks), so normalization flips it: `y = 65535 - (raw + 32768)`. The pads have no touch clock. Frames carry the receipt-anchored time of the report's motion sample, and touch is emitted only in reports that yield one. Slots are surface-local, so slot zero on two pads does not merge.

The left axis pair alternates between pad and stick when both are active. Pad packets retain the last stick value, and interleaved stick packets retain the last pad coordinates. Ending stick activity neutralizes its contribution. Releasing a pad emits an inactive contact frame. Receiver lifecycle resets clear remembered pad coordinates along with the motion clock. These rules follow the full-state interleaving logic in the reviewed SDL source above.

This path also fixes stick/pad cross-contamination; physical validation remains pending.

### Touch Mappings

Profiles identify `primary`, `left`, and `right` surfaces explicitly. Discrete sources cover the contact lifecycle, a validated 1-by-1 through 16-by-16 grid cell, and a cardinal swipe with a minimum normalized travel distance. CLI source forms are `touch:<surface>:contact`, `touch:<surface>:grid:<columns>:<rows>:<zero-based-column>:<zero-based-row>`, and `touch:<surface>:swipe:<direction>:<minimum-distance>`. Native capture detects a newly active surface and its manual assignment controls expose grid dimensions, cell coordinates, and swipe distance. Touchpad and Steam pad clicks remain distinct physical button sources; a contact never synthesizes a click.

One optional continuous mapping per surface selects relative pointer output or a left/right virtual touch stick. Pointer sensitivity is measured in logical screen points per complete surface span. A touch-stick radius is a normalized surface fraction; its radial deadzone and output are normalized to 0...1 and -1...1 respectively. Continuous mappings are configurable in the CLI and native profile editor. Touch-stick modes require virtual output policy.

Runtime state is owned by an exact controller and surface. Contact slots are never compared across those boundaries. The engine reads each normalized axis as a fraction of its own span (`value / 65535`), with no aspect correction, so it needs no surface geometry. The lowest active slot starts as the primary contact and remains primary until it ends. A new finger in the same slot with no inactive frame between is read as the same contact. Changing contact, profile, or controller session resets the pointer and stick baseline. A complete inactive frame releases contact/grid bindings and neutralizes touch stick output. Swipes fire once when their primary contact ends. Profile replacement, disconnect, permission suspension, shutdown, and failed delivery use the engine's ordinary drain path, which releases touch-owned buttons and virtual contributions. Tests cover surface and device isolation, slot identity, grid transitions, swipes, pointer reset, virtual neutralization, capture, CLI parsing, profile validation, persistence, and RPC transport.

### Steam Grips and Pad Clicks

Steam full-state packets expose left/right grip and left/right pad-click events as distinct physical controls. Schema-3 profiles accept `button:left_grip`, `button:right_grip`, `button:left_pad_click`, and `button:right_pad_click` in the CLI and native source/capture menus. They can use the existing binding behaviors, chords, sequences, and layers. New source identifiers require schema 3. The labels have first-pass translations across the current catalogs; visual, VoiceOver, and native-language review remain pending.

These are input sources, not new virtual buttons. Validation rejects them as `gamepad_button` destinations, destination menus omit them, and virtual-state construction filters them. The Steam right-pad click preserves its existing right-stick-click compatibility output when passed through without a binding. A schema-3 binding consumes that contribution.

Tests cover parser press/release edges, source persistence, key press/release output, invalid virtual destinations, capture, source menus, and catalog consistency. Physical isolation and delivery still require hardware validation.

### Independent Joy-Con Input

The canonical HID catalog selects left and right Joy-Con layouts for Nintendo `057e:2006` and `057e:2007`. Each layout ignores the absent stick and the other half's button bits, exposes its one rumble motor, and uses Nintendo's three-sample IMU path. Startup requests full input reports and enables IMU and rumble without the Pro Controller's USB handshake prefix. Both the schema and runtime decoder reject conflicting side selections.

Catalog records were generated from the locked Linux source. Constructed packet tests cover selection, side filtering, motion sample delivery, startup, and rumble isolation. See [Joy-Con validation](../testing/joy-con.md) for the exact source and hardware acceptance steps.

### Paired Joy-Con Sessions

Schema-3 profiles targeting the left Joy-Con model can opt into `joy_con_pair` and select the left, right, or no gyro. Pair profiles do not run on a standalone half. The CLI uses `ojd controller pair <left> <right> --profile <profile>` and `ojd controller unpair <pair>`; the native profile screen exposes the same exact connected-controller selection. Runtime identifiers are opaque and process-local, so pairing is an explicit in-memory session rather than persistent hardware identity.

Both halves feed one remapping state and one virtual output identity, using the left half as the session output key. Each half is diffed against its own last snapshot, so one half's report never releases a control the other half holds. Nintendo's parser normalizes left and right IMU readings into the stable combined-controller frame before the configured half reaches calibration and gyro routing. The unselected half's motion samples are discarded; buttons, the left and right sticks, and rail controls remain side-owned inputs. Existing Nintendo output reports retain per-half rumble bytes.

Disconnecting either exact member, unpairing, or starting a profile-library transaction drains the combined output, retires the virtual controller, and cancels the session. A still-connected half returns to its independent virtual-gamepad route. Reconnection requires a new explicit pair, and an old session UUID cannot unpair its replacement. Constructed routing tests cover partial availability, combined controls, gyro selection, disconnect, replacement-session isolation, and profile transaction cleanup. Bluetooth hardware acquisition, physical orientation accuracy, per-half rumble delivery, and virtual consumer recognition remain unverified.

Joy-Con rail buttons expose four schema-3 sources: `button:left_sl`, `button:left_sr`, `button:right_sl`, and `button:right_sr`. Each belongs to its physical half, including when both halves are connected. The Pro Controller layout ignores these bits. Rail sources can map to supported gamepad buttons or system actions; they have no direct virtual button identity.

### DualSense Edge Controls and Extra-Button Capabilities

The generated Edge record (`054c:0df2`) declares `paddle-left-1`, `paddle-right-1`, `auxiliary-1`, and `auxiliary-2` in `capabilities.present`, which selects the Edge layout for both registry construction and live HID discovery. Standard DualSense (`054c:0ce6`) keeps its original system-button map. Edge function buttons and paddles expose `button:left_function`, `button:right_function`, `button:left_paddle`, and `button:right_paddle` in schema-3 profiles and native capture/editor controls. They map to existing output destinations; they are not virtual button destinations.

The field masks follow the [reviewed SDL PS5 parser][5]. Constructed USB/Bluetooth reports test each source through gamepad press/release, repeated report suppression for digital edges, ordinary-model exclusion, and CRC rejection before button-state mutation. These tests do not establish Edge firmware or hardware delivery.

`capabilities.controls` lists the normalized control IDs the selected parser declares, in `ControlID` declaration order, including base gamepad controls. Sony touchpad/mute, Steam grips/pad clicks, Joy-Con rail controls, and Edge function/paddle controls use their slot IDs. A record's `capabilities.absent` removes controls (xpad trigger-as-button rows drop the analog triggers, stick-less rows drop the stick axes) and `capabilities.present` adds controls the configured parser emits. An unknown control ID or a missing key fails to decode. The list describes decoding, not physical verification or virtual output identities.

Touch surfaces are derived rather than encoded. A zero `touchContactCount` means no surface. Otherwise each declared `left-trackpad-touch` or `right-trackpad-touch` control yields its `left` or `right` surface, and a controller without trackpad-touch controls has one `primary` surface. Sony therefore exposes `primary`, Steam exposes `left` and `right`, and Nintendo exposes no touch surfaces. Raw geometry stays inside each producer; frames carry normalized coordinates. Tests compare capabilities with actual parser-produced frames and preserve the metadata through device-payload serialization.

[5]: https://github.com/libsdl-org/SDL/blob/0c8feecce6e57a7a8c1b1eb06631e0a7a56fcd8f/src/joystick/hidapi/SDL_hidapi_ps5.c
