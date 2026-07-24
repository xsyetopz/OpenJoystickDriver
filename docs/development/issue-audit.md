# Controller issue audit

This matrix separates behavior implemented in source from behavior observed on
the reported hardware. A green unit test is not a substitute for a physical
controller result. The referenced GitHub issues remain authoritative when an
archived report or this audit becomes stale.

Audit baseline: 2026-07-24, OpenJoystickDriver 0.5 development tree.

Dependency baseline:

- SwiftUSB `0.1.2`, resolved revision
  `2bdafcba623e437c02b669eb9ddcb794d94ba1fb`.
- SwifterKit `main`, reviewed resolved revision
  `564a77c050561c286ba81198ad56518dad069c17`. The branch is intentionally
  mutable while its required HID host-report allowlist remains unreleased.
- [Linux `xpad.c`](https://github.com/torvalds/linux/blob/44696aa3a489d2baf58efa61b37833f100072bee/drivers/input/joystick/xpad.c),
  `hid-steam.c`, and `hid-ids.h` remain byte-identical between
  the pinned commit `44696aa3a489d2baf58efa61b37833f100072bee` and upstream
  master observed on 2026-07-23. The pinned source remains the catalog import
  authority; current upstream is a verification reference, not a reason to
  regenerate the catalog.

## Evidence matrix

| Scope | Reported acceptance behavior | Current evidence | Assessment | Remaining closure evidence |
| --- | --- | --- | --- | --- |
| [#8 Steam Controller](https://github.com/xsyetopz/OpenJoystickDriver/issues/8) | Wired and wireless devices enumerate without mouse/keyboard lizard behavior; buttons, sticks, pads, lifecycle, haptics, and brightness work through a consumer-visible virtual controller. | Linux `hid-steam.c` confirms Valve `28DE:1102` wired and `28DE:1142` wireless identities, feature-report discovery, and receiver lifecycle semantics. OJD catalog records, `SteamControllerParser`, feature-report handling, lifecycle gating, parser tests, and the macOS 14 parser harness pass. | **Partial: code implemented, hardware unverified.** | Run the [Steam Controller procedure](../testing/steam-controller.md) on wired and wireless hardware, including reconnect and consumer visibility. |
| [#9 Xbox 360 wireless](https://github.com/xsyetopz/OpenJoystickDriver/issues/9) | Receiver opens without a crash, detects controller connect/disconnect, maps every input correctly, and accepts supported output. | Linux `xpad.c` confirms `045E:0291`, `02A9`, and `0719` as Xbox 360 wireless receivers with D-pad mapping. OJD has wireless receiver records, wrapped-input parsing, lifecycle handling, output-packet tests, and SwiftUSB's device/context lifetime fix. | **Partial: code implemented, hardware unverified.** | Repeat the [wireless receiver procedure](../testing/xbox-360-wireless-receiver.md) with SwiftUSB 0.1.2; the last reported live probe crashed before acceptance. |
| [#10 wired Xbox 360](https://github.com/xsyetopz/OpenJoystickDriver/issues/10) | The ring stops flashing and selects Player 1; inputs remain correctly mapped and the controller remains visible to Steam. | The Player-1 solid startup packet is source-backed and tested. The reporter confirmed the original ring symptom fixed in alpha.4. | **Resolved for the original ring symptom; partial for the later thread.** | Recheck the later mapping and Steam-recognition reports on the current Compatibility-only output path. |
| [#11 Logitech F310](https://github.com/xsyetopz/OpenJoystickDriver/issues/11) | XInput-mode controls match SDL's mapping. | Linux `xpad.c` explicitly classifies `046D:C21D` as Xbox 360; OJD's local record adds the captured interrupt endpoints `0x81`/`0x02`, and mapping and transport-profile tests pass. | **Code-resolved, hardware unverified.** | Run the [F310 procedure](../testing/logitech-f310.md) and compare every control with SDL on the same Mac. |
| [#14 Wolverine V3 TE](https://github.com/xsyetopz/OpenJoystickDriver/issues/14) | `1532:0A43` uses GIP rather than Generic HID, completes startup, exposes every verified control, reconnects, and supports only observed output capabilities. | The exact `0A43` PID is absent from current Linux `xpad.c`; Linux's separate `0A57`/`0A59` Wolverine V3 Pro entries are not evidence for this Tournament Edition. The record therefore remains a local GIP classification with unsupported Share and paddle claims removed. | **Partial: classification implemented.** | Capture endpoints, startup, every input, reconnect, indicator, and rumble using the [V3 TE procedure](../testing/razer/v3-te.md). |
| [#18 Xbox One 1537](https://github.com/xsyetopz/OpenJoystickDriver/issues/18) | `045E:02D1` uses GIP with configuration 1 and endpoints `0x81`/`0x01`; handshake, all controls, Guide, LED, rumble, and reconnect work through OJD without blocking unsupported devices. | Reporter hardware proved the protocol through IOUSBHost. The record contains the verified configuration/endpoints, raw-USB admission rejects unsupported devices, and parser/record tests pass. SwiftUSB 0.1.2 contains the lifetime fix. | **Partial: protocol resolved; production transport unverified.** | The reporter or equivalent hardware must show OJD's SwiftUSB/libusb path opens successfully and completes the [1537 procedure](../testing/xbox/1537.md). The prior production open returned `LIBUSB_ERROR_NO_DEVICE`. |
| [#19 Wolverine V2](https://github.com/xsyetopz/OpenJoystickDriver/issues/19) | `1532:0A29` selects GIP on interface 0 endpoints `0x81`/`0x01`, then proves input decoding, reconnect, indicator, and rumble. | Linux `xpad.c` explicitly classifies `1532:0A29` as Xbox One/GIP. OJD pins the locally captured interrupt endpoints; the announce packet proves GIP classification. Unsupported Share, paddles, forced configuration, and delay claims are intentionally absent. | **Partial: classification and endpoints implemented.** | Complete the [Wolverine V2 procedure](../testing/razer/wolverine-v2.md) on hardware. |
| [#21 Nacon Revolution X Pro](https://github.com/xsyetopz/OpenJoystickDriver/issues/21) | `3285:0634` selects GIP on interface 0 endpoints `0x87`/`0x07`, stays stable through continuous input, and supports the observed controls without a synthetic host status packet. | A local override and generated record select GIP/xboxOne with the captured endpoints and profile-scoped keep-alive disabled. GIP framing accepts split, stacked, and base-128 length frames and builds requested ACKs from the Linux/xone message layout; chunk payload reassembly remains out of scope. Provenance remains unverified. | **Partial: profile and protocol handling implemented; hardware unverified.** | Run the [Nacon Revolution X Pro procedure](../testing/nacon-revolution-x.md), especially reconnect, continuous input, and proof that no host `0x03` is emitted. |
| DriverKit to SwifterKit | The manual DriverKit project is absent; generation is deterministic; host and extension policies are exact; the extension builds for supported architectures; signed activation and relay delivery pass without replacing the consumer gamepad. | SwifterKit owns generation and host transport at reviewed revision `564a77c`. Its generated HID project links only HID/base DriverKit. The signed version-2 dext is activated on macOS 15.7.7 and the kernel reports `start(...) ok`. Normal controller events reach only `CompatibilityOutputDispatcher`; DriverKit is diagnostic-only. Self-test independently probes Compatibility with neutral reports and derives relay strictness from the signed host entitlement. | **Migration and signed dext runtime resolved; host relay delivery blocked by the pending exact entitlement grant.** | Replace the legacy host profile after Apple approves the exact single-relay grant, then run the installed relay self-test. Until then, self-test reports relay delivery as optional and inconclusive while requiring Compatibility delivery. |

## Code-level gates

The audit baseline passed:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd validate scripts
./scripts/ojd test scripts
./scripts/ojd validate swift-structure
./scripts/ojd lint
./scripts/ojd test parsers-macos14
./scripts/ojd validate driverkit
MACOSX_DEPLOYMENT_TARGET=14.0 /usr/bin/xcrun swift test
```

The final Swift suite executed 393 tests in 68 suites with target
`arm64e-apple-macos14.0`. The DriverKit gate produced an unsigned universal
`arm64` and `x86_64` extension.

Focused issue filters also passed: #8 (17 tests), #9 (4), #10 (2), #11 (4),
#14 (1), #18 (4), #19 (1), and #21 (record, probe, and GIP parser tests).
These filters prove the recorded parser,
catalog, admission, and startup contracts; they do not replace the hardware
procedures named in the matrix.

## Installed runtime evidence

The development app and generated version-2 dext were signed and installed on
macOS 15.7.7. The observed runtime state was:

- the app passed AMFI validation and `--headless status` exited successfully;
- Input Monitoring and Accessibility reported granted;
- the system extension reported `activated enabled`;
- the registered dext matched the app-embedded binary by SHA-256;
- `otool -L` showed only HIDDriverKit, base DriverKit, and libc++;
- the kernel reported `SwifterKitRuntimeService::start(...) ok`;
- `--headless diagnose self-test 2` observed four Compatibility reports, reported the
  Compatibility verdict as passed, reported DriverKit as optional and
  inconclusive, and exited successfully.

The installed host intentionally omits
`com.apple.developer.driverkit.userclient-access` while the only approved host
profile contains Apple's malformed legacy value. This permits the app and
Compatibility output to run, but it prevents the relay self-test from opening
the DriverKit user client. The installed self-test reports that relay diagnostic
as optional and inconclusive; a failed Compatibility probe still fails the
command. After Apple approves the corrected grant, replace the profiles and rerun:

```bash
./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd signing doctor
./scripts/ojd rebuild dev
```

The Developer ID profile also remains unsuitable for release because its
embedded certificate does not match the installed Developer ID Application
identity. Development readiness and the installed evidence above do not prove
release signing or notarization.
