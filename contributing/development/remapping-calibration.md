# Remapping Calibration

This page defines physical motion conversion, factory calibration, retry lifetimes, runtime bias, and fusion. Start with the [remapping overview](remapping.md).

## Physical Motion Conversion

`ControllerMotionSample` carries SI values only: `acceleration` in metres per second squared and `angularVelocity` in radians per second, in the canonical controller frame: right-handed, +X to the controller's right, +Y away from the player along the face, +Z upward through the face. A controller lying face up at rest reads about +9.81 m/s² on Z. Raw sensor counts stay inside the drivers. Each sample also carries its calibration provenance and revision. Nonfinite vectors are rejected during construction and decoding. Samples do not imply fusion.

Each producer applies raw counts, then factory (or nominal) calibration, then SI scaling (standard gravity 9.80665 m/s², SDL's `SDL_STANDARD_GRAVITY`), then its axis permutation and signs. The permutations are derived from the SDL sensor frame (X right, Y up, Z toward the player; [SDL sensor coordinates](https://wiki.libsdl.org/SDL3/SDL_SensorType)), which the canonical frame reads as (x, -z, y). Each producer's `sample` function documents its mapping and sources, and `MotionFrameTests` pins each raw axis's canonical component and sign.

The remapping engine converts each sample back once, at `RemappingMotionReading`, into degrees per second and g in the [GamepadMotion input contract][1] frame (X right, Y up, Z toward the player). Its tuning, pointer scales, and calibration offsets are expressed there, so effective sensitivity is unchanged. There, a level controller's measured acceleration points approximately +Y; fusion's physical gravity estimate points in the opposite direction.

DualSense and Edge emit immediate nominal readings: gyro ADC / 16 degrees per second, acceleration ADC / 8192 g, marked `nominalDeviceScale`. Startup requests feature report `0x05` with 41 bytes. The parser validates its ID, length, all six calibration axes, and Bluetooth CRC32 with feature seed `0xA3` before atomically accepting factory calibration. Gyro conversion subtracts bias and scales by the reported speed sum divided by endpoint range; acceleration subtracts endpoint midpoint and scales by 2 / endpoint range. Bias and sensitivity bounds follow the reviewed SDL PS5 implementation linked above. The feature-report framing and CRC follow the reviewed Linux hid-playstation implementation linked above. A rejected reply keeps the previous valid calibration, or nominal conversion if none has been accepted.

Feature-read responses reach the owning pipeline actor, serialized with parsing. Stopped or replaced pipelines reject late replies. Each read is a synchronous IOKit `IOHIDDeviceGetReport` call; OJD sets no per-request read timeout. Calibration provenance travels with each sample; immutable input capability metadata remains independent of mutable calibration state.

Constructed tests cover nominal physical units, factory bias and scale, whole-report rejection, Bluetooth feature CRC, stopped-pipeline rejection, and nonfinite decoding. Signed IOKit hardware checks must verify feature-report delivery, framing, and physical axis signs. Calibration acquisition recovery, runtime bias estimation, fusion, calibration controls, and motion output follow below.

[1]: https://github.com/JibbSmart/GamepadMotionHelpers/blob/39b578aacf34c3a1c584d8f7f194adc776f88055/GamepadMotion.hpp

### Nominal Conversion For DS4, Nintendo, And Steam

DS4 defaults to Sony's nominal /16 gyro and /8192 accelerometer scales. Sony raw axes are SDL's sensor frame, so both sensors map to the canonical frame as `(X, -Z, Y)`. The [reviewed SDL DS4 parser][2] documents these fallback scales. Its factory-report transport differences remain separate work.

Nintendo uses 14.2842 counts per degree/second and 4096 counts per g, following the [reviewed SDL Switch parser][3]. Both sensors map to the canonical frame as `(-Y, X, Z)` on Pro/left and `(Y, X, -Z)` on right Joy-Con (SDL's `(-Y, Z, -X)` and `(Y, -Z, -X)` read in the canonical frame). The parser preserves this stable hardware frame without silently applying standalone horizontal-use orientation. Every IMU sample keeps its own timestamp.

Steam uses nominal gyro scaling of 2000/32768 degrees/second per count, mapped canonical as `(X, -Y, Z)`. Its accelerometer uses 2/32768 g per count, mapped canonical as `(X, Y, Z)`. These are SDL's `(X,Z,Y)` and `(X,Z,-Y)`, which Linux `hid-steam` `steam_controller_imu_mappings` also uses. The two differ by a reflection of Y, which awaits hardware confirmation. Negation occurs after widening so the signed minimum remains representable.

GameSir enhanced HID reports carry IMU bytes, but no source verifies their scale, frame, or byte order, so the GameSir driver publishes no motion samples and does not declare motion. These readings are marked `nominalDeviceScale`; none claims factory calibration. Tests exercise signed extrema, per-family axis signs, units, all three Nintendo samples, and duplicate suppression.

[2]: https://github.com/libsdl-org/SDL/blob/f9abf9e843cb1b9c18aa2401ceb9cfbd7a0d4c74/src/joystick/hidapi/SDL_hidapi_ps4.c
[3]: https://github.com/libsdl-org/SDL/blob/f9abf9e843cb1b9c18aa2401ceb9cfbd7a0d4c74/src/joystick/hidapi/SDL_hidapi_switch.c

## Acceptance Boundary

Product tests cover parser-to-remapper-to-report behavior and lifecycle failures. Signed consumer checks must separately establish physical isolation, virtual recognition, and actual delivery. Record USB and Bluetooth, the macOS HID generation, and the consumer used. Passing report-codec tests does not establish game compatibility. Unavailable hardware checks remain explicit in release-candidate acceptance; they do not excuse failing executable gates.

### DS4 Factory Calibration

DS4 startup reads USB feature report `0x02` (37 bytes). Bluetooth first reads that report to request advanced input mode, then reads calibration report `0x05` (41 bytes). Only the latter can install Bluetooth calibration; it must pass CRC32 validation with feature seed `0xA3`. USB gyro endpoints are interleaved by axis; Bluetooth endpoints group all positive endpoints before all negative endpoints. Gyro conversion subtracts the factory bias and multiplies by `speedSum / (abs(plus - bias) + abs(minus - bias))`. Accelerometer conversion subtracts the endpoint midpoint and multiplies by `2 / (plus - minus)`. All six axes must pass the same bias and scale bounds used for DualSense before the snapshot becomes `deviceFactory`. Malformed or unavailable replies retain the previous snapshot, initially nominal.

The layout and conversion facts come from the pinned SDL DS4 reference above; report lengths and Bluetooth feature CRC framing follow the pinned Linux hid-playstation reference. Tests use different gyro gains on each axis to distinguish the two layouts, check raw-value preservation, and reject truncated or CRC-corrupted replies. Physical startup framing and measured calibration accuracy remain hardware checks. Wireless USB dongles retain nominal calibration rather than claiming factory coefficients; these tests cover direct USB and Bluetooth DS4 connections.

### Nintendo Factory Calibration

Switch Pro and Joy-Con startup append SPI flash-read subcommand `0x10`, requesting 24 bytes from address `0x6020`. The parser accepts a pending reply only when report `0x21` contains a successful acknowledgment, the matching subcommand, the exact address and length, and the complete coefficient block. Erased flash, nonpositive coefficient ranges, and malformed replies leave the prior snapshot unchanged. A valid reply installs all six axes atomically and consumes the pending request. Calibration replies do not advance the motion clock or emit sensor samples.

The pinned SDL Switch reference above defines gyro conversion as `(raw - gyroOffset) * 936 / (gyroSensitivity - gyroOffset)` degrees per second and accelerometer conversion as `raw * 4 / (accelSensitivity - accelOffset)` g. Both then use the same canonical axis transforms as nominal readings. Factory-derived samples carry `deviceFactory` provenance and preserve all raw readings. Tests cover all three layouts and all three samples per report, nonzero offsets, unrelated addresses, negative acknowledgments, truncation, and erased flash. Startup also requests 20 bytes from `0x8026`. A user block with little-endian magic `0xA1B2` replaces the accelerometer and gyro offsets while retaining factory sensitivity coefficients. The combined snapshot carries `factoryWithUserOffsets` provenance. Either reply order works; user data alone cannot calibrate a sample. Missing magic or invalid combined ranges preserve factory conversion. Completed requests ignore duplicate replies, and a new parser starts with nominal conversion. Tests cover both reply orders, changed accelerometer sensitivity, gyro zero-rate correction, invalid user ranges, and provenance serialization. Physical SPI delivery and calibration accuracy remain hardware checks. No flash writes occur.

### Startup Acquisition Lifetime

HID output startup plans are generated on the active pipeline actor, serializing parser packet numbers and calibration request state with input parsing. Each delayed startup send checks the original pipeline's active state, current manager identity, and competing-owner status after its delay. Reusing a physical location or identifier does not authorize the old pipeline's remaining commands. Cancellation exits the delay loop. Feature calibration reads also check that lifetime before reading and before delivering the response. Tests cover inactive plan generation, ownership loss, replacement with identical device identity, and manager shutdown. Transport calls already in flight still rely on the HID backend's client-lifetime checks; physical timing is unverified.

Transport-specific startup methods are protocol requirements with default implementations. This preserves dynamic dispatch through parser-provider existentials: Bluetooth Switch Pro startup omits USB handshake commands, and Bluetooth DS4 feature reads include report `0x05`. Regression tests exercise the pipeline/protocol call path in addition to concrete parser calls.

### Feature Calibration Retry Bound

Startup feature reads with a calibration consumer make at most three attempts per request, separated by 20 ms. Missing reports and rejected calibration data both count as failed attempts. Success ends the retry loop; cancellation or loss of the original active pipeline ends acquisition. Each attempt checks the pipeline before the read and before delivering its response. Exhaustion leaves parser calibration unchanged and continues startup. Reads without a calibration consumer retain their existing single-attempt behavior. OJD sets no per-request timeout on these synchronous IOKit reads, so startup latency has no source-level bound and is not hardware-measured. Nintendo SPI output/reply acquisition uses the separate recovery path below.

### Nintendo SPI Recovery And Expiry

After the initial startup sequence, the manager schedules two recovery rounds, each following a 200 ms reply window. Each round asks the active pipeline actor for only its still-pending SPI reads; generated packets use the parser's current output sequence and rumble state. Reports in a round retain the transport startup interval. A final 200 ms window then expires unanswered requests. Each calibration address receives at most three transmissions, including startup. Every delayed send checks the original pipeline lifetime. Pipeline stop also expires pending requests immediately. Accepted calibration remains installed after expiry, while late replies cannot change it. A new explicit acquisition clears the temporary factory/user blocks before collecting new replies. Tests cover partial success, packet sequence advancement, late-reply rejection, fresh acquisition, and stop/restart without reopening old requests. This bounded software recovery policy does not verify physical loss or timing behavior.

### Runtime Bias Foundation

`RemappingMotionBias` is a native, per-controller calculation component integrated with the motion engine. It operates after physical-unit conversion and keeps its offset separate from factory/user calibration provenance. Manual collection uses a time-weighted mean, supports pause, reset, and explicit finite offsets. Automatic collection initially requires two seconds and at least ten samples, with per-axis gyro span at most 0.5 degrees/second and acceleration span at most 0.025 g. It excludes gyro components above 10 degrees/second and acceleration magnitude outside 0.8–1.2 g. Invalid, nonpositive, or greater-than-100 ms intervals clear collection without discarding the learned offset. Collection state has fixed storage and bounded duration/count.

This is an independent implementation of the calibration capability, not numerical parity with GamepadMotionHelpers' adaptive stillness/sensor-fusion estimator. The pinned reference defines manual and automatic modes and remains the behavioral comparison source. Sensor-fusion bias correction, orientation processing, profile tuning, and live remapping use this component through the processing path below. Tests cover stationary bias, changing motion, acceleration, timing gaps, time-weighted manual collection, pause/reset, and invalid offset rejection.

### Fusion Foundation

`RemappingMotionFusion` integrates local gyro rates into a normalized quaternion mapping the controller frame to a Y-up reference frame. Initial accelerometer alignment handles normal, sideways, and upside-down poses. Subsequent tilt correction uses an exponential 2/second response only while acceleration magnitude is between 0.8 and 1.2 g. Gravity is the reference down vector rotated into controller space; linear acceleration is measured acceleration plus that gravity. Heading is relative and can drift. Freefall preserves initialized orientation without gravity correction, while an uninitialized freefall sample produces no fused result.

Invalid/nonfinite inputs, gyro components above 1,000,000 degrees/second, acceleration components above 1,000 g, and intervals outside 0–100 ms are rejected without changing orientation. These large numeric bounds prevent arithmetic overflow; they do not certify plausible physical motion. Synthetic tests cover 90-degree yaw and pitch, gravity removal, upside-down initialization, freefall, high-acceleration tilt rejection, reset, and invalid/gap state preservation. This native complementary filter is not a numerical port of GamepadMotionHelpers. Per-device timestamps, bias, profile tuning, and motion actions integrate through the processing path below.
