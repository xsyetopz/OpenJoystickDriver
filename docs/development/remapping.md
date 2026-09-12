# Remapping

## Beta.4 design

Advanced remapping extends the existing OJD profile library, deterministic Kit engine, app output
router, and profile editor. The software scope below is implemented. This document does not claim
that external runtime or hardware validation has passed.

The intended path is physical input, normalization, remapping, then virtual-controller and/or
keyboard, pointer, and scroll output. OJD owns the complete session. There is no JSM process,
JSM configuration interpreter, SDL dependency, or third-party state-injection endpoint.

| Capability | Existing foundation | Extension |
| --- | --- | --- |
| Output | Exclusive selection of compatibility or system-event remapping | Mixed output, virtual destinations, per-control consumption and passthrough |
| Bindings | Long hold, double tap, turbo, sequences | Separate activation actions, toggles, pulses, explicit release, multiple actions |
| Combinations | Simultaneous active-source chords and layers | Timed combinations, modifier chords, buffered consumption, binding and tuning overrides |
| Physical input | Buttons, D-pad, sticks, triggers | Timestamped motion, touch contacts, distinct extra buttons |
| Motion | No normalized motion event | Calibration, fusion, coordinate spaces, gyro mouse/stick, supported virtual motion |
| Stick and trigger processing | Scalar deadzone, gain, inversion, curves, digital threshold | Aim, flick, hybrid, area/ring, scroll, steering, lean, dual-stage triggers |
| Touch | Touchpad click button | Touch/click, grids, pointer, touch sticks, swipe directions |
| Multiple controllers | Exact runtime device identity | Explicit paired Joy-Con sessions and gyro selection |
| Physical output | Protocol-owned rumble and indicator capabilities | Mapping actions and channel ownership, supported adaptive-trigger effects |
| Authoring | Shared profiles, authenticated RPC, native CLI and editor | Native UI and CLI coverage for every supported capability |

Mapped controls replace their original virtual contribution unless passthrough is explicitly
selected. Current system-event profiles retain their behavior. Profile and layer transitions,
disconnect, permission loss, suspension, and shutdown release owned output and cancel scheduled
actions. A failed mapping must not silently restore consumed input.

Filtering OJD's virtual reports does not hide the physical controller from another application.
Isolation-dependent profiles require exclusive physical ownership, with acquisition failure
reported separately from permissions and virtual publication. CoreHID ownership must be acquired
before monitoring or report requests; destroying the owning client releases it. The older IOKit
backend uses its existing device-seizure mechanism. See Apple's
[seizeDevice contract](https://developer.apple.com/documentation/corehid/hiddeviceclient/seizedevice()).

## Native action collections

Only schema 3 profiles are accepted. The decoder rejects any other version immediately, before
decoding profile fields; OJD does not migrate, reinterpret, or reset older profiles. Schema 3
assignments retain their primary destination and can contain an ordered
`additional_actions` array. Each additional action has its own UUID, destination, behavior,
and optional turbo, long-hold, double-tap, or pulse settings. Action IDs share the profile-wide
uniqueness requirement. Additional actions count toward the 512-item mapping limit. Continuous
actions use the assignment's axis tuning. Permission requirements include every action and its
alternate destinations, including actions in inactive layers.

The assignment behavior sheet supports adding, removing, reordering, and editing additional
actions. CLI `bind` and `layer bind` accept `--actions-json <JSON-array>` in the native action
format. An omitted option preserves the collection; `[]` removes all additional actions.
Nested CLI commands put the operation before the profile, for example
`map layer bind <profile> --layer <uuid> --source button:south --target key:a`.

The implemented behavior values are:

- `hold`: follow the physical control's press and release.
- `toggle`: alternate the owned output between pressed and released on each new press.
- `tap_on_press` and `tap_on_release`: emit a press/release pair on the selected edge.
  A release tap requires a matching press and is canceled when its assignment loses ownership.
- `pulse`: press for `pulse_duration_ms` (1...5000 ms, default 100). Physical release does not
  shorten the pulse. A new press extends the same action's deadline.
- `press`: press until an explicit release or lifecycle cleanup.
- `release`: release matching held destinations owned by the same controller and cancel their
  pulse/turbo timers. Contributions from other controllers remain owned by those controllers.

Collections dispatch in profile order. Independent actions retain separate activation timers;
shared keyboard/modifier outputs use reference counts, and virtual contributions use the
gamepad aggregator. The sections below define the corresponding combination, motion, touch, and
paired-controller behavior.

## Reference sources

The behavioral reference is
[JoyShockMapper at bb69784488937e0a5e21988b966eccd9f04d504e](https://github.com/Electronicks/JoyShockMapper/tree/bb69784488937e0a5e21988b966eccd9f04d504e)
and the contributor's `JoyShockMapper-macos.zip`, SHA-256
`5f56191598774fa907f1b22aacc85bf46967a6159ed1b1933de258c2d816fb33`.

Comparing the archive's source with that revision shows platform/build adaptations: macOS input
posting, window/tray integration, platform definitions, build configuration, an additional C++
include, and an atomic quit flag with a main-thread AppKit loop. The digital-button, stick, motion,
and SDL input implementations are unchanged. The port's virtual-gamepad and device-whitelisting
factories return null. Its build artifacts and handoff notes are not OJD hardware evidence.

The port pins
[GamepadMotionHelpers at 39b578aacf34c3a1c584d8f7f194adc776f88055](https://github.com/JibbSmart/GamepadMotionHelpers/tree/39b578aacf34c3a1c584d8f7f194adc776f88055).
Adapted code must retain the applicable copyright and license notices. JSM's license credits
Julian "Jibb" Smart and Nicolas Lessard; dependent algorithms retain their own attribution.

Upstream reports guide regression tests, not automatic feature additions or accepted patches:

- [Simultaneous presses, #157](https://github.com/Electronicks/JoyShockMapper/issues/157).
- [Held output after a stick-mode change, #89](https://github.com/Electronicks/JoyShockMapper/issues/89).
- [Paired Joy-Con stick input, #188](https://github.com/Electronicks/JoyShockMapper/issues/188).
- [Virtual motion timestamps, #177](https://github.com/Electronicks/JoyShockMapper/issues/177).
- [Motion deadzone units, PR #194](https://github.com/Electronicks/JoyShockMapper/pull/194).
- [Edge extra buttons and touch grids, PR #187](https://github.com/Electronicks/JoyShockMapper/pull/187).

## Chord timing

Native schema-3 chords accept `mode: "simultaneous"` and `window_ms` from 1 to 1000
(default 50). All constituent presses must fall within that inclusive window. Releasing and
pressing a source again replaces its press timestamp. Omitted mode retains the legacy
`modifier` behavior, which requires held sources without a simultaneous-press deadline.

Modifier-chord sources are owned by the modifier recognizer while that chord is effective. Their
individual assignments, additional actions, and raw passthrough contributions stay suppressed.
When the chord completes, it consumes its constituent presses and any sequence completion that
depends on them. Releasing a constituent retires the chord without replaying the suppressed
source action.

The CLI accepts `map chord add <profile> --sources button:south,button:east --target key:space
--mode simultaneous --window-ms 75` (on one command line). Invalid timing is rejected before
profile mutation. The native combination sheet exposes the same mode and simultaneous window.

Simultaneous chords buffer constituent presses until resolution. A match consumes those presses;
an unmatched timeout replays a held action once, and an early release replays a press/release pair.
Passthrough replay uses the virtual-state aggregator, including a retained axis sample for a quick
direction release. A completed smaller chord waits while a higher-priority overlapping chord can
still complete. Higher source count wins, then profile order. Releasing a completed smaller chord
commits it before its release; releasing a larger chord does not activate a smaller chord from
its already-consumed controls. Disjoint chords can remain active together. Layer transitions and
controller teardown cancel pending presses.

The engine uses a nondecreasing clock for each controller session. Backward input and tick
timestamps clamp to that controller’s latest evaluated time; release edges are still processed.
This prevents reversing turbo phases or shortening newly scheduled pulses, and one controller’s
clock does not advance another controller’s input clock.

Sequence history records buffered presses in their original input order and matches the original
first-to-last press interval. A completed sequence that depends on unresolved presses is retained
separately, so later input cannot displace it. Replaying its required presses commits it once;
chord consumption or a layer transition cancels it. Completing a sequence clears its history,
so each deferred completion owns at least one distinct pending press. History remains bounded
by the longest configured sequence plus the number of pending chord presses.

Focused tests cover modifier consumption, additional-action suppression, passthrough ownership,
sequence/chord interaction, bounded history, controller teardown, and layer-transition cleanup.
Native controls compile and draft persistence is tested; visual and VoiceOver validation remain
pending.

## Motion and touch sample transport

DS4 and DualSense parsers now append typed raw gyroscope, accelerometer, and touch frames to
control events. Normalization preserves repeated samples and their relative order while retaining
control-state coalescing. Snapshot control state retains the latest complete frame for each
explicit surface so native capture can detect a new contact; payloads without that field decode
to no touch samples. Compatibility output continues to ignore sample variants.

The packet layout and touch dimensions follow
[Linux hid-playstation at the reviewed revision](https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-playstation.c).
Sensor vectors retain signed ADC values; they are not calibrated degrees per second or gravity
units. Timestamps retain the raw device counter, rational nanoseconds per tick, elapsed time from
the first report, and a parser-session sequence index. DS4 uses a 16-bit counter at 16000/3 ns;
DualSense uses a 32-bit counter at 1000/3 ns. Fractional remainders carry between samples.
A counter decrease denotes one wrap. This assumes ordered reports; a device reset or multiple
wraps during a gap cannot be distinguished from the counter alone. Reconnection needs a fresh
parser session, and fusion must handle discontinuities before these clocks drive motion output.

Touch frames retain two contacts, active flags, contact IDs, and raw coordinates. DS4 retains
up to three USB or four Bluetooth history frames in packet order, including each raw touch
counter. That counter has no assigned time unit. Its containing-report timestamp does not date
individual historical frames. Malformed history counts omit touch history while preserving
valid motion data. Short DS4 control-only reports do not synthesize sensor samples.

Focused tests cover signed decoding, counter wrap and fractional ticks, repeated sample delivery,
touch history, short reports, and DualSense Bluetooth CRC rejection before sensor-clock updates.
The active parser exposes `physicalInputCapabilities` through the existing connected-device
payload: raw motion support and maximum contacts per touch frame. This is a decoding capability,
not calibrated motion or hardware-validation status. Payloads from an older service default to
no sample capability. Tests exercise both DS4 revisions, DualSense, and DualSense Edge through
the device manager and the encoded payload, preserving the runtime device identifier.

Factory calibration for the supported families is applied before remapping. Other controller
families do not advertise calibrated motion; physical validation remains external. Nintendo timing
uses explicit estimation:
[Linux hid-nintendo](https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-nintendo.c)
documents that reports lack a reliable sample timestamp and contain three IMU samples.
The Switch Pro parser decodes all three signed raw samples in wire order and requests IMU
enablement (`0x40`, value `1`) during HID startup. It advertises raw motion decoding through the
same capability contract. Short control-only reports do not advance its sensor clock.

The pipeline captures host receipt time before parsing and supplies it through the shared parser
hook. Nintendo timestamps have `hostEstimate` basis, retain the raw report counter as metadata,
and leave device tick units absent. The first report uses nominal 5 ms sample spacing; subsequent
spacing follows a bounded moving average of host report intervals. Backward receipt times clamp,
and gaps above 30 ms preserve elapsed gaps rather than stretching three samples across the gap.
This is an estimate, not hardware sample timing. Device-counter timestamps retain their distinct
`deviceCounter` basis. Tests cover both parser dispatch paths, sample order, signed values,
backward receipt time, long gaps, short reports, and the IMU startup command.

### Steam Controller full-state motion

The Steam Controller parser decodes raw accelerometer and gyro vectors from full state messages
(type `0x01`), following the packet fields used by
[SDL's Steam HID parser](https://github.com/libsdl-org/SDL/blob/634dff3725b8419902b832d1c84363da211a3596/src/joystick/hidapi/SDL_hidapi_steam.c)
and the layout documented in
[Linux hid-steam](https://github.com/torvalds/linux/blob/893e11787f78e43b534e252249ac3fff4d1333f8/drivers/hid/hid-steam.c).
Startup settings request raw accelerometer and gyro output with IMU mode `0x18`; shutdown retains
the existing default-settings restoration. Raw motion is exposed in parser capabilities.

Packet sequence numbers remain metadata. Motion timestamps use host receipt time relative to the
first accepted motion report, clamp backward receipt times, and have no device tick units.
An immediately repeated sequence number does not emit another motion sample. Counter wrap accepts
the next report. Receiver disconnect/connect transitions reset timing and duplicate tracking;
reports received while disconnected do not advance motion state.

This covers full-state packets on the supported wired/receiver path. BLE chunked packets are not
advertised as supported input; hardware delivery validation remains external. The tests establish
raw decoding and lifecycle behavior, not calibrated physical units or wireless firmware delivery.

### Steam trackpad samples

Full state packets now emit separate `left` and `right` touch surfaces. The shared contact
coordinates are signed 32-bit values. Each frame describes its coordinate origin and dimensions:
Steam pads retain raw signed 16-bit coordinates with origin -32768 and span 65536; Sony frames
retain their zero origin and existing pixel dimensions on the `primary` surface. Contacts use
surface-local IDs, so matching ID zero on two pads does not merge them.

The left axis pair alternates between pad and stick when both are active. Pad packets retain the
last stick value, and interleaved stick packets retain the last pad coordinates. Ending stick
activity neutralizes its contribution. Releasing a pad emits an inactive contact frame. Receiver
lifecycle resets clear remembered pad coordinates along with the motion clock. These rules follow
the full-state interleaving logic in the reviewed SDL source above.

This input path also fixes stick/pad cross-contamination. Physical validation remains pending.

### Touch mappings

Profiles identify `primary`, `left`, and `right` surfaces explicitly. Discrete sources cover the
contact lifecycle, a validated 1-by-1 through 16-by-16 grid cell, and a cardinal swipe with a
minimum normalized travel distance. CLI source forms are `touch:<surface>:contact`,
`touch:<surface>:grid:<columns>:<rows>:<zero-based-column>:<zero-based-row>`, and
`touch:<surface>:swipe:<direction>:<minimum-distance>`. Native capture detects a newly active
surface and its manual assignment controls expose grid dimensions, cell coordinates, and swipe
distance. Touchpad and Steam pad clicks remain distinct physical button sources; a contact never
synthesizes a click.

One optional continuous mapping per surface selects relative pointer output or a left/right
virtual touch stick. Pointer sensitivity is measured in logical screen points per complete
surface span. A touch-stick radius is a normalized surface fraction; its radial deadzone and
output are normalized to 0...1 and -1...1 respectively. Continuous mappings are configurable in
the CLI and native profile editor. Touch-stick modes require virtual output policy.

Runtime state is owned by an exact controller and surface. Contact IDs are never compared across
those boundaries. The lowest active contact starts as the primary contact and remains primary
until it ends; changing contact, geometry, profile, or controller session resets the pointer and
stick baseline. A complete inactive frame releases contact/grid bindings and neutralizes touch
stick output. Swipes fire once when their primary contact ends. Profile replacement, disconnect,
permission suspension, shutdown, and failed delivery use the engine's ordinary drain path, which
releases touch-owned buttons and virtual contributions. Tests cover surface and device isolation,
origin-aware geometry, grid transitions, swipes, pointer reset, virtual neutralization, capture,
CLI parsing, profile validation, persistence, and RPC transport.

### Steam grips and pad clicks

Steam full-state packets expose left/right grip and left/right pad-click events as distinct
physical controls. Schema-3 profiles accept `button:left_grip`, `button:right_grip`,
`button:left_pad_click`, and `button:right_pad_click` in the CLI and native source/capture menus.
They can use the existing binding behaviors, chords, sequences, and layers. New source identifiers
require schema 3. The labels have first-pass translations across the current catalogs; visual,
VoiceOver, and native-language review remain pending.

These controls are input sources, not newly supported virtual buttons. Validation rejects them
as `gamepad_button` destinations, destination menus omit them, and virtual-state construction
filters them. The Steam right-pad click preserves its existing right-stick-click compatibility
output when passed through without a binding. A schema-3 binding consumes that contribution.

Tests cover parser press/release edges, source persistence, key press/release output, invalid
virtual destinations, capture, source menus, and catalog consistency.
Physical isolation and delivery still require hardware validation.

### Independent Joy-Con input

The canonical HID catalog now selects left and right Joy-Con layouts for Nintendo
`057e:2006` and `057e:2007`. Each layout ignores the absent stick and the other half's
button bits, exposes its one rumble motor, and uses Nintendo's three-sample raw IMU path.
Startup requests full input reports and enables IMU and rumble without the Pro Controller's
USB handshake prefix. Both the schema and runtime decoder reject conflicting side selections.

Catalog records were generated from the locked Linux source. Constructed packet tests cover
selection, side filtering, raw sample delivery, startup, and rumble isolation. See
[Joy-Con validation](../testing/joy-con.md) for the exact source and hardware acceptance steps.
### Paired Joy-Con sessions

Schema-3 profiles targeting the left Joy-Con model can opt into `joy_con_pair` and select the
left, right, or no gyro. Pair profiles do not run on a standalone half. The CLI uses
`map joy-con pair <profile> --left <runtime-identifier> --right <runtime-identifier>`; the native
profile screen exposes the same exact connected-controller selection. Runtime identifiers are
opaque and process-local, so pairing is an explicit in-memory session rather than persistent
hardware identity.

Both halves feed one remapping state and one virtual output identity, using the left half as the
session output key. Nintendo's parser normalizes left and right IMU readings into the stable
combined-controller frame before the configured half reaches calibration and gyro routing. The
unselected half's motion samples are discarded; buttons, the left and right sticks, and rail
controls remain side-owned inputs. Existing Nintendo output reports retain per-half rumble bytes.

Disconnecting either exact member, unpairing, or starting a profile-library transaction drains the
combined output, retires the virtual controller, and cancels the session. A still-connected half
returns to its independent compatibility route. Reconnection requires a new explicit pair, and an
old session UUID cannot unpair its replacement. Constructed routing tests cover partial
availability, combined controls, gyro selection, disconnect, replacement-session isolation, and
profile transaction cleanup. Bluetooth hardware acquisition, physical orientation accuracy,
per-half rumble delivery, and virtual consumer recognition remain unverified.

Joy-Con rail buttons expose four schema-3 sources: `button:left_sl`, `button:left_sr`,
`button:right_sl`, and `button:right_sr`. Each belongs to its physical half, including when
both halves are connected. The Pro Controller layout ignores these bits. Rail sources can map
to supported gamepad buttons or system actions; they have no direct virtual button identity.

### DualSense Edge controls and extra-button capabilities

The generated Edge record (`054c:0df2`) selects `edgeButtons` for both registry construction
and live HID discovery. Standard DualSense (`054c:0ce6`) keeps its original system-button map.
Edge function buttons and paddles expose `button:left_function`, `button:right_function`,
`button:left_paddle`, and `button:right_paddle` in schema-3 profiles and native capture/editor
controls. They map to existing output destinations; they are not virtual button destinations.

The field masks follow the
[reviewed SDL PS5 parser](https://github.com/libsdl-org/SDL/blob/0c8feecce6e57a7a8c1b1eb06631e0a7a56fcd8f/src/joystick/hidapi/SDL_hidapi_ps5.c).
Constructed USB/Bluetooth reports test each source through gamepad press/release, repeated
report suppression for digital edges, ordinary-model exclusion, and CRC rejection before
button-state mutation. These tests do not establish Edge firmware or hardware delivery.

`physicalInputCapabilities.additionalButtons` carries the parser's extra physical button
identifiers through the connected-device payload. Sony touchpad/mute, Steam grips/pad clicks,
Joy-Con rail controls, and Edge function/paddle controls are reported by their selected parsers.
An older capability payload without the list decodes as an empty list. Base gamepad controls
remain implicit. The list describes implemented decoding, not physical verification or whether
a control has a virtual output identity.

`physicalInputCapabilities.touchSurfaces` enumerates the identifiers emitted by touch frames:
Sony exposes `primary`, and Steam exposes `left` and `right`. Nintendo exposes no touch surfaces.
An older payload without this list decodes as unspecified (an empty list), even if it has a
nonzero contact count; clients must not invent a surface identity from that count. Frame geometry
continues to carry coordinate origins and dimensions. Tests compare capabilities with actual
parser-produced frames and preserve the metadata through device-payload serialization.

## Physical motion conversion

Motion samples retain their raw ADC vectors and may additionally contain `physicalReading`.
This uses degrees per second and g in a right-handed gamepad frame: X right, Y up, Z toward
the player. A level controller's measured acceleration points approximately +Y; fusion's
physical gravity estimate points in the opposite direction. These conventions follow
[SDL sensor coordinates](https://wiki.libsdl.org/SDL3/SDL_SensorType) and the pinned
[GamepadMotion input contract](https://github.com/JibbSmart/GamepadMotionHelpers/blob/39b578aacf34c3a1c584d8f7f194adc776f88055/GamepadMotion.hpp).
Nonfinite physical vectors are rejected during construction and decoding. Older raw-only
sample payloads remain readable. Physical readings do not imply that fusion has run.

DualSense and Edge now emit nominal readings immediately: gyro ADC / 16 degrees per second,
acceleration ADC / 8192 g, marked `nominalDeviceScale`. Startup requests feature report `0x05`
with 41 bytes. The parser validates its ID, length, all six calibration axes, and Bluetooth
CRC32 with feature seed `0xA3` before atomically accepting factory calibration. Gyro conversion
subtracts bias and scales by the reported speed sum divided by endpoint range; acceleration
subtracts endpoint midpoint and scales by 2 / endpoint range. Bias and sensitivity bounds
follow the reviewed SDL PS5 implementation linked above. The feature-report framing and CRC
follow the reviewed Linux hid-playstation implementation linked above. A rejected reply keeps
the previous valid calibration, or nominal conversion if none has been accepted.

Feature-read responses now reach the owning pipeline actor, serialized with parsing. Stopped
or replaced pipelines reject late replies. CoreHID reads have a two-second timeout and reject
responses from replaced clients. Apple documents that an omitted
[get-report timeout](https://developer.apple.com/documentation/corehid/hiddeviceclient/dispatchgetreportrequest(type:id:timeout:))
waits indefinitely. Calibration provenance travels with each sample; immutable input capability
metadata remains independent of mutable calibration state.

Constructed tests cover nominal physical units, factory bias and scale, whole-report rejection,
Bluetooth feature CRC, stopped-pipeline rejection, and legacy/nonfinite decoding. Signed IOKit
and CoreHID hardware checks must verify feature-report delivery, framing, and physical axis signs.
Calibration acquisition recovery, runtime bias estimation, fusion, calibration controls, and
motion output are described in the following sections.

### Nominal conversion for DS4, Nintendo, and Steam

DS4 defaults to Sony's nominal /16 gyro and /8192 accelerometer scales, retaining X/Y/Z order.
The [reviewed SDL DS4 parser](https://github.com/libsdl-org/SDL/blob/f9abf9e843cb1b9c18aa2401ceb9cfbd7a0d4c74/src/joystick/hidapi/SDL_hidapi_ps4.c)
documents these fallback scales. Its factory-report transport differences remain separate work.

Nintendo uses 14.2842 counts per degree/second and 4096 counts per g, following the
[reviewed SDL Switch parser](https://github.com/libsdl-org/SDL/blob/f9abf9e843cb1b9c18aa2401ceb9cfbd7a0d4c74/src/joystick/hidapi/SDL_hidapi_switch.c).
Both sensors map to the canonical frame as `(-Y, Z, -X)` on Pro/left and `(Y, -Z, -X)` on right
Joy-Con. This is a stable hardware frame; standalone horizontal-use orientation is not silently
applied by the parser. Every IMU sample retains its own raw vector and timestamp.

Steam uses nominal gyro scaling of 2000/32768 degrees/second per count with axis order `(X,Z,Y)`.
Its accelerometer uses 2/32768 g per count with `(X,Z,-Y)`, following the reviewed Steam source
linked above. Negation occurs after widening so the signed minimum remains representable.
These readings are marked `nominalDeviceScale`; none claims factory calibration. Tests exercise
signed extrema, per-family axis signs, units, all three Nintendo samples, and duplicate suppression.

## Acceptance boundary

Product tests cover parser-to-remapper-to-report behavior and lifecycle failures. Signed consumer
checks must separately establish physical isolation, virtual recognition, and actual delivery.
Record USB and Bluetooth, the macOS HID generation, and the consumer used. Passing report-codec
tests does not establish game compatibility. Unavailable hardware checks remain explicit in
release-candidate acceptance; they do not excuse failing executable gates.

### DS4 factory calibration

DS4 startup reads USB feature report `0x02` (37 bytes). Bluetooth first reads that report to
request advanced input mode, then reads calibration report `0x05` (41 bytes). Only the latter
can install Bluetooth calibration; it must pass CRC32 validation with feature seed `0xA3`.
USB gyro endpoints are interleaved by axis; Bluetooth endpoints group all positive endpoints
before all negative endpoints. Gyro conversion subtracts the factory bias and multiplies by
`speedSum / (abs(plus - bias) + abs(minus - bias))`. Accelerometer conversion subtracts the
endpoint midpoint and multiplies by `2 / (plus - minus)`. All six axes must pass the same
bias and scale bounds used for DualSense before the snapshot becomes `deviceFactory`.
Malformed or unavailable replies retain the previous snapshot, initially nominal.

The layout and conversion facts come from the pinned SDL DS4 reference above; report lengths
and Bluetooth feature CRC framing follow the pinned Linux hid-playstation reference. Tests use
different gyro gains on each axis to distinguish the two layouts, check raw-value preservation,
and reject truncated or CRC-corrupted replies. Physical startup framing and measured calibration
accuracy remain hardware checks. Wireless USB dongles retain nominal calibration rather than
claiming factory coefficients; these tests cover direct USB and Bluetooth DS4 connections.

### Nintendo factory calibration

Switch Pro and Joy-Con startup append SPI flash-read subcommand `0x10`, requesting 24 bytes
from address `0x6020`. The parser accepts a pending reply only when report `0x21` contains a
successful acknowledgment, the matching subcommand, the exact address and length, and the
complete coefficient block. Erased flash, nonpositive coefficient ranges, and malformed replies
leave the prior snapshot unchanged. A valid reply installs all six axes atomically and consumes
the pending request. Calibration replies do not advance the motion clock or emit sensor samples.

The pinned SDL Switch reference above defines gyro conversion as
`(raw - gyroOffset) * 936 / (gyroSensitivity - gyroOffset)` degrees per second and accelerometer
conversion as `raw * 4 / (accelSensitivity - accelOffset)` g. Both then use the same canonical
axis transforms as nominal readings. Factory-derived samples carry `deviceFactory` provenance
and preserve all raw readings. Tests cover all three layouts and all three samples per report,
nonzero offsets, unrelated addresses, negative acknowledgments, truncation, and erased flash.
Startup also requests 20 bytes from `0x8026`. A user block with little-endian magic `0xA1B2`
replaces the accelerometer and gyro offsets while retaining factory sensitivity coefficients.
The combined snapshot carries `factoryWithUserOffsets` provenance. Either reply order works;
user data alone cannot calibrate a sample. Missing magic or invalid combined ranges preserve
factory conversion. Completed requests ignore duplicate replies, and a new parser starts with
nominal conversion. Tests cover both reply orders, changed accelerometer sensitivity, gyro
zero-rate correction, invalid user ranges, and provenance serialization.
Physical SPI delivery and calibration accuracy remain hardware checks. No flash writes are
performed.

### Startup acquisition lifetime

HID output startup plans are generated on the active pipeline actor, serializing parser packet
numbers and calibration request state with input parsing. Each delayed startup send checks the
original pipeline's active state, current manager identity, and competing-owner status after its
delay. Reusing a physical location or identifier does not authorize the old pipeline's remaining
commands. Cancellation exits the delay loop. Feature calibration reads also check that lifetime
before reading and before delivering the response. Tests cover inactive plan generation, ownership
loss, replacement with identical device identity, and manager shutdown. Transport calls already
in flight still rely on the HID backend's client-lifetime checks; physical timing is unverified.

Transport-specific startup methods are protocol requirements with default implementations.
This preserves dynamic dispatch through parser-provider existentials: Bluetooth Switch Pro
startup omits USB handshake commands, and Bluetooth DS4 feature reads include report `0x05`.
Regression tests exercise the pipeline/protocol call path in addition to concrete parser calls.

### Feature calibration retry bound

Startup feature reads with a calibration consumer make at most three attempts per request,
separated by 20 ms. Missing reports and rejected calibration data both count as failed attempts.
Success ends the retry loop; cancellation or loss of the original active pipeline ends acquisition.
Each attempt checks the pipeline before the read and before delivering its response. Exhaustion
leaves parser calibration unchanged and continues startup. Reads without a calibration consumer
retain their existing single-attempt behavior. CoreHID's existing two-second read timeout bounds
each dispatched request; this is not a hardware-measured startup latency guarantee. Nintendo SPI
output/reply acquisition uses the separate recovery path below.


### Nintendo SPI recovery and expiry

After the initial startup sequence, the manager schedules two recovery rounds, each following a
200 ms reply window. Each round asks the active pipeline actor for only its still-pending SPI
reads; generated packets use the parser's current output sequence and rumble state. Reports in
a round retain the transport startup interval. A final 200 ms window then expires unanswered
requests. There are at most three transmissions per calibration address, including startup.
Every delayed send checks the original pipeline lifetime. Pipeline stop also expires pending
requests immediately. Accepted calibration remains installed after expiry, while late replies
cannot change it. A new explicit acquisition clears the temporary factory/user blocks before
collecting new replies. Tests cover partial success, packet sequence advancement, late-reply
rejection, fresh acquisition, and stop/restart without reopening old requests. The timing policy
is a bounded software recovery policy; physical loss and timing behavior remain unverified.

### Runtime bias foundation

`RemappingMotionBias` is a native, per-controller calculation component integrated with the motion
engine. It operates after physical-unit conversion and keeps its offset separate from
factory/user calibration provenance. Manual collection uses a time-weighted mean, supports pause,
reset, and explicit finite offsets. Automatic collection initially requires two seconds and at
least ten samples, with per-axis gyro span at most 0.5 degrees/second and acceleration span at
most 0.025 g. It excludes gyro components above 10 degrees/second and acceleration magnitude
outside 0.8–1.2 g. Invalid, nonpositive, or greater-than-100 ms intervals clear collection without
discarding the learned offset. Collection state has fixed storage and bounded duration/count.

This is an independent implementation of the calibration capability, not numerical parity with
GamepadMotionHelpers' adaptive stillness/sensor-fusion estimator. The pinned reference defines
manual and automatic modes and remains the behavioral comparison source. Sensor-fusion bias
correction, orientation processing, profile tuning, and live remapping use this component through
the processing path below. Tests cover stationary bias, changing motion, acceleration, timing gaps, time-weighted
manual collection, pause/reset, and invalid offset rejection.

### Fusion foundation

`RemappingMotionFusion` integrates local gyro rates into a normalized quaternion mapping the
controller frame to a Y-up reference frame. Initial accelerometer alignment handles normal,
sideways, and upside-down poses. Subsequent tilt correction uses an exponential 2/second response
only while acceleration magnitude is between 0.8 and 1.2 g. Gravity is the reference down vector
rotated into controller space; linear acceleration is measured acceleration plus that gravity.
Heading is relative and can drift. Freefall preserves initialized orientation without gravity
correction, while an uninitialized freefall sample produces no fused result.

Invalid/nonfinite inputs, gyro components above 1,000,000 degrees/second, acceleration components
above 1,000 g, and intervals outside 0–100 ms are rejected without changing orientation. These
large numeric bounds prevent arithmetic overflow; they do not certify plausible physical motion.
Synthetic tests cover 90-degree yaw and pitch, gravity removal, upside-down initialization,
freefall, high-acceleration tilt rejection, reset, and invalid/gap state preservation. This native
complementary filter is not a numerical port of GamepadMotionHelpers. Per-device timestamps, bias,
profile tuning, and motion actions integrate through the processing path below.


### Per-device motion processing

The remapping engine now feeds motion samples into each `RemappingDeviceState`'s processor. It
uses sample-relative nanoseconds for integration, independent of report delivery uptime, and
retains the latest corrected gyro, fused orientation, gravity, linear acceleration, and interval.
Duplicate/backward sequence indices and backward sample times do not advance state. A forward
sequence with the same timestamp produces no second integration. Gaps above 100 ms, clock-basis
or tick-unit changes, and calibration-provenance changes reset bias/orientation and establish a
zero-duration baseline. Missing or numerically out-of-range physical readings clear estimates;
the next valid sample also establishes a fresh baseline. This prevents interpolation across
missing motion and prevents extreme finite values from entering bias arithmetic.

The processor uses the active profile's motion tuning. Controller release, profile
replacement, and engine drain discard its containing device state. Tests exercise the real engine
path for two identical models at different locations, release/reacquisition, duplicate/backward
samples, gaps, provenance changes, and extreme-value recovery. Sony and Nintendo readings carry a
session-local calibration revision. Installing changed
coefficients or provenance advances it; identical accepted coefficients and rejected replies do not.
A revision change resets processing estimates even when provenance is unchanged. Older encoded
readings without a revision decode as revision zero.

Live manual bias calibration is available through the authenticated application service and CLI:

```text
map calibration status|start|pause|reset --controller <runtime-identifier>
```

Use the exact controller runtime identifier reported by `map list --json`. Each operation returns
JSON with `hasMotionBaseline`, `isCollecting`, and `offsetDegreesPerSecond` (X/Y/Z). `start`
requires an eligible remapping route with a valid motion baseline. Keep the controller stationary
while collecting. `pause` stops manual collection and retains the estimated offset; automatic bias
collection can continue if the profile enables it. `reset` clears motion estimates and waits for a
fresh sample baseline. Disconnect, profile replacement, invalid samples, and clock/calibration
discontinuities cancel manual collection. Calibration does not change factory coefficients or
persist a user offset in the profile.

The engine checks the captured mapping session before applying queued calibration commands.
Regression coverage rejects a previous session's command after reconnect without clearing the
replacement baseline and covers router queue races. CLI socket tests
cover exact identity, status decoding, and JSON bias values.

The controller input-test window includes a Motion calibration panel. Refresh reads the selected
controller's calibration state; Start calibration, Pause, and Reset use the same router commands.
The panel shows collection state and X/Y/Z bias in degrees per second. It disables overlapping
operations and ignores late results after selection changes. Disconnect and window close clear
the selected calibration target. Closing the panel does not stop service-owned manual collection;
use Pause to stop collecting. Native visual/VoiceOver verification and translations of the new
calibration strings remain pending.

### Gyro coordinate projections

Processed motion exposes local, player, and world projection through the shared Codable
`RemappingMotionSpace` contract. Local mode returns controller X pitch and Y yaw. Player mode
keeps local pitch and combines Y/Z gyro around gravity, with a default yaw relaxation of 1.41
capped by the combined Y/Z rate. World mode projects gyro onto reference up for yaw and projects
the controller pitch axis onto the gravity plane for pitch. Its default 0.125 side-reduction
threshold suppresses unstable pitch near a sideways pose; exact side alignment returns zero
pitch. Gravity is normalized, so its magnitude does not scale output.

Player/world formulas are adapted from the pinned MIT GamepadMotionHelpers reference. The full
copyright and permission notice is retained in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
Binary distribution of that notice remains part of candidate packaging. Tests distinguish flat,
sideways, and tilted poses, enforce the player yaw cap, and reject zero gravity or invalid tuning.
The projection produces degrees/second; the native motion-action layer applies pointer sign,
sensitivity, smoothing, and output mapping.

### Motion tuning contract and transform

`RemappingMotionTuning` is a shared Codable value with defaults for omitted fields and rejection
of nonfinite/out-of-range values. It selects projection, independent pitch/yaw angular sensitivity
(0–100), inversion, smoothing half-time (0–1000 ms), radial rate threshold (0–1000 degrees/second),
automatic bias, player yaw relaxation, world side reduction, and gravity correction rate (0–100/s).
The transform applies the radial threshold, time-based exponential smoothing, then sensitivity
and inversion. The processor feeds the same tuning into bias, fusion, and projection and retains
the tuned angular rates in its result. A configuration change resets processing/filter history.

Profiles persist non-default tuning under `motion_tuning`; omitted tuning uses defaults within
schema 3. The live engine passes the active profile's settings into the
processor, and app/CLI profile reconstruction preserves them through metadata and binding edits.
CLI create/update accepts `--motion-space local|player|world`, `--motion-pitch-sensitivity`,
`--motion-yaw-sensitivity`, `--motion-smoothing-half-time-ms`,
`--motion-threshold-degrees-per-second`, `--motion-yaw-relaxation`,
`--motion-side-reduction-threshold`, and `--motion-gravity-correction-rate`.
`--motion-invert-pitch`, `--motion-invert-yaw`, and `--motion-automatic-bias` take explicit
`true|false` values. Omitted options preserve current settings on update. The profile editor
now has a Motion tuning sheet with all fields, reset, and cancel. Numeric fields accept typed
values and synchronize valid edits with sliders. Invalid text remains visible and prevents saving;
decimal-comma input is supported for locales that use it. Changes use the existing
validated draft and profile save flow. Labels have English source and first-pass translations in 68 locale catalogs. Amharic and Northern Sámi still use English
motion labels pending translation. Remaining translations,
native-language review, and native visual/accessibility proof are pending. CLI help includes the option syntax in all shipped catalogs. Tests cover default/partial
JSON, profile round trips, omitted schema-3 defaults, invalid decoding, editing preservation, live
engine sensitivity/inversion, radial threshold, and identical smoothing after one 100 ms step or
ten 10 ms steps. Gyro routing converts those angular rates to the configured destination.

### Gyro output and activation

Schema 3 profiles now accept `gyro_output`. Omitted settings preserve disabled output. Modes are
`disabled`, `mouse`, `left_stick`, and `right_stick`. Stick modes require a virtual gamepad output
policy; mouse mode requires system-input permission. Native profile edits preserve these settings.
The Motion sheet edits output, scaling, activation, and motion tuning together. The CLI exposes
`--gyro-output`, `--gyro-pointer-points-per-degree`, and `--gyro-full-stick-degrees-per-second`.

Mouse output integrates accepted sample intervals into logical screen-point deltas. Stick output
uses angular speed divided by the configured full-stick speed, clamps each axis, and participates
in the existing gamepad contribution accumulator. A 100 ms sample timeout removes only the gyro
contribution. Reset calibration removes the gyro stick contribution through the engine output
transaction; delivery failure follows the normal fail-closed recovery path.

Activation modes are `always`, `while_held`, `while_released`, and `toggle`, configured with
`--gyro-activation` and `--gyro-activation-source`. Sources may be buttons, D-pad directions, or
axis directions. Continuous axes are rejected. Always-active mode has no activation source.
Enabling starts with a fresh sample baseline; disabling immediately removes the gyro stick
contribution. Activation controls retain their explicit bindings. Their original virtual contribution is suppressed
by default when gyro output is enabled. Set `--gyro-consume-activation false` or turn off the native
suppression toggle to pass through an otherwise unmapped activation control. An axis-direction
activator reserves its parent virtual axis, consistent with ordinary axis-direction mappings.

Focused tests cover sample timing, timeout aggregation, activation, calibration-reset delivery
failure, CLI persistence, locale-aware numeric entry, and native draft preservation. Trackball,
layer tuning overrides, and supported virtual motion output are implemented as described below.
The new gyro editor labels are present in all catalogs but await translation. Physical
motion direction, rendered controls, keyboard navigation, and VoiceOver remain unverified.

Trackball configuration is available through `--gyro-trackball-source <source>`,
`--gyro-trackball-axes pitch|yaw|both`, `--gyro-trackball-decay <halvings/s>`, and
`--gyro-trackball-consume true|false`. Set the source to `none` to remove trackball settings.
Partial updates preserve existing fields; tuning without a source and removal combined with
new tuning are rejected. Defaults select both axes, one velocity halving per second, and
suppression of the source's original virtual contribution. Zero decay retains constant velocity.

While the source is held, selected axes use the last accepted angular velocity instead of new
physical motion. Mouse travel uses the analytical decay integral; sticks use the current decayed
velocity. Processing remains sample-driven, and gaps clear retained motion. This native algorithm
uses the last velocity, not JSM's 125 ms sample average. The Motion sheet authors trackball enablement, control, axes, decay, and source consumption.
Typed decimal values follow the current locale. Translation, native visual/accessibility review,
and physical feel/direction validation remain pending.

### Layer motion overrides

A layer may contain an optional `motion_tuning` object. The most recently activated layer with
an override supplies the complete tuning value; active layers without one leave the previous
choice in effect. Releasing a held layer or toggling it off restores the earlier active override,
or the profile tuning when no override remains. A tuning change immediately removes the gyro
stick contribution and clears retained trackball motion, calibration collection, and the motion
baseline. Output resumes only after a new baseline sample.

Use `map layer motion <profile> --layer <uuid> --motion-yaw-sensitivity 0.5` to author an override.
All existing `--motion-*` tuning options are accepted. The first edit starts from the profile's
current tuning; later edits preserve unspecified override fields. Use
`map layer motion <profile> --layer <uuid> --clear` to restore inheritance. Clearing cannot be
combined with tuning options. Each native layer row has a Motion tuning button. The shared tuning
sheet offers
Use profile tuning to remove the override. Native rendering, keyboard navigation, VoiceOver,
and translation review remain pending.

### Virtual motion output

Set `gyro_output.virtual_motion` or use `--gyro-virtual-motion true` to forward the processor's
runtime-bias-corrected gyroscope and calibrated accelerometer through a supported virtual
controller report. This is independent of the mouse/stick gyro mode, so a profile may publish
motion while also using gyro for a mapped destination. Virtual motion requires virtual-gamepad
output. The native Motion sheet exposes the same setting and uses the existing validated save
path.

DualShock 4 USB, DualSense USB, and Switch Pro USB virtual identities encode their documented
sensor fields. Other identities report motion as unavailable rather than adding vendor data to a
descriptor that does not define it. Sony reports use their nominal 1/16 degree/second and 1/8192 g
scales. Switch Pro reports use the advertised virtual calibration scale and repeat the latest
sample in its three IMU slots with the inverse Pro-controller coordinate transform.

The virtual-device session owns its report clock. Accepted sample intervals advance it
monotonically; a source clock-basis, tick-unit, calibration-revision, or tuning discontinuity
clears motion and requires a new baseline without resetting the published clock. Missing or
invalid physical readings, a 100 ms sample timeout, calibration reset, layer tuning change,
profile replacement, disconnect, suspension, shutdown, and output failure all clear the current
sensor fields. Control-only report updates preserve both current sensor values and the virtual
clock. Focused tests distinguish supported report layouts, timestamp units, Nintendo axes,
timeout and discontinuity cleanup, profile persistence, CLI/native authoring, and fail-closed
delivery. Consumer recognition, physical direction/scale, USB and Bluetooth behavior, and
hardware latency remain external gates and are not established by constructed reports.

### Angular stick modes

Native `stick_mappings` entries select the left or right stick. Aim integrates radial stick
strength into angular travel at `aim_degrees_per_second`; `pointer_points_per_degree` converts
that travel to logical screen points. Positive stick Y moves the pointer upward. Flick starts a
smooth timed turn when the stick crosses the radial threshold, then follows rotation around the
rim. `flick_only` omits rim rotation; `rotate_only` omits the initial turn. The initial angle is
clockwise from forward, and rim rotation follows the shortest angular difference across the rear
seam. A centered stick finishes its pending flick through the shared scheduler. Disconnects and
profile replacement cancel pending travel. Aim stops at center and caps delayed integration at
100 ms per update.

Create or update one stick per CLI command:

```sh
OpenJoystickDriver --headless map update Desktop --stick-source right --stick-mode flick \
  --stick-pointer-points-per-degree 4 --stick-flick-duration-ms 100
OpenJoystickDriver --headless map update Desktop --stick-source left --stick-mode aim \
  --stick-aim-degrees-per-second 360 --stick-inner-deadzone 0.1
OpenJoystickDriver --headless map update Desktop --stick-source right --stick-mode none
```

Unspecified fields retain their current values, and edits preserve the other stick. `none`
removes the selected mapping and cannot be combined with tuning options. Radial inner and outer
deadzones must sum to less than one; response exponent shapes normalized radial strength.
`--stick-invert-x` and `--stick-invert-y` accept `true` or `false`. Flick threshold and hysteresis
control engagement and rearming; hysteresis must be smaller than the threshold.

A mapped stick suppresses its original virtual axes. Explicit axis bindings still run, allowing
additional destinations; this does not hide the physical controller from other processes.
Angular stick modes require system-input access. The profile editor’s Stick modes sheet edits
both sticks, preserves hidden mode settings, and validates both drafts before applying them.
Reset disables the selected stick mapping; Cancel discards sheet edits. Rendered layout, keyboard
navigation, VoiceOver, translated labels/help, and physical feel/direction validation remain pending.

### Area, ring, scroll, and steering stick modes

The same `stick_mappings` contract also supports `pointer_area`, `pointer_ring`, `scroll_wheel`,
and `steering`. All modes apply the shared radial inner/outer deadzones, response exponent, and
axis inversion before their mode-specific calculation. `pointer_area` captures the current
pointer as its activation anchor and places the pointer relative to that anchor by the transformed
stick vector and `pointer_radius_points`. `pointer_ring` uses the transformed stick angle and the
same fixed logical-point radius. Centering either mode returns to the anchor. No absolute display
coordinates or display geometry are stored in a profile.

`scroll_wheel` measures the shortest angular movement between consecutive deflected samples.
`scroll_degrees_per_line` converts accumulated travel to logical scroll lines while retaining a
bounded sub-line remainder; `scroll_axis` selects horizontal or vertical output.
`rotation_direction` defines which physical rotation is positive. Centering drops the previous
angle, so re-engagement cannot manufacture travel across a gap. System-event delivery retains
fractional line displacement until it can emit a high-resolution scroll event.

`steering` accumulates shortest angular travel into a bounded wheel angle.
`steering_degrees_at_full_scale` maps that angle to the selected virtual left- or right-stick X
axis. While the stick is not fully deflected, `steering_return_degrees_per_second` unwinds toward
neutral using monotonic time, with each delayed step capped at 100 ms. The shared scheduler keeps
return active without controller reports. The mapping owns one independent virtual-axis
contribution; replacement, disconnect, permission loss, suspension, shutdown, or failed delivery
removes it immediately without disturbing other contributors.

Stick mappings suppress their physical virtual axes unless `passthrough` is true. Pointer and
scroll modes require post-event access; steering requires mapped virtual output. CLI create/update
accepts the `--stick-pointer-radius-points`, `--stick-scroll-*`, `--stick-rotation-direction`,
`--stick-steering-*`, and `--stick-passthrough` options documented by `map help`. The native Stick
modes sheet exposes the same values and retains hidden mode settings while switching modes.

### Motion lean and steering

An accepted calibrated motion sample derives signed controller lean from its acceleration vector.
Optional `motion_tuning.lean` defines a 1–89 degree digital threshold and a smaller release
hysteresis. It supplies typed `motion:lean:left` and `motion:lean:right` sources through the normal
binding, chord, sequence, layer, consumption, and lifecycle paths. Optional
`motion_tuning.steering` maps lean outside `deadzone_degrees` to one virtual stick X axis, reaches
full scale at `full_scale_degrees`, applies `response_exponent`, and may invert direction. It owns
an independent virtual contribution rather than replacing other mapped contributors.

Motion lean and steering require a calibrated physical reading. Invalid or missing readings,
clock/calibration discontinuity, a 100 ms sample timeout, profile/layer replacement, calibration
reset, disconnect, suspension, shutdown, or output failure clears digital and virtual ownership.
Changing effective layer tuning requires a fresh baseline. Motion steering requires mapped
virtual output; lean-only bindings do not. CLI uses `--motion-lean*` and
`--motion-steering-*`; the native Motion tuning sheet authors the same fields.

### Dual-stage triggers

`trigger_mappings` configures each physical trigger once and exposes typed `trigger:left:soft`,
`trigger:left:full`, `trigger:right:soft`, and `trigger:right:full` sources. Thresholds are normalized
trigger values. `soft_threshold` must be below `full_threshold`; `hysteresis` is subtracted on
release and must be below the soft threshold. The engine evaluates release transitions before
press transitions so exclusive full pulls cannot overlap the soft action accidentally.

The interaction modes are:

- `simultaneous`: soft remains active when full activates.
- `exclusive`: full releases and replaces soft.
- `prefer_full`: soft waits for `skip_window_ms`; a quick full pull selects full only, while a late
  full pull is ignored until release.
- `prefer_full_combined`: the same quick-pull selection, but a full pull after committed soft joins
  it.
- `responsive_prefer_full`: soft emits immediately, a quick full replaces it, and a late full is
  ignored.
- `responsive_prefer_full_combined`: immediate soft, quick replacement, and late combination.

Buffered stages use the controller's monotonic shared scheduler; no per-mapping timer is created.
Release, profile replacement, disconnect, permission loss, suspension, shutdown, and delivery
failure cancel pending deadlines and release both stage sources. A configured trigger suppresses
its analog virtual axis unless `passthrough` is true; explicit ordinary axis bindings still run.
The CLI `--trigger-*` options and native Trigger stages sheet create, update, and remove one trigger
configuration at a time. Every mutation validates the complete schema-3 profile, so a stage source
cannot outlive its trigger configuration.

Focused coverage distinguishes anchor return, shortest-angle wrap, fractional scroll accumulation,
steering unwind and ownership cleanup, motion timeout and profile replacement, trigger ordering,
all quick/late full-pull policies, shared deadlines, passthrough, schema round trips, CLI parsing,
and native draft validation. The new catalog keys have English fallback text in every shipped
locale; translation review remains external. Native visual layout, keyboard-only traversal,
VoiceOver announcements, physical pointer/scroll/steering feel, motion direction, and real trigger
threshold behavior remain external gates and are not established by constructed tests.

### Mapping-owned physical output

A discrete destination may own one source-controller output channel while its action is active:
`rumble`, `player_indicator`, `color`, `brightness`, or `adaptive_trigger`. Each claim is scoped to
the exact runtime `DeviceIdentifier`; a stale claim cannot select another controller of the same
model or a replacement at a new session location. Unsupported motors, lights, or trigger sides
fail delivery instead of being emulated. Profile validation accepts physical destinations without
requiring virtual output, rejects non-finite or out-of-range normalized values, and prohibits
continuous sources and turbo.

Channels arbitrate independently. The most recently activated mapping claim wins and releasing it
restores the preceding active claim. Input Test output is a higher-priority manual override:
timed rumble restores mapping output when its bounded timer expires, while an off player indicator,
black color, or zero brightness releases the corresponding manual override. Disconnect,
permission loss, pipeline replacement, profile replacement, suspension, failed remapping delivery,
and shutdown remove mapping ownership and attempt a neutral report before transport teardown.
Successful delivery means that the supported transport accepted its output report; it is not
evidence that the physical actuator or light responded.

CLI targets use `physical:rumble:<motor>:<0...1>`, `physical:player:<0...4>`,
`physical:color:<red>:<green>:<blue>`, `physical:brightness:<0...1>`, and
`physical:adaptive:<left|right>:off|resistance:<start-position>:<strength>`. The native destination
picker includes bounded presets and preserves imported values outside that preset list. DualSense
USB and Bluetooth reports implement off and resistance effects with side-specific validity flags,
bounded 0–9 start position, bounded 0–8 strength, and the Bluetooth output CRC. Physical rumble,
lighting, adaptive-trigger behavior, report timing, and coexistence with vendor software remain
hardware gates; catalog text is present in every locale with translation review pending.

### Authoring and accessibility coverage

Profile create, update, import, and export all use the same schema-3 value and complete-profile
validation path. The authenticated RPC transports that value without field-specific reconstruction.
CLI binding, layer, chord, sequence, action-collection, touch, motion, stick, trigger, Joy-Con pair,
and physical-output grammars preserve unspecified values and reject an invalid complete result.
The renderer emits parseable physical destinations, including exact normalized adaptive-trigger
parameters.

The native editor exposes the same profile sections and uses `RuntimeProfileDraft` as its sole
mutation boundary. Physical destinations have reusable typed controls for motor, intensity,
player indicator, RGB channels, brightness, trigger side, effect, resistance start, and strength;
they are available to ordinary and layer assignments, additional and alternate actions, chords,
and sequences. Imported values not present in the convenience preset menu remain selectable and
editable. Native labeled `Picker` and `Slider` controls retain keyboard traversal and accessible
values. Profile option catalogs and physical value controls are split from the profile draft so
the draft remains responsible only for validated mutations.

All new labels and CLI help have English fallback entries in every shipped locale. This establishes
catalog completeness, compilation, round-trip behavior, and programmatic accessibility labels.
It does not establish translated wording, visual layout at every text size, keyboard-only workflow
quality, or VoiceOver announcement order; those remain external review gates.

## Integration and release evidence

Constructed integration coverage runs 256 exact-identity controller sessions through mixed
keyboard, virtual-gamepad, mouse, timed, combination, and mapping-owned physical destinations,
then verifies that controller state and shared output reference counts drain completely. A 10,000
input-cycle stress case bounds sequence history, deferred sequences, chord presses, pulse
deadlines, and turbo state by the active profile. A separate 10,000-update physical-output case
verifies that repeated channel updates replace one owner claim rather than accumulating claims.

Focused routing and lifecycle suites additionally cover profile replacement, permission loss,
suspension, delivery failure, disconnect, paired-session replacement, virtual report aggregation,
motion discontinuities, scheduled steering and trigger work, and manual-versus-mapping physical
output arbitration. These tests establish deterministic ownership and storage bounds; they do not
establish hard real-time guarantees, physical latency, actuator response, or consumer recognition.

The software release gate is the repository's catalog, profile, schema, script structure, Swift
structure, lint, DriverKit generation, macOS 14 parser, complete Swift test, and whitespace checks
listed in `AGENTS.md`. Current milestone state is recorded in
[Beta.4 remapping status](remapping-status.md). Signed-runtime behavior, supported-controller USB
and Bluetooth delivery, physical isolation, motion and touch feel, haptics and adaptive triggers,
native visual and accessibility quality, translation review, consumer recognition, and end-to-end
latency remain external gates and must be recorded as observations rather than inferred from
constructed reports.
