# Advanced Remapping Controls

Ways to make a stick, a trigger, or a tilt of the controller do something richer than "press a key". See the [remapping overview](remapping.md).

## Angular Stick Modes

These modes let a stick turn the camera like a mouse would. Entries in `stickMappings` pick the left or right stick.

| Mode | What it does |
| --- | --- |
| Aim | The further you push, the faster you turn, at up to `aimDegreesPerSecond`. It stops when the stick is centred, and counts at most 100 ms of a late update. `pointerPointsPerDegree` turns degrees into screen points. |
| Flick | Push past the threshold and the view snaps toward that direction over a set time. Then sliding the stick around the edge keeps turning. `FlickOnly` skips the edge turning. `RotateOnly` skips the first snap. |

- The first angle counts clockwise from straight ahead. Turning around the edge always takes the shorter way across the back.
- When the stick returns to centre, any unfinished flick finishes through the shared timer. Unplugging or swapping the profile cancels the rest of the turn.

The command-line tool has no stick options. Edit `stickMappings` with `ojd profile edit <profile>`, or export the profile, change it, and import it. The checks require:

- the inner and outer deadzones (the "ignore" rings near the centre and edge) to add up to less than one
- the flick hysteresis (how far back you must come before it counts as let go) to be smaller than the threshold

A mapped stick hides its normal virtual axes. Bindings you set on a single axis still run. Angular modes need permission to send system input. The **Stick Modes** sheet edits both sticks and checks both before saving. **Reset** turns off the selected mapping. Not checked yet: layout, keyboard navigation, VoiceOver, translations, and how it feels in the hand.

### Area, Ring, Scroll, and Steering Stick Modes

`stickMappings` also supports `PointerArea`, `PointerRing`, `ScrollWheel`, and `Steering`. Each one first applies the shared deadzones, the response curve, and axis flipping.

| Mode | What it does |
| --- | --- |
| `PointerArea` | Remembers where the pointer is, then moves it by the stick's push times `pointerRadiusPoints`. Letting go returns the pointer to where it started. |
| `PointerRing` | Like `PointerArea`, but only the stick's angle counts, so the pointer sits on a circle of that radius. |
| `ScrollWheel` | Spinning the stick around scrolls, like a scroll wheel. Every `scrollDegreesPerLine` of turning is one line. `scrollAxis` picks across or up and down, and `rotationDirection` picks which way is positive. Part-lines are saved until a fine-grained scroll event can send them. |
| `Steering` | Spinning the stick turns a steering wheel with a limit. `steeringDegreesAtFullScale` maps the wheel to the virtual left or right stick X axis. When the stick isn't pushed all the way, the wheel turns back toward centre at `steeringReturnDegreesPerSecond`, at most 100 ms per step. |

Steering adds its own push to the virtual axis, kept apart from anything else. Swapping the profile, unplugging, losing permission, pausing, shutting down, or a failed send removes it.

Stick mappings hide their virtual axes unless `passthrough` is true. Pointer and scroll modes need permission to post events. Steering needs mapped virtual output. Edit with `ojd profile edit` or the **Stick Modes** sheet.

### Motion Lean and Steering

Tilting the controller left or right (lean) can act as a button, or as a steering wheel. A calibrated motion sample gives a lean angle with a sign, worked out from which way gravity pulls.

- Optional `motionTuning.lean` sets an on/off threshold of 1 to 89 degrees, and a smaller release margin. It gives `motion:lean:left` and `motion:lean:right` sources for bindings, chords, sequences, and layers.
- Optional `motionTuning.steering` maps lean beyond `deadzoneDegrees` to one virtual stick X axis. It reaches full push at `fullScaleDegrees`, with `responseExponent` and optional flipping. Its push is kept apart from anything else on that axis.

Lean and steering need a calibrated reading from the controller. These let go of every button and axis they hold:

- a bad or missing reading, a jump in the clock or calibration, or 100 ms with no sample
- swapping the profile or layer, resetting calibration, unplugging, pausing, shutting down, or an output failure

When the layer tuning in use changes, motion waits for a fresh starting point. Steering needs mapped virtual output. Bindings that only use lean don't. Set these fields with `ojd profile edit` or the **Motion Tuning** sheet.

### Dual-Stage Triggers

One trigger can act as two buttons: a light pull (soft) and a full pull (full), like a camera's half-press to focus. `triggerMappings` sets up each trigger once and gives `trigger:left:soft`, `trigger:left:full`, `trigger:right:soft`, and `trigger:right:full` sources.

- `softThreshold` must be below `fullThreshold`.
- `hysteresis` is taken off when letting go, and must be below the soft threshold.
- Let-go changes run before press changes.

How soft and full work together:

| Mode | Behavior |
| --- | --- |
| `Simultaneous` | Soft stays on when full turns on. |
| `Exclusive` | Full turns soft off and takes its place. |
| `PreferFull` | Soft waits `skipWindowMs`. A quick full pull gives only full. A late full pull is ignored until you let go. |
| `PreferFullCombined` | Same, but a full pull after soft has started adds full to it. |
| `ResponsivePreferFull` | Soft fires at once, a quick full replaces it, and a late full is ignored. |
| `ResponsivePreferFullCombined` | Soft fires at once, a quick full replaces it, and a late full adds to it. |

Waiting stages use the shared timer. Letting go, swapping the profile, unplugging, losing permission, pausing, shutting down, and a failed send cancel anything still waiting. A set-up trigger hides its analog virtual axis unless `passthrough` is true.

`ojd profile edit` and the **Trigger Stages** sheet change one trigger at a time. The command-line tool has no `--trigger-*` options. Not checked yet: translations, layout, keyboard navigation, VoiceOver, how it feels, and thresholds on real triggers.

### Mappings That Drive the Controller's Own Rumble and Lights

While its action is on, a button-like mapping can take over one output of the controller it came from: `Rumble`, `PlayerIndicator`, `Color`, `Brightness`, or `AdaptiveTrigger`. Each claim belongs to that exact running controller (`LogicalControllerID`). Motors, lights, or trigger sides the controller lacks fail to send. The checks accept these outputs without any virtual output. They refuse values that aren't finite or are out of range, sliding sources, and turbo.

Each output decides on its own who wins:

- The newest mapping claim wins. Releasing it brings back the one before.
- Input Test output beats mappings, as a manual override. Timed rumble hands back to the mapping when it ends. Turning the player light off, setting black, or brightness zero ends that override.
- Unplugging, losing permission, swapping, pausing, a failed send, and shutting down remove the claim. The service then tries to send an at-rest report.
- A successful send means the connection took the report, not that the motor or light reacted.

Command-line targets:

- `physical:rumble:<motor>:<0...1>`
- `physical:player:<0...4>`
- `physical:color:<red>:<green>:<blue>`
- `physical:brightness:<0...1>`
- `physical:adaptive:<left|right>:off|resistance:<start-position>:<strength>`

The app's picker offers a set list of presets, and keeps imported values that aren't on the list. DualSense USB and Bluetooth reports support off and resistance, with a valid flag for each side, a start position of 0 to 9, and a strength of 0 to 8. Bluetooth reports carry the output CRC. Still waiting on hardware: rumble, lights, adaptive triggers, report timing, and running alongside the maker's own software.

### Editing and Accessibility

Creating, updating, importing, and exporting a profile all use the same profile value and the same full-profile check. The app's editor changes a profile only through `RuntimeProfileDraft`. Imported values missing from a preset menu can still be picked. Labels and command-line help have English backup text in every shipped language. Checked outside the code: translated wording, layout at every text size, using only the keyboard, and VoiceOver order.

## Tests and What They Don't Prove

Tests built from made-up input run 256 controller sessions, each with an exact identity, through a mix of keyboard, virtual gamepad, mouse, timed, combination, and controller-output mappings. They check that all state and reference counts empty out afterward. A 10,000-input stress case keeps sequence history, chord presses, pulse timers, and turbo state from growing. A 10,000-update case checks that repeated controller-output updates replace one claim. These tests can't show real-time speed, delay, or whether games recognize the gamepad.

The software release checks are listed in `AGENTS.md`. Progress so far: [remapping status](remapping.md#status). These are checked outside the code, and never assumed from made-up reports:

- how the signed app behaves, and USB and Bluetooth delivery
- real controllers kept apart, how motion and touch feel, haptics, and adaptive triggers
- how it looks, accessibility, and translation review
- whether games recognize it, and the full delay from press to game
