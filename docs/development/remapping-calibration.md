# Remapping Calibration

See the [remapping overview](remapping.md).

## Physical Motion Conversion

`ControllerMotionSample` carries SI values only: `acceleration` in m/s² and `angularVelocity` in rad/s. Both use the canonical frame: right-handed, +X right, +Y away from the player along the face, +Z up through the face. Raw counts stay inside the drivers. Each sample carries calibration provenance and revision. Nonfinite vectors are rejected.

Each producer applies, in order: factory (or nominal) calibration, SI scaling (standard gravity 9.80665 m/s²), then its axis permutation and signs. Permutations derive from the [SDL sensor frame](https://wiki.libsdl.org/SDL3/SDL_SensorType) (X right, Y up, Z toward the player), which the canonical frame reads as (x, -z, y). `MotionFrameTests` pins each axis and sign.

The engine converts each sample once, at `RemappingMotionReading`, to degrees per second and g in the [GamepadMotion input contract][1] frame (X right, Y up, Z toward the player). Tuning, pointer scales, and calibration offsets use that frame. A level controller's acceleration points about +Y.

DualSense and Edge emit nominal readings at once: gyro ADC / 16 degrees per second and acceleration ADC / 8192 g, marked `nominalDeviceScale`. Startup requests feature report `0x05` (41 bytes). The parser accepts factory calibration in one step, only after checking ID, length, all six axes, and Bluetooth CRC32 with feature seed `0xA3`.

- Gyro: subtract bias, scale by the reported speed sum divided by endpoint range.
- Acceleration: subtract the endpoint midpoint, scale by 2 / endpoint range.
- Bounds follow the SDL PS5 code; framing and CRC follow Linux hid-playstation.
- A rejected reply keeps the previous valid calibration, or nominal conversion if none was accepted.

Stopped or replaced pipelines reject late feature replies. Hardware checks must verify delivery, framing, and axis signs.

[1]: https://github.com/JibbSmart/GamepadMotionHelpers/blob/39b578aacf34c3a1c584d8f7f194adc776f88055/GamepadMotion.hpp

### Nominal Conversion For DS4, Nintendo, and Steam

- DS4: Sony's nominal /16 gyro and /8192 accelerometer scales, as in the [SDL DS4 parser][2]. Both sensors map as (X, -Z, Y).
- Nintendo: 14.2842 counts per degree/second and 4096 counts per g, per the [SDL Switch parser][3]. Both sensors map as (-Y, X, Z) on Pro and left Joy-Con, and (Y, X, -Z) on right Joy-Con. The parser applies no horizontal-use orientation.
- Steam: gyro 2000/32768 degrees/second per count, mapped (X, -Y, Z). Accelerometer 2/32768 g per count, mapped (X, Y, Z). These are SDL's (X,Z,Y) and (X,Z,-Y), also used by Linux hid-steam. The two differ by a Y reflection, which awaits hardware confirmation.
- GameSir enhanced HID reports carry IMU bytes, but no source verifies scale, frame, or byte order. The GameSir driver publishes no motion.

All these readings are marked nominalDeviceScale, never factory calibration.

[2]: https://github.com/libsdl-org/SDL/blob/f9abf9e843cb1b9c18aa2401ceb9cfbd7a0d4c74/src/joystick/hidapi/SDL_hidapi_ps4.c
[3]: https://github.com/libsdl-org/SDL/blob/f9abf9e843cb1b9c18aa2401ceb9cfbd7a0d4c74/src/joystick/hidapi/SDL_hidapi_switch.c

## Acceptance Boundary

Signed consumer checks must separately show physical isolation, virtual recognition, and delivery, and record USB or Bluetooth, the macOS HID generation, and the consumer. Release acceptance lists each unavailable hardware check; none excuses a failing executable gate.

### DS4 Factory Calibration

DS4 startup reads USB feature report `0x02` (37 bytes). Bluetooth first reads that report to request advanced input mode, then reads calibration report `0x05` (41 bytes). Only `0x05` can install Bluetooth calibration, and it must pass CRC32 with feature seed `0xA3`.

- USB gyro endpoints are interleaved by axis. Bluetooth groups positive endpoints before negative ones.
- Gyro: subtract factory bias, multiply by `speedSum / (abs(plus - bias) + abs(minus - bias))`.
- Accelerometer: subtract the endpoint midpoint, multiply by `2 / (plus - minus)`.
- All six axes must pass the DualSense bias and scale bounds before the snapshot becomes deviceFactory.
- Malformed or unavailable replies keep the previous snapshot, initially nominal.

Layout and conversion follow the pinned SDL DS4 reference; lengths and CRC framing follow pinned Linux hid-playstation. Wireless USB dongles keep nominal calibration. Physical framing and accuracy are hardware checks.

### Nintendo Factory Calibration

Switch Pro and Joy-Con startup append SPI flash-read subcommand `0x10` for 24 bytes at `0x6020`. The parser accepts a reply only when report `0x21` has a successful acknowledgment, the matching subcommand, the exact address and length, and the complete coefficient block. Erased flash, nonpositive ranges, and malformed replies leave the prior snapshot unchanged. A valid reply installs all six axes atomically.

SDL Switch gives gyro as `(raw - gyroOffset) * 936 / (gyroSensitivity - gyroOffset)` degrees per second and accelerometer as `raw * 4 / (accelSensitivity - accelOffset)` g. Both then use the nominal axis transforms. Factory samples carry deviceFactory provenance.

Startup also requests 20 bytes from `0x8026`. A user block with little-endian magic `0xA1B2` replaces the offsets and keeps factory sensitivity, with factoryWithUserOffsets provenance.

- Reply order does not matter. User data alone cannot calibrate a sample.
- Missing magic or invalid combined ranges keep factory conversion.
- Duplicate replies are ignored. A fresh parser starts nominal. No flash writes occur.
- Physical SPI delivery and accuracy are hardware checks.

### Startup Acquisition Lifetime

- Startup plans run on the active pipeline actor.
- Each delayed startup send and calibration read re-checks the original pipeline's active state, manager identity, and competing-owner status. Cancellation exits the delay loop.
- In-flight transport calls rely on the HID backend's lifetime checks. Physical timing is unverified.
- Bluetooth Switch Pro startup omits USB handshake commands. Bluetooth DS4 feature reads include report `0x05`.

### Feature Calibration Retry Bound

- A startup feature read with a calibration consumer makes at most three attempts, 20 ms apart. Missing reports and rejected data count as failures.
- Success, cancellation, or loss of the original pipeline ends the loop. Exhaustion leaves calibration unchanged and startup continues. Reads without a consumer make one attempt.
- Synchronous IOKit reads have no timeout: startup latency is unbounded in source and not hardware-measured.
- Nintendo SPI acquisition uses the recovery path below.

### Nintendo SPI Recovery and Expiry

- After startup, the manager schedules two recovery rounds. Each follows a 200 ms reply window and re-requests only still-pending SPI reads, with the parser's current output sequence and rumble state.
- A final 200 ms window expires unanswered requests. Each address gets at most three transmissions, including startup. Pipeline stop expires pending requests at once.
- Accepted calibration stays after expiry, and late replies cannot change it. A fresh acquisition clears the temporary factory and user blocks first.
- Physical loss and timing are not verified.

### Runtime Bias Foundation

`RemappingMotionBias` is per controller. It runs after unit conversion and keeps its offset apart from calibration provenance. Manual collection uses a time-weighted mean and supports pause, reset, and explicit finite offsets.

- Automatic collection needs two seconds and at least ten samples.
- Per-axis span must be at most 0.5 degrees/second (gyro) and 0.025 g (acceleration).
- It excludes gyro components above 10 degrees/second and acceleration magnitude outside 0.8 to 1.2 g.
- Invalid, nonpositive, or greater-than-100 ms intervals clear collection but keep the learned offset.

The numbers differ from the GamepadMotionHelpers estimator, whose pinned reference defines the manual and automatic modes.

### Fusion Foundation

`RemappingMotionFusion` integrates local gyro rates into a normalized quaternion mapping the controller frame to a Y-up reference frame.

- Initial accelerometer alignment handles normal, sideways, and upside-down poses.
- Tilt correction uses an exponential 2/second response only while acceleration magnitude is between 0.8 and 1.2 g.
- Gravity is the reference down vector in controller space. Linear acceleration is measured acceleration plus gravity. Heading is relative and can drift.
- Freefall keeps an initialized orientation without gravity correction. An uninitialized freefall sample yields no result.
- Rejected without changing orientation: nonfinite values, gyro components above 1,000,000 degrees/second, acceleration components above 1,000 g, and intervals outside 0 to 100 ms.

The filter is not a numerical port of GamepadMotionHelpers. Timestamps, bias, tuning, and actions: [Remapping Motion](remapping-motion.md).
