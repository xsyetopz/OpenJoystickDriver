# Advanced Remapping Controls

See the [remapping overview](remapping.md).

## Angular Stick Modes

Native `stickMappings` entries select the left or right stick.

- Aim integrates radial stick strength into angular travel at `aimDegreesPerSecond`. It stops at center and caps delayed integration at 100 ms per update. `pointerPointsPerDegree` converts travel to logical screen points.
- Flick starts a timed turn when the stick crosses the radial threshold, then follows rotation around the rim. `FlickOnly` omits rim rotation. `RotateOnly` omits the initial turn.
- The initial angle is clockwise from forward. Rim rotation follows the shortest angular difference across the rear seam.
- A centered stick finishes its pending flick through the shared scheduler. Disconnects and profile replacement cancel pending travel.

The CLI has no stick options. Edit `stickMappings` with `ojd profile edit <profile>`, or export, change, and import the profile. Validation requires:

- inner and outer radial deadzones that sum to less than one
- flick hysteresis smaller than the threshold

A mapped stick suppresses its original virtual axes. Explicit axis bindings still run. Angular modes need system-input access. The **Stick Modes** sheet edits both sticks and validates both drafts before applying. **Reset** turns off the selected mapping. Not validated: layout, keyboard navigation, VoiceOver, translations, and physical feel.

### Area, Ring, Scroll, and Steering Stick Modes

`stickMappings` also supports `PointerArea`, `PointerRing`, `ScrollWheel`, and `Steering`. All apply the shared radial deadzones, response exponent, and axis inversion first.

- `PointerArea` anchors at the current pointer and offsets it by the stick vector times `pointerRadiusPoints`. `PointerRing` uses the stick angle and the same radius. Centering returns to the anchor.
- `ScrollWheel` converts the shortest angular movement between deflected samples to scroll lines with `scrollDegreesPerLine`. `scrollAxis` selects horizontal or vertical. `rotationDirection` sets the positive rotation. Fractional lines carry until a high-resolution scroll event can emit them.
- `Steering` accumulates angular travel into a bounded wheel angle. `steeringDegreesAtFullScale` maps it to the virtual left or right stick X axis. Below full deflection, `steeringReturnDegreesPerSecond` unwinds toward neutral on monotonic time, capped at 100 ms per step.

Steering owns one independent virtual-axis contribution. Replacement, disconnect, permission loss, suspension, shutdown, or failed delivery removes it.

Stick mappings suppress their virtual axes unless `passthrough` is true. Pointer and scroll modes need post-event access. Steering needs mapped virtual output. Edit with `ojd profile edit` or the **Stick Modes** sheet.

### Motion Lean and Steering

A calibrated motion sample yields signed controller lean from its acceleration vector. Optional `motionTuning.lean` sets a digital threshold of 1 to 89 degrees and a smaller release hysteresis. It supplies `motion:lean:left` and `motion:lean:right` sources to bindings, chords, sequences, and layers. Optional `motionTuning.steering` maps lean outside `deadzoneDegrees` to one virtual stick X axis, reaching full scale at `fullScaleDegrees`, with `responseExponent` and optional inversion. It owns an independent virtual contribution.

Lean and steering need a calibrated physical reading. These events clear digital and virtual ownership:

- an invalid or missing reading, a clock or calibration discontinuity, or a 100 ms sample timeout
- profile or layer replacement, calibration reset, disconnect, suspension, shutdown, or output failure

A change of effective layer tuning needs a fresh baseline. Steering needs mapped virtual output. Lean-only bindings do not. Set these fields with `ojd profile edit` or the **Motion Tuning** sheet.

### Dual-Stage Triggers

`triggerMappings` configures each physical trigger once and exposes `trigger:left:soft`, `trigger:left:full`, `trigger:right:soft`, and `trigger:right:full` sources. `softThreshold` must be below `fullThreshold`. `hysteresis` is subtracted on release and must be below the soft threshold. Release transitions run before press transitions.

Interaction modes:

- `Simultaneous`: soft stays active when full activates.
- `Exclusive`: full releases and replaces soft.
- `PreferFull`: soft waits for `skipWindowMs`. A quick full pull selects full only. A late full pull is ignored until release.
- `PreferFullCombined`: same, but a full pull after committed soft joins it.
- `ResponsivePreferFull`: soft emits at once, a quick full replaces it, and a late full is ignored.
- `ResponsivePreferFullCombined`: immediate soft, quick replacement, and late combination.

Buffered stages use the shared monotonic scheduler. Release, profile replacement, disconnect, permission loss, suspension, shutdown, and delivery failure cancel pending deadlines. A configured trigger suppresses its analog virtual axis unless `passthrough` is true.

`ojd profile edit` and the **Trigger Stages** sheet change one trigger at a time. The CLI has no `--trigger-*` options. Not validated: translations, layout, keyboard traversal, VoiceOver, physical feel, and real trigger thresholds.

### Mapping-Owned Physical Output

A discrete destination can own one source-controller output channel while its action is active: `Rumble`, `PlayerIndicator`, `Color`, `Brightness`, or `AdaptiveTrigger`. Each claim is scoped to the exact runtime `LogicalControllerID`. Unsupported motors, lights, or trigger sides fail delivery. Validation accepts physical destinations without virtual output and rejects non-finite or out-of-range values, continuous sources, and turbo.

Channels arbitrate independently.

- The most recent mapping claim wins. Releasing it restores the previous claim.
- Input Test output is a higher-priority manual override. Timed rumble restores mapping output when it expires. An off player indicator, black color, or zero brightness releases the matching override.
- Disconnect, permission loss, replacement, suspension, failed delivery, and shutdown remove ownership. The service then tries to send a neutral report.
- Successful delivery means the transport accepted the report, not that the actuator responded.

CLI targets:

- `physical:rumble:<motor>:<0...1>`
- `physical:player:<0...4>`
- `physical:color:<red>:<green>:<blue>`
- `physical:brightness:<0...1>`
- `physical:adaptive:<left|right>:off|resistance:<start-position>:<strength>`

The native picker has bounded presets and keeps imported values outside that list. DualSense USB and Bluetooth reports support off and resistance, with side-specific validity flags, a start position of 0 to 9, and a strength of 0 to 8. Bluetooth reports carry the output CRC. Hardware gates: rumble, lighting, adaptive triggers, report timing, and coexistence with vendor software.

### Authoring and Accessibility Coverage

Profile create, update, import, and export share one profile value and one complete-profile validation path. The native editor uses `RuntimeProfileDraft` as its only mutation boundary. Imported values missing from a preset menu stay selectable. Labels and CLI help have English fallback entries in every shipped locale. External gates: translated wording, layout at every text size, keyboard-only workflow, and VoiceOver order.

## Integration and Release Evidence

Constructed integration tests run 256 exact-identity controller sessions through mixed keyboard, virtual-gamepad, mouse, timed, combination, and physical destinations, and verify that state and reference counts drain. A 10,000 input-cycle stress case bounds sequence history, chord presses, pulse deadlines, and turbo state. A 10,000-update case verifies that repeated physical-output updates replace one owner claim. They do not show real-time guarantees, latency, or consumer recognition.

The software release gate is listed in `AGENTS.md`. Milestone state: [remapping status](remapping.md#status). These stay external gates and are never inferred from constructed reports:

- signed-runtime behavior and USB and Bluetooth delivery
- physical isolation, motion and touch feel, haptics, and adaptive triggers
- visual and accessibility quality, and translation review
- consumer recognition and end-to-end latency
