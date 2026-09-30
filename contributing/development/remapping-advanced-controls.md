# Advanced Remapping Controls

This page defines angular, area, ring, scroll, steering, lean, and trigger modes plus mapping-owned physical output and release evidence. Start with the [remapping overview](remapping.md).

## Angular Stick Modes

Native `stick_mappings` entries select the left or right stick. Aim integrates radial stick strength into angular travel at `aim_degrees_per_second`; `pointer_points_per_degree` converts that travel to logical screen points. Positive stick Y moves the pointer upward. Flick starts a smooth timed turn when the stick crosses the radial threshold, then follows rotation around the rim. `flick_only` omits rim rotation; `rotate_only` omits the initial turn. The initial angle is clockwise from forward, and rim rotation follows the shortest angular difference across the rear seam. A centered stick finishes its pending flick through the shared scheduler. Disconnects and profile replacement cancel pending travel. Aim stops at center and caps delayed integration at 100 ms per update.

Create or update one stick per CLI command:

```sh
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless map update \
  Desktop --stick-source right --stick-mode flick \
  --stick-pointer-points-per-degree 4 --stick-flick-duration-ms 100
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless map update \
  Desktop --stick-source left --stick-mode aim \
  --stick-aim-degrees-per-second 360 --stick-inner-deadzone 0.1
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless map update \
  Desktop --stick-source right --stick-mode none
```

Unspecified fields retain their current values, and edits preserve the other stick. `none` removes the selected mapping and cannot be combined with tuning options. Radial inner and outer deadzones must sum to less than one; response exponent shapes normalized radial strength. `--stick-invert-x` and `--stick-invert-y` accept `true` or `false`. Flick threshold and hysteresis control engagement and rearming; hysteresis must be smaller than the threshold.

A mapped stick suppresses its original virtual axes. Explicit axis bindings still run, allowing additional destinations; this does not hide the physical controller from other processes. Angular stick modes require system-input access. The profile editor’s Stick modes sheet edits both sticks, preserves hidden mode settings, and validates both drafts before applying them. Reset disables the selected stick mapping; Cancel discards sheet edits. Rendered layout, keyboard navigation, VoiceOver, translated labels/help, and physical feel/direction validation remain pending.

### Area, Ring, Scroll, And Steering Stick Modes

The `stick_mappings` contract also supports `pointer_area`, `pointer_ring`, `scroll_wheel`, and `steering`. All modes apply the shared radial inner/outer deadzones, response exponent, and axis inversion before their mode-specific calculation. `pointer_area` captures the current pointer as its activation anchor and places the pointer relative to that anchor by the transformed stick vector and `pointer_radius_points`. `pointer_ring` uses the transformed stick angle and the same fixed logical-point radius. Centering either mode returns to the anchor. No absolute display coordinates or display geometry are stored in a profile.

`scroll_wheel` measures the shortest angular movement between consecutive deflected samples. `scroll_degrees_per_line` converts accumulated travel to logical scroll lines while retaining a bounded sub-line remainder; `scroll_axis` selects horizontal or vertical output. `rotation_direction` defines which physical rotation is positive. Centering drops the previous angle, so re-engagement cannot manufacture travel across a gap. System-event delivery retains fractional line displacement until it can emit a high-resolution scroll event.

`steering` accumulates shortest angular travel into a bounded wheel angle. `steering_degrees_at_full_scale` maps that angle to the selected virtual left- or right-stick X axis. While the stick is not fully deflected, `steering_return_degrees_per_second` unwinds toward neutral using monotonic time, with each delayed step capped at 100 ms. The shared scheduler keeps return active without controller reports. The mapping owns one independent virtual-axis contribution; replacement, disconnect, permission loss, suspension, shutdown, or failed delivery removes it immediately without disturbing other contributors.

Stick mappings suppress their physical virtual axes unless `passthrough` is true. Pointer and scroll modes require post-event access; steering requires mapped virtual output. CLI create/update accepts the `--stick-pointer-radius-points`, `--stick-scroll-*`, `--stick-rotation-direction`, `--stick-steering-*`, and `--stick-passthrough` options documented by `map help`. The native Stick modes sheet exposes the same values and retains hidden mode settings while switching modes.

### Motion Lean And Steering

An accepted calibrated motion sample derives signed controller lean from its acceleration vector. Optional `motion_tuning.lean` defines a 1–89 degree digital threshold and a smaller release hysteresis. It supplies typed `motion:lean:left` and `motion:lean:right` sources through the normal binding, chord, sequence, layer, consumption, and lifecycle paths. Optional `motion_tuning.steering` maps lean outside `deadzone_degrees` to one virtual stick X axis, reaches full scale at `full_scale_degrees`, applies `response_exponent`, and may invert direction. It owns an independent virtual contribution rather than replacing other mapped contributors.

Motion lean and steering require a calibrated physical reading. Invalid or missing readings, clock/calibration discontinuity, a 100 ms sample timeout, profile/layer replacement, calibration reset, disconnect, suspension, shutdown, or output failure clears digital and virtual ownership. Changing effective layer tuning requires a fresh baseline. Motion steering requires mapped virtual output; lean-only bindings do not. CLI uses `--motion-lean*` and `--motion-steering-*`; the native Motion tuning sheet authors the same fields.

### Dual-Stage Triggers

`trigger_mappings` configures each physical trigger once and exposes typed `trigger:left:soft`, `trigger:left:full`, `trigger:right:soft`, and `trigger:right:full` sources. Thresholds are normalized trigger values. `soft_threshold` must be below `full_threshold`; `hysteresis` is subtracted on release and must be below the soft threshold. The engine evaluates release transitions before press transitions so exclusive full pulls cannot overlap the soft action accidentally.

Interaction modes:

- `simultaneous`: soft remains active when full activates.
- `exclusive`: full releases and replaces soft.
- `prefer_full`: soft waits for `skip_window_ms`; a quick full pull selects full only, while a late full pull is ignored until release.
- `prefer_full_combined`: the same quick-pull selection, but a full pull after committed soft joins it.
- `responsive_prefer_full`: soft emits immediately, a quick full replaces it, and a late full is ignored.
- `responsive_prefer_full_combined`: immediate soft, quick replacement, and late combination.

Buffered stages use the controller's monotonic shared scheduler; no per-mapping timer is created. Release, profile replacement, disconnect, permission loss, suspension, shutdown, and delivery failure cancel pending deadlines and release both stage sources. A configured trigger suppresses its analog virtual axis unless `passthrough` is true; explicit ordinary axis bindings still run. The CLI `--trigger-*` options and native Trigger stages sheet create, update, and remove one trigger configuration at a time. Every mutation validates the complete schema-3 profile, so a stage source cannot outlive its trigger configuration.

Focused coverage distinguishes anchor return, shortest-angle wrap, fractional scroll accumulation, steering unwind and ownership cleanup, motion timeout and profile replacement, trigger ordering, all quick/late full-pull policies, shared deadlines, passthrough, schema round trips, CLI parsing, and native draft validation. The new catalog keys have English fallback text in every shipped locale; translation review remains external. Native visual layout, keyboard-only traversal, VoiceOver announcements, physical pointer/scroll/steering feel, motion direction, and real trigger threshold behavior remain external gates and are not established by constructed tests.

### Mapping-Owned Physical Output

A discrete destination may own one source-controller output channel while its action is active: `rumble`, `player_indicator`, `color`, `brightness`, or `adaptive_trigger`. Each claim is scoped to the exact runtime `DeviceIdentifier`; a stale claim cannot select another controller of the same model or a replacement at a new session location. Unsupported motors, lights, or trigger sides fail delivery instead of being emulated. Profile validation accepts physical destinations without requiring virtual output, rejects non-finite or out-of-range normalized values, and prohibits continuous sources and turbo.

Channels arbitrate independently. The most recently activated mapping claim wins and releasing it restores the preceding active claim. Input Test output is a higher-priority manual override: timed rumble restores mapping output when its bounded timer expires, while an off player indicator, black color, or zero brightness releases the corresponding manual override. Disconnect, permission loss, pipeline replacement, profile replacement, suspension, failed remapping delivery, and shutdown remove mapping ownership and attempt a neutral report before transport teardown. Successful delivery means the supported transport accepted its report, not that the physical actuator or light responded.

CLI targets use `physical:rumble:<motor>:<0...1>`, `physical:player:<0...4>`, `physical:color:<red>:<green>:<blue>`, `physical:brightness:<0...1>`, and `physical:adaptive:<left|right>:off|resistance:<start-position>:<strength>`. The native destination picker includes bounded presets and preserves imported values outside that preset list. DualSense USB and Bluetooth reports implement off and resistance effects with side-specific validity flags, bounded 0–9 start position, bounded 0–8 strength, and the Bluetooth output CRC. Physical rumble, lighting, adaptive-trigger behavior, report timing, and coexistence with vendor software remain hardware gates; catalog text is present in every locale with translation review pending.

### Authoring And Accessibility Coverage

Profile create, update, import, and export all use the same schema-3 value and complete-profile validation path. The authenticated RPC transports that value without field-specific reconstruction. CLI binding, layer, chord, sequence, action-collection, touch, motion, stick, trigger, Joy-Con pair, and physical-output grammars preserve unspecified values and reject an invalid complete result. The renderer emits parseable physical destinations, including exact normalized adaptive-trigger parameters.

The native editor exposes the same profile sections and uses `RuntimeProfileDraft` as its sole mutation boundary. Physical destinations have reusable typed controls for motor, intensity, player indicator, RGB channels, brightness, trigger side, effect, resistance start, and strength; they are available to ordinary and layer assignments, additional and alternate actions, chords, and sequences. Imported values not present in the convenience preset menu remain selectable and editable. Native labeled `Picker` and `Slider` controls retain keyboard traversal and accessible values. Profile option catalogs and physical value controls are split from the profile draft so the draft remains responsible only for validated mutations.

All new labels and CLI help have English fallback entries in every shipped locale. This establishes catalog completeness, compilation, round-trip behavior, and programmatic accessibility labels. Translated wording, layout at every text size, keyboard-only workflow quality, and VoiceOver announcement order remain external review gates.

## Integration And Release Evidence

Constructed integration coverage runs 256 exact-identity controller sessions through mixed keyboard, virtual-gamepad, mouse, timed, combination, and mapping-owned physical destinations, then verifies that controller state and shared output reference counts drain completely. A 10,000 input-cycle stress case bounds sequence history, deferred sequences, chord presses, pulse deadlines, and turbo state by the active profile. A separate 10,000-update physical-output case verifies that repeated channel updates replace one owner claim rather than accumulating claims.

Focused routing and lifecycle suites additionally cover profile replacement, permission loss, suspension, delivery failure, disconnect, paired-session replacement, virtual report aggregation, motion discontinuities, scheduled steering and trigger work, and manual-versus-mapping physical output arbitration. These tests establish deterministic ownership and storage bounds; they do not establish hard real-time guarantees, physical latency, actuator response, or consumer recognition.

The software release gate is the repository's catalog, profile, and schema contracts, direct standard-tool checks, DriverKit generation, macOS 14 parser, complete Swift test, and whitespace checks listed in `AGENTS.md`. Milestone state: [remapping status](remapping.md#status). Signed-runtime behavior, supported-controller USB and Bluetooth delivery, physical isolation, motion and touch feel, haptics and adaptive triggers, native visual and accessibility quality, translation review, consumer recognition, and end-to-end latency remain external gates and must be recorded as observations rather than inferred from constructed reports.
