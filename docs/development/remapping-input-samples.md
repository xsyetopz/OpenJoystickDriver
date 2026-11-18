# Remapping Input Samples

See the [remapping overview](remapping.md).

## Motion and Touch Sample Transport

DS4 and DualSense parsers append motion samples and touch frames to control events. Snapshots keep the latest complete frame per surface. Virtual output ignores samples.

Layouts follow [Linux hid-playstation][1]. Motion samples use m/s² and rad/s in the canonical frame: right-handed, +X right, +Y away from the player, +Z up through the face. Producers use factory calibration if available, else the nominal scale, and record which in `calibrationSource`.

Timestamps keep the raw device counter, rational nanoseconds per tick, and a sequence index. Sample time is the session's first `MonotonicTimestamp` plus elapsed device ticks.

- DS4 uses a 16-bit counter at 16000/3 ns. DualSense uses a 32-bit counter at 1000/3 ns. Remainders carry between samples.
- Ticks use the nominal rate, so sample time can drift from `ControllerEvent.timestamp`.
- A counter decrease means one wrap. A reset or a gap of a full counter period or more (about 350 ms on DS4) is not recovered.
- `resetProtocolState` re-anchors time at the next report and keeps the sequence index counting.

A touch contact has a slot, an active flag, normalized unsigned 16-bit X and Y, and optional `UnipolarValue` pressure (no producer reports it). A frame has a surface and timestamp.

- The slot is the contact's report index. The tracking counter is not published.
- 0 is the left or top edge, 65535 the right or bottom edge. Producers declare raw origin and span in `ControllerTouchGeometry`: DS4 1920x942, DualSense 1920x1080.
- Normalization clamps the raw offset to `0...span-1`, then computes `(offset * 65535 + (span - 1) / 2) / (span - 1)` in integers.
- Sony raw Y grows downward and is not flipped. Sony frames carry the report's sensor-clock time.
- DS4 keeps up to three USB or four Bluetooth history frames in packet order, each with the report's time.
- A malformed DS4 history count omits touch history, keeping motion. Short DS4 control-only reports emit no samples.

The connected-device payload exposes the parser's `capabilities` (motion support, maximum contacts per touch frame); a payload without that key fails to decode. Capabilities describe decoding, not hardware validation. Other families advertise no calibrated motion.

Nintendo timing is estimated: [Linux hid-nintendo][2] documents three IMU samples per report and no reliable timestamp. The Switch Pro parser converts all three in wire order to SI units in the canonical frame. At HID startup it requests IMU enablement (`0x40`, value `1`). Short control-only reports do not advance its sensor clock. Timestamps use the `hostEstimate` basis (device counters use `deviceCounter`) and keep the raw report counter as metadata.

- Sample time is the first report's receipt time plus estimated elapsed time; the newest sample in a report is dated up to 10 ms after receipt.
- The first report uses 5 ms spacing. Later spacing is a bounded moving average of host report intervals.
- Backward receipt times clamp; gaps above 30 ms keep the elapsed gap.

[1]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-playstation.c
[2]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-nintendo.c

### Steam Controller Full-State Motion

The parser converts accelerometer and gyro vectors from full state messages (type 0x01) to SI units at the nominal scale, following [SDL's Steam HID parser][3] and [Linux hid-steam][4]. Startup requests raw output with IMU mode 0x18; shutdown restores defaults.

- Axis mapping follows SDL. Gyro and accelerometer mappings differ by a reflection; handedness is unverified until a hardware capture.
- Sequence numbers are metadata. Timestamps use host receipt time: the first accepted motion report anchors the session; backward receipt times clamp.
- A repeated sequence number emits no second sample. Counter wrap accepts the next report.
- Receiver connect, disconnect, and session resets re-anchor timing and reset duplicate tracking. Reports while disconnected do not advance motion.
- BLE chunked packets are not supported.

Not verified: physical accuracy, wireless firmware delivery.

[3]: https://github.com/libsdl-org/SDL/blob/634dff3725b8419902b832d1c84363da211a3596/src/joystick/hidapi/SDL_hidapi_steam.c
[4]: https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-steam.c

### Steam Trackpad Samples

Full state packets emit left and right touch surfaces, each with one contact in slot 0. Raw coordinates are signed 16-bit (origin -32768, span 65536). X is `raw + 32768`. Raw Y grows upward, so Y is `65535 - (raw + 32768)`.

The pads have no touch clock: frames carry the report's motion sample time, and touch is emitted only in reports that yield one. The left axis pair alternates between pad and stick, per the SDL source.

- Pad packets keep the last stick value; stick packets keep the last pad coordinates.
- Ending stick activity neutralizes its contribution. Releasing a pad emits an inactive contact frame.
- Receiver lifecycle resets clear remembered pad coordinates and the motion clock.

Physical validation is open.

### Touch Mappings

Profiles name Primary, Left, and Right surfaces. Discrete sources: contact, a grid cell (1x1 through 16x16), and a cardinal swipe with a minimum normalized distance. CLI forms:

- `touch:<surface>:contact`
- `touch:<surface>:grid:<columns>:<rows>:<zero-based-column>:<zero-based-row>`
- `touch:<surface>:swipe:<direction>:<minimum-distance>`

Pad clicks are distinct button sources. A contact never synthesizes a click.

Each surface takes one optional continuous mapping: relative pointer or a left or right virtual touch stick. Pointer sensitivity is in logical screen points per full surface span. Touch-stick radius is a normalized surface fraction, radial deadzone 0...1, output -1...1. Touch-stick modes need virtual output policy. Axes are `value / 65535` with no aspect correction. State is per controller and surface.

- The lowest active slot is the primary contact until it ends. Same slot with no inactive frame between is the same contact.
- A new contact, profile, or controller session resets the pointer and stick baseline.
- An inactive frame releases contact and grid bindings and neutralizes touch stick output.
- Swipes fire once when the primary contact ends.
- Profile replacement, disconnect, permission suspension, shutdown, and failed delivery drain the engine, releasing touch-owned buttons and virtual contributions.

### Steam Grips and Pad Clicks

Steam full-state packets expose grips and pad clicks as controls: `button:left-paddle2`, `button:right-paddle2`, `button:left-trackpad-click`, `button:right-trackpad-click`. They support every binding behavior, chord, sequence, and layer. Label translations are drafts; visual, VoiceOver, and native-language review are open.

They are input sources, not virtual buttons: validation rejects them as `GamepadButton` destinations, and destination menus and virtual state omit them.

- On the classic Steam Controller the right pad is the right stick, so an unbound right-pad click passes through as the right stick click. A binding consumes it.
- The Steam Deck and Steam Triton have a real right stick click, so their right-pad click reaches no virtual controller.

Hardware validation open.

### Independent Joy-Con Input

The HID catalog selects left and right Joy-Con layouts for Nintendo 057e:2006 and 057e:2007. Each layout ignores the absent stick and the other half's button bits, exposes one rumble motor, and uses the three-sample IMU path. Startup requests full input reports and enables IMU and rumble, without the Pro Controller's USB handshake prefix. Schema and runtime decoder reject conflicting side selections. Acceptance steps: [Joy-Con validation](../testing/joy-con.md).

### Paired Joy-Con Sessions

Profiles for the left Joy-Con model can opt into `joyConPair` and select the left, right, or no gyro. It does not run on a single half. Use `ojd controller pair <left> <right> --profile <profile>` and `ojd controller unpair <pair>`; the native profile screen offers the same selection. Pairing is an in-memory session. Opaque session tokens end when a controller disconnects.

Both halves feed one remapping state and one virtual output identity, keyed by the left half.

- Each half is diffed against its own last snapshot, so one half never releases the other's control.
- The parser normalizes both IMUs into the combined frame before calibration and gyro routing, and discards the unselected half's motion.
- Buttons, sticks, and rail controls stay side-owned. Output reports keep per-half rumble bytes.

A member disconnect, an unpair, or a profile-library transaction drains the combined output, retires the virtual controller, and cancels the session. A still-connected half returns to its own virtual-gamepad route; after a reconnect, pair again. An old session UUID cannot unpair its replacement. Not verified: Bluetooth acquisition, orientation accuracy, per-half rumble delivery, virtual consumer recognition.

Joy-Con rail buttons are `button:auxiliary3` through `button:auxiliary6`, each owned by its physical half. The Pro Controller layout ignores these bits. Rail sources map to gamepad buttons or system actions, not to virtual button identities.

### DualSense Edge Controls and Extra-Button Capabilities

The generated Edge record (054c:0df2) declares `LeftPaddle1`, `RightPaddle1`, `Auxiliary1`, and `Auxiliary2` in `capabilities.present`, which selects the Edge layout. Standard DualSense (054c:0ce6) uses the standard map. Profiles name the Edge buttons `button:auxiliary1`, `button:auxiliary2`, `button:left-paddle1`, `button:right-paddle1`. They map to existing output destinations.

Field masks follow [SDL's PS5 parser][5]. Edge hardware delivery is not verified.

`capabilities.controls` lists the parser's declared control IDs in `Control` declaration order, including base gamepad controls. Sony touchpad and mute, Steam grips and pad clicks, Joy-Con rail, and Edge controls use their slot IDs.

- `capabilities.absent` removes controls: xpad trigger-as-button rows drop analog triggers, stick-less rows drop stick axes.
- `capabilities.present` adds controls the parser emits.
- An unknown control ID or a missing key fails to decode.

Touch surfaces are derived. A zero `touchContactCount` means no surface. Each declared `LeftTrackpadTouch` or `RightTrackpadTouch` control yields a left or right surface; otherwise there is one primary surface. Sony exposes primary, Steam left and right, Nintendo none.

[5]: https://github.com/libsdl-org/SDL/blob/0c8feecce6e57a7a8c1b1eb06631e0a7a56fcd8f/src/joystick/hidapi/SDL_hidapi_ps5.c
