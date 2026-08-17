# OpenJoystickDriver

> [!WARNING]
> All compiled 'releases' before 0.5.0-alpha.4 have been swooped due to [#23]([https://github.com/xsyetopz/OpenJoystickDriver/issues/](https://github.com/xsyetopz/OpenJoystickDriver/issues/23)). Please be patient (or compile a private version yourself) for `0.5.0-beta.1`. Thanks for your patience.
>
> UPDATE(2026-08-17): Apple needs to respond to request for Xbox provisioning, and VirtualHIDDevice provisioning changes, as the Jul 17 request is still "submitted" and went nowhere, plus various new fixes within `feat/new-gui` branch that were discovered as I got temp hands on an Xbox Series X controller at a relative's place. This requires lots of patience and waiting as Apple's not very keen to fast responses and resolute. Thanks for waiting!
> - Krystian, OJD's core maintainer.

English | [简体中文](README.zh.md)

[![GitHub Repo stars](https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social)](https://github.com/xsyetopz/OpenJoystickDriver/stargazers)
[![License](https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](README.md)

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

OpenJoystickDriver normalizes physical controller input into virtual controller outputs that apps can understand. It provides compatibility modes for SDL, Apple GameController, Generic HID, and experimental Xbox HID targets, with common diagnostics and checks in one repo-controlled workflow.

## Status

See [docs/user/compatibility.md](docs/user/compatibility.md) for current backend, output-mode, and device-support status.

Compatibility mode does not require DriverKit. The generated SwifterKit system
extension is a vendor-defined integrity relay for self-test and diagnostics. It
deliberately does not publish a second consumer gamepad. Self-test reads the
signed host entitlement. Relay delivery is required for an entitled host and
reported as optional and inconclusive when the entitlement is absent.

## Quickstart

1. Drag `OpenJoystickDriver.app` to `/Applications`.
2. Open `OpenJoystickDriver.app`.
3. The app intentionally has no visible UI. Start and inspect it with the installed bundle command below.
4. Grant **Input Monitoring** and **Accessibility** to OpenJoystickDriver when macOS asks.
5. Connect a supported controller.
6. Run `controller state` or `controller watch` from the CLI to confirm buttons and sticks.

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
| Most games, Steam, emulators, SDL apps | Compatibility + `SDL 2/3` | Stable app-facing identity and mapping. |
| Native macOS apps using `GCController` | Compatibility + `Apple GameController` | Targets GameController.framework consumers. |
| Apps that inspect HID descriptors | Compatibility + `Generic HID` | Descriptor-driven HID surface. |
| A picky app expecting Microsoft HID | Compatibility + `Xbox 360 HID` or `Xbox One HID` | Experimental spoof identities for targeted testing. |

CLI equivalents from the installed app bundle:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
```

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| The runtime is disconnected | Launch the installed app, then check `--headless status`. |
| SDL sees 0 controllers | Ensure Input Monitoring and Accessibility are granted, then restart the host and re-test. |
| DriverKit relay installation fails | Compatibility output still works. `--headless test` tests Compatibility and reports relay diagnostics as optional when the signed host lacks relay access. |

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
brew install libusb
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
./scripts/ojd check driverkit
swift build
```

For application, generated DriverKit relay, signing, and notarization work, start here:

- [Signing assets and Apple Developer portal setup](docs/development/signing.md)
- [scripts/README.md](scripts/README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/development/architecture.md](docs/development/architecture.md)

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
