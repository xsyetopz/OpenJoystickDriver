# OpenJoystickDriver

[![GitHub Repo stars](https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social)](https://github.com/xsyetopz/OpenJoystickDriver/stargazers)
[![License](https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](README.md)

OpenJoystickDriver is a macOS menu-bar app that turns supported physical controllers into app-friendly virtual controllers.

Use it when a controller works in OpenJoystickDriver but not in a game, emulator, browser, SDL app, or native macOS app.

<p>
  <a href="#quickstart">Quickstart</a> ·
  <a href="#install-update-or-remove">Install / Remove</a> ·
  <a href="docs/user/compatibility.md">Compatibility</a> ·
  <a href="#choose-a-compatibility-identity">Compatibility Identity</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="CONTRIBUTING.md">Contribute</a> ·
  <a href="https://github.com/xsyetopz/OpenJoystickDriver/stargazers">Star</a>
</p>

<p align="center">
  <img width="512" height="632" alt="OpenJoystickDriver menu-bar app showing controller input and compatibility controls" src="https://github.com/user-attachments/assets/b2ad4741-8082-445f-8721-d66edb3f79df" />
</p>

## Why OpenJoystickDriver

- Normalizes physical controller input into virtual controller outputs that apps can understand.
- Provides compatibility modes for SDL, Apple GameController, Generic HID, and experimental Xbox HID targets.
- Keeps common diagnostics and check commands in one repo-controlled workflow.

## Status

See [docs/user/compatibility.md](docs/user/compatibility.md) for current backend, output-mode, and device-support status.

Compatibility mode does not require DriverKit. The generated SwifterKit system
extension is a vendor-defined integrity relay for self-test and diagnostics; it
deliberately does not publish a second consumer gamepad. Self-test reads the
signed host entitlement: relay delivery is required for an entitled host and
reported as optional and inconclusive when the entitlement is absent.

## Quickstart

1. Drag `OpenJoystickDriver.app` to `/Applications`.
2. Open `OpenJoystickDriver.app`.
3. Choose **Install** or **Start** in the menu-bar app when prompted.
4. Grant **Input Monitoring** and **Accessibility** to OpenJoystickDriver when macOS asks.
5. Connect a supported controller.
6. Use **Input Test** to confirm buttons and sticks.

Expected result: your target app sees a compatible virtual controller.

## Install, Update, or Remove

OpenJoystickDriver has one app bundle in `/Applications`:

```bash
/Applications/OpenJoystickDriver.app
```

The main application executable also hosts the background service. There is no nested helper application or second privacy identity.

Use the menu-bar controls for the normal flow:

| Action | Menu-bar path | Headless equivalent |
| --- | --- | --- |
| Install or start service | Open the app, then choose **Install** or **Start** | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless install` |
| Check service status | Open the app and check the System card | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status` |
| Restart service | Choose **Restart Service** | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart` |
| Unregister service | Choose **Uninstall** | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless uninstall` |

To uninstall OpenJoystickDriver completely:

1. Run **Uninstall** from the menu-bar app, or run:

   ```bash
   /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless uninstall
   ```

2. Quit OpenJoystickDriver.
3. Delete `/Applications/OpenJoystickDriver.app`.
4. Optional: remove OpenJoystickDriver from **Input Monitoring** and **Accessibility** in System Settings.

## Choose A Compatibility Identity

| What you are trying to run | Recommended | Why |
| --- | --- | --- |
| Most games, Steam, emulators, SDL apps | Compatibility + `SDL 2/3` | Stable app-facing identity and mapping. |
| Native macOS apps using `GCController` | Compatibility + `Apple GameController` | Targets GameController.framework consumers. |
| Apps that inspect HID descriptors | Compatibility + `Generic HID` | Descriptor-driven HID surface. |
| A picky app expecting Microsoft HID | Compatibility + `Xbox 360 HID` or `Xbox One HID` | Experimental spoof identities for targeted testing. |

CLI equivalents from the installed app bundle:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat sdl2-3
```

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Menu UI says “running (disconnected)” | Use **Restart Service** in the menu, or run `--headless restart`. |
| SDL / browser sees 0 controllers | Ensure Input Monitoring and Accessibility are granted, then re-open the app and re-test. |
| Compare Chrome, Firefox, and Safari | Run `--headless diagnose browser-gamepad --open all`, then press a controller control. |
| DriverKit relay installation fails | Compatibility output still works. `--headless selftest` tests Compatibility and reports relay diagnostics as optional when the signed host lacks relay access. |

Useful diagnostics:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./.build/debug/OpenJoystickDriver --headless diagnose gamecontroller-catalog --json
./.build/debug/OpenJoystickDriver --headless diagnose runtime --seconds 300 --json
./.build/debug/OpenJoystickDriver --headless input state --json
./.build/debug/OpenJoystickDriver --headless input watch --seconds 10 --interval-ms 16
./.build/debug/OpenJoystickDriver --headless input packets --limit 50
./.build/debug/OpenJoystickDriver --headless logs show --stream both --lines 100
./.build/debug/OpenJoystickDriver --headless updates check
./scripts/ojd diagnose sdl3 --seconds 10
```

See [Application service Runtime Health](docs/development/application-service-health.md) for soak verdicts, high-water limits, and the foreground-consumer polling leak regression probe.
See [Menu App Responsiveness](docs/development/menu-responsiveness.md) for bounded system-tool execution and main-actor isolation guarantees.
See [CLI and GUI Capability Parity](docs/development/cli-and-menu-app.md) for the current shared capability audit and remaining one-sided surfaces.

Installed app bundle commands:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless report create
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
```

## Development

Parser, record, and test changes do not require signing:

```bash
brew install libusb
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
./scripts/ojd validate driverkit
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
- reproducible reports for games, emulators, browsers, SDL apps, and native macOS apps

Before opening a PR for parser/record work, run:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
swift build
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for repository expectations.

## AI / Coding Agents

Use this context path before editing:

1. [README.md](README.md) -- product intent and user workflows.
2. [scripts/README.md](scripts/README.md) -- repository command interface.
3. [CONTRIBUTING.md](CONTRIBUTING.md) -- PR expectations.
4. [docs/development/architecture.md](docs/development/architecture.md) -- application, DriverKit, and compatibility boundaries.
5. [docs/user/compatibility.md](docs/user/compatibility.md) -- support status and output-mode behavior.

Minimum checks for parser/record changes:

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
swift build
```

## Star History

<a href="https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left" />
 </picture>
</a>

## License

[MIT](LICENSE)
