# Remapping Motion Processing

See the [remapping overview](remapping.md).

## Per-Device Motion Processing

Each RemappingDeviceState processor integrates samples in sample-relative nanoseconds, independent of delivery time, and keeps the latest corrected gyro, fused orientation, gravity, linear acceleration, and interval. Units: [Remapping Calibration](remapping-calibration.md).

- Duplicate or backward sequence indices, backward or repeated sample times do not advance state.
- Gaps above 100 ms, clock-basis or tick-unit changes, and calibration-provenance changes reset bias and orientation and set a zero-duration baseline.
- Out-of-range readings clear estimates. The next valid sample sets a fresh baseline.

Controller release, profile replacement, and engine drain discard processor state. Sony and Nintendo readings carry a session-local calibration revision, advanced by changed coefficients or provenance (not by identical accepted coefficients or rejected replies). A revision change resets estimates. A reading without it fails to decode.

The CLI and the authenticated application service run manual bias calibration:

```text
ojd controller calibrate <controller> [start|pause|reset]
```

`<controller>` is an ID from `ojd controller list` or a VVVV:PPPP model. Without an action, it prints the calibration. With `--json`, each operation returns `controller`, `calibrated`, `collecting`, and `offsetDegreesPerSecond` (X/Y/Z). Action `sticks` with `--step <rest|circle|triggers|gyro>` measures stick centres, ranges, trigger ends, and gyro, and stores them for the controller's model.

- start: needs an eligible remapping route with a valid motion baseline. Keep the controller still.
- pause: stops manual collection, keeps the offset. Automatic collection can continue if the profile enables it.
- reset: clears motion estimates and stored stick values, then waits for a fresh baseline.

Disconnect, profile replacement, invalid samples, and clock or calibration discontinuities cancel collection. Calibration changes no factory coefficients and stores no profile offset. The engine rejects commands from an earlier mapping session.

The input-test window's **Motion Calibration** panel has **Refresh**, **Start Calibration**, **Pause**, and **Reset**, using the same router commands. It shows collection state and X/Y/Z bias in degrees per second. Closing it does not stop collection. Not verified: native visual and VoiceOver checks and calibration translations.

### Gyro Coordinate Projections

Codable RemappingMotionSpace offers three projections:

- Local: controller X pitch and Y yaw.
- Player: local pitch, with Y/Z gyro combined around gravity. Default yaw relaxation is 1.41, capped by the combined Y/Z rate.
- World: yaw from gyro projected onto reference up. Pitch from the pitch axis projected onto the gravity plane. Default 0.125 side-reduction threshold suppresses unstable pitch near a sideways pose; exact side alignment returns zero.

Projections yield degrees per second from normalized gravity. The native motion-action layer applies pointer sign, sensitivity, smoothing, and output mapping. Player and world formulas come from the pinned MIT GamepadMotionHelpers reference; [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) keeps its notice, and release packaging must ship it.

### Motion Tuning Contract and Transform

Codable RemappingMotionTuning defaults omitted fields and rejects nonfinite and out-of-range values. It sets projection, inversion, automatic bias, player yaw relaxation, world side reduction, and these ranges:

- pitch and yaw sensitivity: 0 to 100
- smoothing half-time: 0 to 1000 ms
- radial rate threshold: 0 to 1000 degrees/second
- gravity correction rate: 0 to 100 per second

The transform applies the radial threshold, time-based exponential smoothing, then sensitivity and inversion. The same tuning feeds bias, fusion, and projection. A change resets processing and filter history.

Non-default tuning is stored under `motionTuning`, set with `ojd profile edit` or `ojd profile set`. The profile editor's **Motion Tuning** sheet blocks saving invalid text. Labels have draft translations. Not verified: which catalogs still use English motion labels, native-language review, native visual and accessibility checks.

### Gyro Output and Activation

Profiles accept `gyroOutput` (off if omitted). Modes: Disabled, Mouse, LeftStick, RightStick. Stick modes need a virtual gamepad output policy; Mouse needs system-input permission. Set `gyroOutput.mode`, `gyroOutput.pointerPointsPerDegree`, and `gyroOutput.fullStickDegreesPerSecond` the same way.

Mouse output integrates sample intervals into screen-point deltas. Stick output divides angular speed by the full-stick speed, clamps each axis, and joins the gamepad contribution accumulator. A 100 ms sample timeout or reset calibration removes only the gyro contribution. Delivery failure follows fail-closed recovery.

Activation modes: Always (no source), WhileHeld, WhileReleased, Toggle. Set `gyroOutput.activationMode` and `gyroOutput.activationSource`. A source is a button, D-pad direction, or axis direction; continuous axes are rejected.

- Enabling starts with a fresh sample baseline. Disabling removes the gyro stick contribution at once.
- While gyro output is on, OJD suppresses the control's original virtual contribution. To pass an unmapped activation control through, set `gyroOutput.consumesActivationSource` to false or turn off the native suppression toggle.
- An axis-direction activator reserves its parent virtual axis.

Not verified: physical motion direction, keyboard navigation, VoiceOver. Gyro editor labels need translation.

Trackball settings are under `gyroOutput.trackball` (`source`, `axes`, `decayHalvingsPerSecond`, `consumesSource`), set the same way. Defaults: both axes, one halving per second, source suppressed. Zero decay keeps velocity constant. Not verified: rules for partial updates and for removing the trackball.

While the source is held, selected axes use the last accepted angular velocity, not live motion (JSM averages the last 125 ms). Mouse travel uses the analytical decay integral. Sticks use the decayed velocity. Gaps clear retained motion. Not verified: translation, native review, and physical feel.

### Layer Motion Overrides

A layer may hold a `motionTuning` object; the latest activated layer with one supplies the whole value. Releasing or toggling off a layer restores the earlier override, else the profile tuning. A tuning change removes the gyro stick contribution and clears retained trackball motion, calibration collection, and the motion baseline. Output resumes after a fresh baseline.

Edit a layer's tuning with `ojd profile edit <profile>` (no CLI tuning options); remove it to restore inheritance. Each native layer row has a **Motion Tuning** button; **Use Profile Tuning** in the sheet removes the override. Not verified: native rendering, keyboard navigation, VoiceOver, and translations.
