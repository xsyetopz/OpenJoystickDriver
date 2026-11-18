# Remapping

Pages:

- [Input samples](remapping-input-samples.md)
- [Calibration](remapping-calibration.md)
- [Motion processing](remapping-motion.md)
- [Advanced controls](remapping-advanced-controls.md)

## Design

Input flows through normalization and remapping to virtual gamepad, keyboard, pointer, or scroll output, or both. OJD owns the session: no JSM process, interpreter, SDL dependency, or third-party state-injection endpoint.

| Capability | Existing foundation | Extension |
| --- | --- | --- |
| Output | Exclusive virtual-gamepad or system-event | Mixed output, per-control consumption/passthrough |
| Bindings | Long hold, multi-tap, turbo, sequences | Toggles, pulses, explicit release, multi-action |
| Combinations | Simultaneous chords, layers | Timed and modifier chords, buffered consumption, overrides |
| Physical input | Buttons, D-pad, sticks, triggers | Timestamped motion, touch contacts, extra buttons |
| Motion | No normalized motion event | Calibration, fusion, coordinate spaces, gyro output |
| Stick and trigger processing | Deadzone, gain, inversion, curves, threshold | Aim, flick, hybrid, area/ring, scroll, steering, lean, dual-stage triggers |
| Touch | Touchpad click button | Touch/click, grids, pointer, sticks, swipes |
| Multiple controllers | Runtime device identity | Paired Joy-Con sessions, gyro selection |
| Physical output | Protocol-owned rumble, indicators | Mapping actions, channel ownership, adaptive triggers |
| Authoring | Shared profiles, authenticated RPC, CLI, editor | Native UI and CLI for all |

Mapped controls replace their virtual contribution unless passthrough is set. Profile and layer transitions, disconnect, permission loss, suspension, and shutdown release owned output and cancel scheduled actions and pending presses. A failed mapping restores no consumed input.

Filtering virtual reports does not hide the controller from other applications. Isolation-dependent profiles need exclusive ownership; failing to get it is reported apart from permission and publication failures. The IOKit HID backend opens and closes each device with `kIOHIDOptionsTypeSeizeDevice`.

## Status

Implemented, with constructed tests. Not validated:

- signed-runtime controller and virtual-device behavior
- physical isolation, motion, touch, haptics, lighting, adaptive triggers over USB and Bluetooth
- native visual, keyboard-only, VoiceOver, localization review
- consumer recognition, end-to-end latency

## Native Action Collections

Profiles must declare `apiVersion: openjoystickdriver/v1alpha3`; the decoder rejects any other value first. An assignment has a primary destination and an ordered `additionalActions` array; each action has a UUID, destination, behavior, and optional turbo, long-hold, multi-tap, or pulse settings. Action IDs are unique across the profile and count toward the 512-item mapping limit. Continuous actions use the assignment's axis tuning. Permissions cover every action, inactive layers included.

`ojd binding set --actions-json <JSON-array>` replaces the collection (omit to keep, `[]` removes all). Edit layer bindings with `ojd profile edit <profile>`.

Behaviors:

- Hold: follows the physical press.
- Toggle: switches owned output.
- TapOnPress, TapOnRelease: press/release pair on that edge. A release tap needs a matching press; losing assignment ownership cancels it.
- Pulse: presses for `pulseDurationMs` (1...5000 ms, default 100); release does not shorten it.
- Press: holds until Release or cleanup.
- Release: releases the controller's matching held destinations and cancels their pulse and turbo timers.

Collections dispatch in profile order with separate timers. Shared keyboard and modifier outputs are reference counted.

## Reference Sources

Reference: [JoyShockMapper at bb69784488937e0a5e21988b966eccd9f04d504e][1] and the contributor's `JoyShockMapper-macos.zip`, SHA-256 `5f56191598774fa907f1b22aacc85bf46967a6159ed1b1933de258c2d816fb33`.

The archive adapts only platform and build code; button, stick, motion, and SDL input code is unchanged. Its virtual-gamepad and device-whitelisting factories return null. Its builds are not OJD hardware evidence.

The port pins [GamepadMotionHelpers at 39b578aacf34c3a1c584d8f7f194adc776f88055][2]. Adapted code keeps its notices, crediting Julian "Jibb" Smart and Nicolas Lessard. Upstream reports behind regression tests:

- [Simultaneous presses #157](https://github.com/Electronicks/JoyShockMapper/issues/157).
- [Held output after stick-mode change #89](https://github.com/Electronicks/JoyShockMapper/issues/89).
- [Paired Joy-Con stick input #188](https://github.com/Electronicks/JoyShockMapper/issues/188).
- [Motion deadzone units PR #194](https://github.com/Electronicks/JoyShockMapper/pull/194).
- [Edge buttons and touch grids PR #187](https://github.com/Electronicks/JoyShockMapper/pull/187).

[1]: https://github.com/Electronicks/JoyShockMapper/tree/bb69784488937e0a5e21988b966eccd9f04d504e
[2]: https://github.com/JibbSmart/GamepadMotionHelpers/tree/39b578aacf34c3a1c584d8f7f194adc776f88055

## Chord Timing

Chords take `mode: "Simultaneous"` and `windowMs` 1 to 1000 (default 50): all presses must fall within that inclusive window, and a repeated press replaces its timestamp. An omitted mode selects Modifier: held sources, no deadline. Edit chords with `ojd profile edit <profile>` or the combination sheet; invalid timing is rejected.

While a modifier chord is effective, its sources' assignments, additional actions, and passthrough stay suppressed. A completed chord consumes its presses and any dependent sequence completion. Releasing a constituent retires the chord without replay.

Simultaneous chords buffer presses until resolution:

- A match consumes the presses. A timeout replays a held action once; early release replays press and release.
- Passthrough replay uses the virtual-state aggregator.
- A completed smaller chord waits while a higher-priority overlapping chord can still complete (higher source count wins, then profile order).
- Releasing a smaller chord commits it before its release; releasing a larger one activates no smaller one. Disjoint chords can stay active together.

Each controller session has a nondecreasing clock: backward timestamps clamp to the latest evaluated time, so turbo never reverses and pulses never shorten.

Sequence history records buffered presses in input order and matches the first-to-last interval. A completed sequence depending on unresolved presses is held apart from later input and commits once when they replay; chord consumption or a layer transition cancels it. History is bounded by the longest sequence plus pending chord presses.
