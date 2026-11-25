# Remapping

Remapping means changing what a button or stick does. Press A on the controller and a game can see B, a key on the keyboard, or a mouse click instead.

Pages:

- [Input samples](remapping-input-samples.md)
- [Calibration](remapping-calibration.md)
- [Motion processing](remapping-motion.md)
- [Advanced controls](remapping-advanced-controls.md)

## Design

Input from the controller is first cleaned up into a standard shape, then remapped. The result goes to a virtual gamepad, the keyboard, the pointer, scrolling, or a mix. OJD runs all of it itself, with no JSM process, script interpreter, SDL, or outside program that pushes state in.

| Area | What exists | Where it grows |
| --- | --- | --- |
| Output | Only the virtual gamepad, or only system events | Both at once; each control is used up or also passed through |
| Bindings | Long hold, multi-tap, turbo, sequences | Toggles, pulses, explicit release, several actions per button |
| Combinations | Buttons pressed together (chords), layers | Timed and modifier chords, held-back presses, overrides |
| Physical input | Buttons, D-pad, sticks, triggers | Motion with timestamps, touch points, extra buttons |
| Motion | No standard motion event | Calibration, sensor fusion, coordinate spaces, gyro output |
| Sticks and triggers | Deadzone, gain, flip, curves, threshold | Aim, flick, hybrid, area and ring, scroll, steering, lean, two-stage triggers |
| Touch | Touchpad click as a button | Touch and click, grids, pointer, sticks, swipes |
| Several controllers | A per-session device identity | Joy-Con pairs, choosing which gyro to use |
| Physical output | Rumble and lights run by each protocol | Mapping actions, who owns which motor, adaptive triggers |
| Editing | Shared profiles, signed-in RPC, CLI, editor | The app and the CLI can edit everything |

A mapped control stops sending its normal virtual input, unless you turn on passthrough. OJD lets go of every output it holds, and cancels scheduled actions and waiting presses, when any of these happens:

- the profile or layer changes
- the controller disconnects
- a permission is lost
- the session is paused or shut down

If a mapping fails, the input it used up doesn't come back.

Hiding parts of the virtual reports doesn't hide the controller from other apps. A profile that depends on hiding needs exclusive ownership. When OJD can't get it, it says so in a message of its own, apart from permission and publishing errors. The IOKit HID backend opens and closes each device with `kIOHIDOptionsTypeSeizeDevice`.

## Status

Built, with tests on made-up input. Not yet checked:

- real controllers and virtual devices with a signed build
- physical hiding, motion, touch, haptics, lights, and adaptive triggers over USB and Bluetooth
- a review of the look, keyboard-only use, VoiceOver, and translations
- whether games recognize it, and the full delay from button to game

## Several Actions per Button

Profiles must declare `apiVersion: openjoystickdriver/v1alpha4`. The reader refuses any other value before it reads anything else. An assignment has one main destination and an ordered `additionalActions` list. Each action has:

- a UUID
- a destination
- a behavior
- optional turbo, long-hold, multi-tap, or pulse settings

Action IDs must be unique across the profile, and they count toward the 512-item mapping limit. Actions that send a range of values, such as a stick, use the assignment's axis tuning. Permissions apply to every action, including actions in layers that aren't active.

`ojd binding set --actions-json <JSON-array>` replaces the list. Leave it out to keep the list, or pass `[]` to remove all actions. Edit layer bindings with `ojd profile edit <profile>`.

Behaviors:

- Hold: follows your finger. Down while you press, up when you let go.
- Toggle: the first press turns the output on, the next turns it off.
- TapOnPress, TapOnRelease: sends a quick press and release when you press, or when you let go. A release tap needs a matching press first, and losing control of the assignment cancels it.
- Pulse: holds for `pulseDurationMs` (1 to 5000 ms, default 100). Letting go early doesn't cut it short.
- Press: holds until a Release action or cleanup.
- Release: lets go of this controller's held destinations that match it, and cancels their pulse and turbo timers.

Actions run in profile order, each with its own timer. When two actions hold the same key or modifier, OJD counts them and lets go only when both are done.

## Reference Sources

Reference: [JoyShockMapper at bb69784488937e0a5e21988b966eccd9f04d504e][1] and the contributor's `JoyShockMapper-macos.zip`, SHA-256 `5f56191598774fa907f1b22aacc85bf46967a6159ed1b1933de258c2d816fb33`.

The archive changes only platform and build code. The button, stick, motion, and SDL input code is the same as upstream. Its virtual-gamepad and device-whitelist factories return null. Its builds don't count as OJD hardware evidence.

The port pins [GamepadMotionHelpers at 39b578aacf34c3a1c584d8f7f194adc776f88055][2]. Code taken from it keeps its notices, crediting Julian "Jibb" Smart and Nicolas Lessard. Upstream reports that OJD tests guard against:

- [Simultaneous presses #157](https://github.com/Electronicks/JoyShockMapper/issues/157).
- [Held output after stick-mode change #89](https://github.com/Electronicks/JoyShockMapper/issues/89).
- [Paired Joy-Con stick input #188](https://github.com/Electronicks/JoyShockMapper/issues/188).
- [Motion deadzone units PR #194](https://github.com/Electronicks/JoyShockMapper/pull/194).
- [Edge buttons and touch grids PR #187](https://github.com/Electronicks/JoyShockMapper/pull/187).

[1]: https://github.com/Electronicks/JoyShockMapper/tree/bb69784488937e0a5e21988b966eccd9f04d504e
[2]: https://github.com/JibbSmart/GamepadMotionHelpers/tree/39b578aacf34c3a1c584d8f7f194adc776f88055

## Chord Timing

A chord is two or more buttons that do something together, like a piano chord. There are two kinds:

- `mode: "Simultaneous"`: every button must go down within `windowMs` of the others (1 to 1000, default 50, edges included). Pressing one button again resets its time.
- Modifier, when `mode` is left out: hold the buttons in any order, with no time limit.

Edit chords with `ojd profile edit <profile>` or the combination sheet. OJD refuses timing that's out of range.

While a modifier chord is held, the buttons in it don't do their own jobs: their assignments, extra actions, and passthrough all stay quiet. A finished chord uses up its presses, and any sequence that depends on them. Letting go of one of its buttons ends the chord without replaying anything.

A Simultaneous chord holds presses back until it knows the answer:

- On a match, the presses are used up. On a timeout, a held action plays once; an early release plays its press and release.
- Passthrough replays go through the virtual-state aggregator.
- If a smaller chord is complete but a bigger chord that shares buttons could still finish, the smaller one waits. The chord with more buttons wins, then the one earlier in the profile.
- Letting go of a smaller chord runs it before its release. Letting go of a bigger chord never starts a smaller one. Chords that share no buttons can be active together.

Each controller session has a clock that never runs backward. A time stamp from the past is moved up to the latest time OJD has seen, so turbo never goes backward and pulses never get shorter.

Sequence history saves held-back presses in the order you pressed them, and matches on the time from the first press to the last. If a finished sequence depends on presses OJD hasn't decided yet, OJD keeps it apart from newer input and runs it once when those presses replay. A chord using up those presses, or a layer change, cancels it. History holds at most the longest sequence plus the waiting chord presses.
