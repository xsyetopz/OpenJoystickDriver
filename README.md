# OpenJoystickDriver

[![GitHub Repo stars](https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social)](https://github.com/xsyetopz/OpenJoystickDriver/stargazers)
[![License](https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](README.md)

OpenJoystickDriver is a macOS menu-bar app and daemon that turns supported physical controllers into app-friendly virtual controllers.

Use it when a controller works in OpenJoystickDriver but not in a game, emulator, browser, SDL app, or native macOS app.

<p>
  <a href="#quickstart">Quickstart</a> ·
  <a href="docs/COMPATIBILITY_LAYERS.md">Compatibility</a> ·
  <a href="#choose-an-output-mode">Output Modes</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="CONTRIBUTING.md">Contribute</a> ·
  <a href="https://github.com/xsyetopz/OpenJoystickDriver/stargazers">Star</a>
</p>

<p align="center">
  <img width="512" height="632" alt="OpenJoystickDriver menu-bar app showing controller input and compatibility controls" src="https://github.com/user-attachments/assets/b2ad4741-8082-445f-8721-d66edb3f79df" />
</p>

## Why OpenJoystickDriver

- Normalizes physical controller input into virtual controller outputs that apps can understand.
- Uses SDL3 for real controller access, including SDL HIDAPI/libusb-backed controllers on macOS.
- Provides compatibility modes for SDL, Apple GameController, Generic HID, and experimental Xbox HID targets.
- Keeps common diagnostics and validation commands in one repo-controlled workflow.

## Status

See [docs/COMPATIBILITY_LAYERS.md](docs/COMPATIBILITY_LAYERS.md) for current backend, output-mode, and device-support status.

Compatibility mode can still be useful without DriverKit. Use DriverKit only when you specifically need that path.

## Quickstart

1. Install `OpenJoystickDriver.app` into `/Applications`.
2. Open the menu-bar item.
3. Follow the UI prompts to grant **Input Monitoring** for the app and helper.
4. Connect a supported controller.
5. Use **Input Test** to confirm buttons and sticks.
6. Test physical rumble only for devices whose rumble path is listed as implemented.

Expected result: your target app sees a compatible virtual controller.

## Choose An Output Mode

| What you are trying to run             | Recommended                                      | Why                                                 |
| -------------------------------------- | ------------------------------------------------ | --------------------------------------------------- |
| Most games, Steam, emulators, SDL apps | Compatibility + `SDL 2/3`                        | Stable app-facing identity and mapping.             |
| Native macOS apps using `GCController` | Compatibility + `Apple GameController`           | Targets GameController.framework consumers.         |
| Apps that inspect HID descriptors      | Compatibility + `Generic HID`                    | Descriptor-driven HID surface.                      |
| A picky app expecting Microsoft HID    | Compatibility + `Xbox 360 HID` or `Xbox One HID` | Experimental spoof identities for targeted testing. |

CLI equivalents from the installed app bundle:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat sdl2-3
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless output secondary
```

## Troubleshooting

| Symptom                               | What to do                                                                             |
| ------------------------------------- | -------------------------------------------------------------------------------------- |
| Menu UI says “running (disconnected)” | Use **Restart Helper** in the menu, or run `--headless restart`.                       |
| SDL / browser sees 0 controllers      | Ensure Input Monitoring is granted, then re-open the app and re-test.                  |
| DriverKit extension install fails     | Compatibility mode still works without DriverKit. Use DriverKit only when you need it. |

Useful diagnostics:

```bash
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./scripts/ojd diagnose sdl3 --seconds 10
```

Installed app bundle commands:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless restart
```

## Development

Parser, profile, and test changes do not require signing:

```bash
brew install sdl3 libusb
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
swift build
```

For app/daemon, DriverKit, signing, and notarization work, start here:

- [scripts/README.md](scripts/README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Contributing

Useful contribution areas:

- controller parser and profile improvements
- compatibility-layer tests and diagnostics
- documentation for supported devices, output modes, and troubleshooting
- reproducible reports for games, emulators, browsers, SDL apps, and native macOS apps

Before opening a PR for parser/profile work, run:

```bash
./scripts/ojd validate profiles
./scripts/ojd test parsers-macos14
swift build
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for repository expectations.

## AI / Coding Agents

Use this context path before editing:

1. [README.md](README.md) — product intent and user workflows.
2. [scripts/README.md](scripts/README.md) — repository command interface.
3. [CONTRIBUTING.md](CONTRIBUTING.md) — PR expectations.
4. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — app, daemon, DriverKit, and compatibility boundaries.
5. [docs/COMPATIBILITY_LAYERS.md](docs/COMPATIBILITY_LAYERS.md) — support status and output-mode behavior.

Minimum validation for parser/profile changes:

```bash
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
