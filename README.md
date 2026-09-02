# OpenJoystickDriver

English | [简体中文](README.zh.md)

[![GitHub Repo stars](https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social)](https://github.com/xsyetopz/OpenJoystickDriver/stargazers)
[![License](https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)

![Github-sponsors](https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA)
[![BuyMeACoffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/jarveaarkry)
[![Ko-Fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/krystian3219)

OpenJoystickDriver is a macOS userspace gamepad driver. Its signed app bundle hosts the controller runtime. The same executable provides a low-level CLI for setup, control, and diagnostics.

Use it when a controller works in OpenJoystickDriver but not in a game, emulator, SDL app, or native macOS app.

<p>
  <a href="#quickstart">Quickstart</a> ·
  <a href="#install-update-or-remove">Install / Remove</a> ·
  <a href="docs/user/compatibility.md">Compatibility</a> ·
  <a href="#choose-a-compatibility-identity">Compatibility Identity</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="CONTRIBUTING.md">Contribute</a> ·
  <a href="https://github.com/xsyetopz/OpenJoystickDriver/stargazers">Star</a>
</p>

## Why OpenJoystickDriver

OpenJoystickDriver normalizes physical controller input into controller outputs that apps can understand. It provides compatibility modes for SDL, Apple GameController, Generic HID, and family-adjacent generic-HID targets, with common diagnostics and checks in one repo-controlled workflow.

## Status

See [docs/user/compatibility.md](docs/user/compatibility.md) for current backend, output-mode, and device-support status.

Vendor-specific/raw USB controllers use direct IOUSBHost when macOS permits app ownership.
Apple-entitled exclusive Xbox GIP models use the generated
`com.openjoystickdriver.XboxUSBDevice` USBDriverKit system extension. The app publishes
consumer-facing virtual controllers with CoreHID on macOS 15+ and the IOKit backend on
macOS 10.15–14. The DEXT never publishes virtual HID devices.

## Brand mark attribution

The settings UI uses native SF Symbols and brand-referenced colors to identify
Xbox and PlayStation protocol families; no brand image assets are bundled. Xbox
and PlayStation marks and names remain the property of Microsoft and Sony
Interactive Entertainment, respectively, and this project is not affiliated
with or endorsed by either company. See [Microsoft Trademark and Brand
Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
and [PlayStation's copyright and trademark notice](https://www.playstation.com/en-us/legal/copyright-and-trademark-notice/).

## Quickstart

1. Drag `OpenJoystickDriver.app` to `/Applications`.
2. Open `OpenJoystickDriver.app`.
3. Open the menu-bar item to review readiness and connected controllers. Choose `Settings…` (⌘,)
   for Overview, Controllers, Profiles, and Debug.
4. Grant **Input Monitoring** and **Accessibility** to OpenJoystickDriver when macOS asks. Use
   the matching permission icon in the settings footer to start the native macOS flow. These
   permissions enable physical controller input and controller output.
5. If a profile sends keyboard, mouse, pointer, or scroll events, use the **Keyboard & pointer**
   permission icon in the settings footer for its separate access check.
6. Connect a supported controller, then choose **Open Profiles…** to create ordinary assignments and
   adjust stick/trigger response. Use **Controllers…** or **Refresh** to update the menu-bar summary.

Your target app should now see a compatible virtual controller.

## Install, update, or remove

OpenJoystickDriver has one app bundle in `/Applications`:

```bash
/Applications/OpenJoystickDriver.app
```

The main application executable also hosts the in-process runtime. There is no nested helper application or second privacy identity.

Use the installed executable for setup and diagnostics:

| Action | Command |
| --- | --- |
| Check service status | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status` |
| Disable Open at Login | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless app login disable` |

To uninstall OpenJoystickDriver completely:

1. Disable the login item with:

   ```bash
   /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless app login disable
   ```

2. Quit OpenJoystickDriver.
3. Delete `/Applications/OpenJoystickDriver.app`.
4. Optional: remove OpenJoystickDriver from **Input Monitoring** and **Accessibility** in System Settings.

## Choose a compatibility identity

| What you are trying to run | Recommended | Why |
| --- | --- | --- |
| Steam, PCSX2, and other SDL 2/3 apps | Compatibility + `SDL2/3` | Hardware-verified ASTRO HIDAPI identity with Xbox 360-style input and rumble. |
| Native macOS apps using `GCController` | Compatibility + `Apple GameController` | Targets GameController.framework consumers. |
| Apps that inspect HID descriptors | Compatibility + `Generic HID` | Descriptor-driven HID surface. |
| A consumer needing Xbox 360-family generic HID | Compatibility + `Xbox 360 HID` | Family-adjacent generic-HID descriptor; not XInputHID, XUSB, or GIP emulation. |

CLI equivalents from the installed app bundle:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
```

`xone-hid` is a legacy persisted Xbox One Bluetooth-shaped generic-HID
identity, retained only for existing configurations and not offered as a new
selection. It is not XInputHID, XUSB, or GIP emulation.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| The runtime is disconnected | Launch the installed app, then check `--headless status`. |
| SDL sees 0 controllers | Ensure Input Monitoring and Accessibility are granted, then restart the host and re-test. |
| XboxUSBDevice installation fails | Entitlement-restricted USB controllers remain unavailable; accessible raw controllers can still use direct IOUSBHost. Rebuild the signed app and run `--headless extension enable`. |

Useful diagnostics:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./.build/debug/OpenJoystickDriver --headless diagnose catalog --json
./.build/debug/OpenJoystickDriver --headless diagnose runtime --seconds 300 --json
./.build/debug/OpenJoystickDriver --headless controller state --json
./.build/debug/OpenJoystickDriver --headless controller watch --seconds 10 --interval-ms 16
./.build/debug/OpenJoystickDriver --headless controller packets --limit 50
./.build/debug/OpenJoystickDriver --headless app logs show --stream both --lines 100
./.build/debug/OpenJoystickDriver --headless update check
./scripts/ojd diagnose sdl3 --seconds 10
```

When identical controller models are connected, run `controller output list`
and pass its opaque selector as `--device <id>` to `input` or
`controller output`. This targets the same runtime device identity used by Input
diagnostics instead of selecting an arbitrary matching VID/PID.

See [Application service Runtime Health](docs/development/application-service-health.md) for soak verdicts, high-water limits, and the foreground-consumer polling leak regression probe.
See [Application Responsiveness](docs/development/application-responsiveness.md) for bounded system-tool execution and shutdown guarantees.
See [CLI and Application Runtime](docs/development/cli-and-runtime.md) for the shared runtime boundary.

Installed app bundle commands:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless diagnose report
```

## Development

Parser, record, and test changes do not require signing:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
./scripts/ojd check driverkit
swift build
```

For application, generated USB DriverKit, signing, and notarization work, start here:

- [Signing assets and Apple Developer portal setup](docs/development/signing.md)
- [scripts/README.md](scripts/README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/development/architecture.md](docs/development/architecture.md)

### Tester and release distribution

The supported distribution paths are intentionally separate and ordered:

1. For private tester sharing, a maintainer with locally configured Developer ID
   host and DEXT signing assets runs `./scripts/ojd package tester`. The command
   creates a named, unnotarized DMG in `.build/tester-artifacts/` containing the
   app, embedded DriverKit extension, source commit, and unique bundle build
   metadata. It does not install or publish anything, and the recipient does not
   need a source checkout. It is Developer ID signed but unnotarized; testers may need an
   explicit Gatekeeper override. Apple Development artifacts are not supported
   for arbitrary community tester distribution.
2. For published releases, push a SemVer tag or manually dispatch
   `.github/workflows/release.yml` with an existing SemVer tag. GitHub Actions
   checks out that tag, builds with Developer ID signing, notarizes and staples
   the app, and publishes the release DMG.

See [scripts/README.md](scripts/README.md) for signing prerequisites and the
exact artifact/reporting expectations.

## Contributing

Useful contribution areas:

- controller parser and record improvements
- compatibility-layer tests and diagnostics
- documentation for supported devices, compatibility identities, and troubleshooting
- reproducible reports for games, emulators, SDL apps, and native macOS apps

Before opening a PR for parser/record work, run:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
swift build
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for repository expectations.

## AI and coding agents

Read these files before editing:

1. [README.md](README.md) -- product intent and user workflows.
2. [scripts/README.md](scripts/README.md) -- repository command interface.
3. [CONTRIBUTING.md](CONTRIBUTING.md) -- PR expectations.
4. [docs/development/architecture.md](docs/development/architecture.md) -- application, DriverKit, and compatibility boundaries.
5. [docs/user/compatibility.md](docs/user/compatibility.md) -- support status and output-mode behavior.

Minimum checks for parser/record changes:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
swift build
```

## Star History

<a href="https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&theme=dark&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U" />
 </picture>
</a>

## License

[MIT](LICENSE)
