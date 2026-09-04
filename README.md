# OpenJoystickDriver

[![GitHub Repo stars](https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social)](https://github.com/xsyetopz/OpenJoystickDriver/stargazers)
[![License](https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)

![Github-sponsors](https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA)
[![BuyMeACoffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/jarveaarkry)
[![Ko-Fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/krystian3219)

A macOS userspace gamepad driver. The signed app runs the runtime; the same
binary is the CLI. Use it when a controller works here but not in a game,
emulator, SDL app, or native macOS app.

Xbox and PlayStation names in the UI are trademarks of Microsoft and Sony. This
project is not affiliated with either.
[Microsoft](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
·
[PlayStation](https://www.playstation.com/en-us/legal/copyright-and-trademark-notice/).

Support matrix: [docs/user/compatibility.md](docs/user/compatibility.md).

## Install

1. Drag `OpenJoystickDriver.app` to `/Applications` and open it.
2. Use the menu-bar item. Settings is ⌘,.
3. Grant **Input Monitoring** and **Accessibility** when asked. Profiles that
   send keyboard or mouse events also need **Keyboard & pointer**.
4. Connect a controller. **Open Profiles...** for assignments; **Controllers...**
   or **Refresh** for the menu summary.

One bundle, no helper app: `/Applications/OpenJoystickDriver.app`.

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
```

Uninstall: `--headless app login disable`, quit, delete the app. Optionally
remove it from Input Monitoring and Accessibility.

## Compatibility identity

| Target | Setting |
| --- | --- |
| Steam, PCSX2, SDL 2/3 | Compatibility + `SDL2/3` |
| `GCController` apps | Compatibility + `Apple GameController` |
| HID-descriptor apps | Compatibility + `Generic HID` |
| Xbox 360-family generic HID | Compatibility + `Xbox 360 HID` |

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
```

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Runtime disconnected | Launch the app, then `--headless status` |
| SDL sees 0 controllers | Grant Input Monitoring and Accessibility, restart, retry |
| XboxUSBDevice install fails | Rebuild the signed app; `--headless extension enable` |

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless diagnose report
```

Identical models: `controller output list`, then `--device <id>`.

## Development

[CONTRIBUTING.md](CONTRIBUTING.md) · [LOCALIZATION.md](LOCALIZATION.md) ·
[docs/README.md](docs/README.md) · [scripts/README.md](scripts/README.md) ·
[AGENTS.md](AGENTS.md)

## License

[MIT](LICENSE)

## Star History

<a href="https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&theme=dark&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U" />
 </picture>
</a>
