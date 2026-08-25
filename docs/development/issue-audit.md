# Controller issue audit

This matrix separates behavior implemented in source from behavior observed on
the reported hardware. A green unit test is not a substitute for a physical
controller result. The referenced GitHub issues remain authoritative when an
archived report or this audit becomes stale.

Audit baseline: 2026-07-24, OpenJoystickDriver 0.5 development tree.

Dependency baseline:

- SwifterKit `main`, reviewed resolved revision
  `564a77c050561c286ba81198ad56518dad069c17`. The branch is intentionally
  mutable while its required HID host-report allowlist remains unreleased.
- [Linux `xpad.c`](https://github.com/torvalds/linux/blob/44696aa3a489d2baf58efa61b37833f100072bee/drivers/input/joystick/xpad.c),
  `hid-steam.c`, and `hid-ids.h` were byte-identical between pinned commit
  `44696aa3a489d2baf58efa61b37833f100072bee` and upstream master, as observed
  on 2026-07-23. The pinned source is the catalog import authority; upstream is
  a verification reference and does not require catalog regeneration.

## Evidence matrix

| Scope | Reported acceptance behavior | Current evidence | Assessment | Remaining closure evidence |
| --- | --- | --- | --- | --- |
| [#8 Steam Controller](https://github.com/xsyetopz/OpenJoystickDriver/issues/8) | Wired and wireless devices enumerate without mouse/keyboard lizard behavior; buttons, sticks, pads, lifecycle, haptics, and brightness work through a consumer-visible virtual controller. | Linux `hid-steam.c` confirms Valve `28DE:1102` wired and `28DE:1142` wireless identities, feature-report discovery, and receiver lifecycle semantics. OJD catalog records, `SteamControllerParser`, feature-report handling, lifecycle gating, parser tests, and the macOS 14 parser harness pass. | **Partial: code implemented, hardware unverified.** | Run the [Steam Controller procedure](../testing/steam-controller.md) on wired and wireless hardware, including reconnect and consumer visibility. |
| [#9 Xbox 360 wireless](https://github.com/xsyetopz/OpenJoystickDriver/issues/9) | Receiver opens without a crash, detects controller connect/disconnect, maps every input correctly, and accepts supported output. | Linux `xpad.c` confirms `045E:0291`, `02A9`, and `0719` as Xbox 360 wireless receivers with D-pad mapping. OJD has wireless receiver records, wrapped-input parsing, lifecycle handling, and output-packet tests. These pairs are not in the current production Apple USB entitlement. | **Partial: code implemented; hardware ownership unverified.** | Run the [wireless receiver procedure](../testing/xbox-360-wireless-receiver.md) through direct IOUSBHost. Request an exact production entitlement only if live evidence proves macOS ownership requires the DEXT. |
| [#10 wired Xbox 360](https://github.com/xsyetopz/OpenJoystickDriver/issues/10) | The ring stops flashing and selects Player 1; inputs remain correctly mapped and the controller remains visible to Steam. | The Player-1 solid startup packet is source-backed and tested. The reporter confirmed the original ring symptom fixed in alpha.4. | **Resolved for the original ring symptom; partial for the later thread.** | Recheck the later mapping and Steam-recognition reports on the current Compatibility-only output path. |
| [#11 Logitech F310](https://github.com/xsyetopz/OpenJoystickDriver/issues/11) | XInput-mode controls match SDL's mapping. | Linux `xpad.c` explicitly classifies `046D:C21D` as Xbox 360; OJD's local record adds the captured interrupt endpoints `0x81`/`0x02`, and mapping and transport-profile tests pass. | **Code-resolved, hardware unverified.** | Run the [F310 procedure](../testing/logitech-f310.md) and compare every control with SDL on the same Mac. |
| [#14 Wolverine V3 TE](https://github.com/xsyetopz/OpenJoystickDriver/issues/14) | `1532:0A43` uses GIP rather than Generic HID, completes startup, exposes every verified control, reconnects, and supports only observed output capabilities. | The exact `0A43` PID is absent from current Linux `xpad.c`; Linux's separate `0A57`/`0A59` Wolverine V3 Pro entries are not evidence for this Tournament Edition. The record therefore remains a local GIP classification with unsupported Share and paddle claims removed. | **Partial: classification implemented.** | Capture endpoints, startup, every input, reconnect, indicator, and rumble using the [V3 TE procedure](../testing/razer/v3-te.md). |
| [#18 Xbox One 1537](https://github.com/xsyetopz/OpenJoystickDriver/issues/18) | `045E:02D1` uses GIP with configuration 1 and endpoints `0x81`/`0x01`; handshake, all controls, Guide, LED, rumble, and reconnect work through OJD without blocking unsupported devices. | Reporter hardware proved the protocol through IOUSBHost. The record contains the verified configuration/endpoints, raw-USB admission rejects unsupported devices, parser/record tests pass, and Apple approved this pair for the production USBDriverKit entitlement. | **Partial: protocol resolved; generated DEXT transport unverified.** | An appropriately provisioned build must open the controller through `com.openjoystickdriver.XboxUSBDevice` and complete the [1537 procedure](../testing/xbox/1537.md). |
| [#19 Wolverine V2](https://github.com/xsyetopz/OpenJoystickDriver/issues/19) | `1532:0A29` selects GIP on interface 0 endpoints `0x81`/`0x01`, then proves input decoding, reconnect, indicator, and rumble. | Linux `xpad.c` explicitly classifies `1532:0A29` as Xbox One/GIP. OJD pins the locally captured interrupt endpoints; the announce packet proves GIP classification. Unsupported Share, paddles, forced configuration, and delay claims are intentionally absent. | **Partial: classification and endpoints implemented.** | Complete the [Wolverine V2 procedure](../testing/razer/wolverine-v2.md) on hardware. |
| [#21 Nacon Revolution X Pro](https://github.com/xsyetopz/OpenJoystickDriver/issues/21) | `3285:0634` selects GIP on interface 0 endpoints `0x87`/`0x07`, stays stable through continuous input, and supports the observed controls without a synthetic host status packet. | A local override and generated record select GIP/xboxOne with the captured endpoints and profile-scoped keep-alive disabled. GIP framing accepts split, stacked, and base-128 length frames and builds requested ACKs from the Linux/xone message layout; chunk payload reassembly remains out of scope. Provenance remains unverified. | **Partial: profile and protocol handling implemented; hardware unverified.** | Run the [Nacon Revolution X Pro procedure](../testing/nacon-revolution-x.md), especially reconnect, continuous input, and proof that no host `0x03` is emitted. |
| [#22 bDeviceClass=0 discovery](https://github.com/xsyetopz/OpenJoystickDriver/issues/22) | Controllers with `bDeviceClass = 0` that declare vendor-specific class only at the interface level are discovered and matched to their catalog profile. | The IOUSBHost backend discovers catalog-supported `IOUSBHostDevice` services before interfaces exist, applies a catalog-declared configuration when required, and then resolves the vendor-specific interface. `USBDescriptorTransportResolver` retains the interface-level admission rule. | **Code-resolved, hardware unverified.** | Test with a `bDeviceClass=0` controller (e.g. ZD Ultimate Legend `413D:2104`) and confirm discovery without manual intervention. |
| USBDriverKit to SwifterKit | The manual DriverKit project is absent; generation is deterministic; host and extension policies are exact; and the extension builds for supported architectures. | SwifterKit owns DEXT generation and the restricted host adapter. The sole authored configuration and entitlement contain exactly Apple's approved Microsoft GIP pairs in development and production. Accessible third-party controllers such as the GameSir G7 SE remain app-owned through IOUSBHost. Virtual HID remains app-owned and is absent from the DEXT. | **Code migration complete; signed Microsoft USB runtime unverified.** | Keep the activated DEXT idle without an entitled Microsoft device. Complete signed DEXT input/output validation when one of Apple's approved Microsoft pairs is available; validate GameSir separately through direct IOUSBHost. |

## Code-level gates

The audit baseline passed:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd check scripts
./scripts/ojd check swift-structure
./scripts/ojd lint
./scripts/ojd test parsers-macos14
./scripts/ojd check driverkit
MACOSX_DEPLOYMENT_TARGET=14.0 /usr/bin/xcrun swift test
```

The final Swift suite executed 393 tests in 68 suites with target
`arm64e-apple-macos14.0`. The DriverKit gate produced an unsigned universal
`arm64` and `x86_64` extension.

Focused issue filters also passed: #8 (17 tests), #9 (4), #10 (2), #11 (4),

# 14 (1), #18 (4), #19 (1), #21 (record, probe, and GIP parser tests), and #22

These filters prove the recorded parser, catalog, admission, and startup
contracts; they do not replace the hardware procedures named in the matrix.

## Installed runtime evidence

The removed HID relay was previously signed and installed on macOS 15.7.7. That
evidence does not validate the replacement USB DEXT. The historical observed
runtime state was:

- the app passed AMFI validation and `--headless status` exited successfully;
- Input Monitoring and Accessibility reported granted;
- the system extension reported `activated enabled`;
- the registered dext matched the app-embedded binary by SHA-256;
- `otool -L` showed only HIDDriverKit, base DriverKit, and libc++;
- the kernel reported `SwifterKitRuntimeService::start(...) ok`;
- `--headless test 2` observed four compatibility reports and exited successfully.

### Required replacement signing evidence

The installed host profile contains a malformed legacy user-client value and the
replacement DEXT development profile is absent. Current signing tooling requires
the exact single-DEXT host grant. Install refreshed profiles and rerun:

```bash
./scripts/ojd signing install-profiles
./scripts/ojd signing configure
./scripts/ojd signing doctor
./scripts/ojd build install dev
```

### Remaining release blocker

The Developer ID profile remains unsuitable for release because its embedded
certificate does not match the installed Developer ID Application identity.
Development readiness and the installed evidence above do not prove release
signing or notarization.
