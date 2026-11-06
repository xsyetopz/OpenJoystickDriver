## Context

This change is planning only: it holds specs and tasks, no code. Most tasks are evidence gathering that must finish before the code tasks start.
Sources read for this plan: the code at the paths below; SDL `release-3.4.16` `SDL_hidapi_switch2.c` and `usb_ids.h`; the README of `caqlayan/procon2-mac` (branch `master`, license MIT through the GitHub API) read 2026-10-25. The source files of `procon2-mac` and the BlueRetro project it cites were not read.
No Switch 2 controller is in hand for this plan. Testers receive tester builds (`docs/development/tester-builds.md`).

## Research claims checked against the code and the sources

| Claim | Verdict | Evidence |
| --- | --- | --- |
| OJD uses input report `0x05`; procon2-mac uses `0x09`. | Confirmed, and wider than an ID. | `Switch2Driver.swift:4` and the guard at `:380` accept `0x05` only, 64 bytes or more; buttons are bytes 5 to 8, sticks start at 11 and 14. The README lists `0x09` with buttons in payload bytes 2 to 4 (absolute 3 to 5) and sticks at payload 5 to 10 (absolute 6 to 11). These are different layouts, not one layout under two IDs. SDL checks no ID byte (`size < 64` only) and reads buttons at 5 to 8. The README also says the HID descriptor declares a standard Game Pad collection of 21 buttons and 12-bit axes with the D-pad as buttons, which fits `0x09` being the descriptor-declared report and `0x05` the vendor report; that is a hypothesis for the capture, not a finding. |
| The Bluetooth LE layout differs from OJD's one table (bit order, sticks at [10] to [15]). | Corrected. | The hub prepends `0x05` to each notification (`Switch2BluetoothLEHub.swift:137-150`), so notification bytes 4 to 7 are OJD's bytes 5 to 8 and notification bytes 10 to 15 are OJD's 11 to 16. The README's "differs from the BLE layout" compares its own USB `0x09` button measurement with BLE; it does not compare BLE with OJD's table. The positions agree. Whether the bit order of the BLE buttons matches OJD's table is unverified and is a capture task. |
| Rumble cadence is 4 ms in procon2-mac, 12 ms in OJD. | Confirmed, not a fault. | `nintendo-switch2.json` `keepAlive.intervalMilliseconds` is 12 and a test pins it (`Switch2DriverTests.swift:206`); SDL has `#define RUMBLE_INTERVAL 12`. The README says USB frames stream "every ~4ms" and the BLE pass-through polls every 8 ms. Different consumers feed different frame sources; whether a shorter interval improves feel or only adds traffic is a measurement (H5). |
| Output report `0x02` with the `0x50` counter byte and the second actuator copy. | Agrees. | The README places the counter at payload byte 0 and the right actuator at payload 16 to 21; OJD writes `0x50` combined with the sequence at byte 1 and the copy at byte `0x11` (`Switch2Driver.swift:328-340`), the same offsets with the ID at byte 0. |
| The IMU is not decoded. | Confirmed. | `Switch2Driver.swift:92` says so. SDL decodes it: sensor timestamp at bytes `0x2B` to `0x2E` (32-bit), accelerometer at `0x31`, `0x33`, `0x35`, gyroscope at `0x37`, `0x39`, `0x3B` (16-bit little-endian each), with flash bias and a rate-dependent gyro coefficient (34.8 or 40.0) chosen after five samples. The README puts the IMU at payload byte 22 on `0x09`, which is another layout. |
| PIDs: `2069` Pro 2, `2073` GameCube, `2066`/`2067` Joy-Con 2. | Confirmed with sides. | Records exist for all four. SDL `usb_ids.h`: `2067` Joy-Con left, `2066` Joy-Con right, `2068` Joy-Con pair, `2069` Pro, `2073` GameCube. OJD maps `2066` to `JoyConRight`, `2067` to `JoyConLeft`, `2073` to `GameCube`, and `2069` to the family default with no `layout`. There is no record for `2068`. |

## Decisions

### D1 Evidence before code

No decoder change lands before the captures of tasks 2.x exist. A capture is a text fixture of raw reports with the controller, firmware if known, transport, the action performed and the time. Fixtures come from the app's packet capture, after task 1.1 confirms that it records every report ID of the interface (the driver ignores unknown IDs, and a capture that drops them would hide `0x09`).

### D2 Report identification

The outcome table of task 2.4 decides:

| Capture shows | Driver does |
| --- | --- |
| Only `0x05` on USB and Bluetooth LE | Keep `0x05`; the README's `0x09` belongs to another firmware or transport; record both in the doc. |
| Both `0x05` and `0x09` on USB | Decode `0x05`; ignore `0x09` explicitly; the doc names both and why. |
| Only `0x09` on USB | Decode `0x09` with its own table in the description; `0x05` is removed unless Bluetooth LE sends it. |

Either way the driver does not guess from content, and an unknown report ID is ignored without changing state (existing behavior, pinned by `rejectsShortReportsAndOtherReportIDs`).

### D3 Bluetooth LE layout

Use the captures of tasks 2.2 and 2.3 to compare the bit for each button and both sticks. A per-transport table is added to the description only for a bit that differs; the one table stays otherwise.

### D4 IMU

After D2 and D3 settle the layout, decode accelerometer and gyroscope with the flash bias and the sensor timestamp, following the facts in the table above (SDL, zlib; the code is written to the repository's motion path used by the Steam Triton driver, which converts a hardware counter into sample time). Units and axis signs follow the other drivers; the Joy-Con left and right orientation swaps are taken from the capture, not copied. Which flash addresses hold the bias is read from the pinned SDL source in task 4.1. A report whose sensor timestamp is zero carries no sample.

### D5 Rumble cadence

The interval stays description data. It changes only if H5 shows a better result at another value, and the test that pins 12 ms changes with it.

### D6 Licenses

OJD is licensed under PolyForm Noncommercial 1.0.0 with a commercial license, so GPL code cannot be ported. SDL (zlib) and `procon2-mac` (MIT) code may be used with its notice kept in `THIRD_PARTY_NOTICES.md`. Only the README of `procon2-mac` was read for this plan.

## Risks

- Reading the wrong report ID silently freezes input. The capture tasks and an explicit fixture per report prevent it.
- IMU decoding with the wrong gyro coefficient gives wrong rates. The coefficient depends on a measured sample rate in SDL; the plan measures it on hardware.

## Open Questions

- Does a `2068` Joy-Con pair device exist on macOS, and what does it report? The user lists four IDs; `2068` is noted only.
- Which firmware version do the testers' controllers run? Each capture records it.
