# OpenJoystickDriver

[![GitHub Repo stars][1]](https://github.com/xsyetopz/OpenJoystickDriver/stargazers) [![License][2]](LICENSE) [![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)

![Github-sponsors][3]

A macOS userspace gamepad driver. The signed app binary hosts the runtime and CLI. Use it when a controller works here but not in a game, emulator, SDL app, or native macOS app.

Xbox and PlayStation names in the UI are trademarks of Microsoft and Sony. This project is not affiliated with either. [Microsoft](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) · [PlayStation](https://www.playstation.com/en-us/legal/copyright-and-trademark-notice/).

Supported controllers and their evidence: [docs/connecting-controllers/supported-controllers.md](docs/connecting-controllers/supported-controllers.md). New here: [install](docs/getting-started/installing-openjoystickdriver.md), [FAQ](docs/troubleshooting/faq.md).

[1]: https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social
[2]: https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver
[3]: https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA

## Install

1. Drag `OpenJoystickDriver.app` to `/Applications` and open it.
1. Use the menu-bar item. Settings is ⌘,.
1. Grant **Input Monitoring** and **Accessibility** when asked. Profiles that send keyboard or mouse events also need **Keyboard & pointer**.
1. Connect a controller. **Open Profiles...** for assignments; **Controllers...** or **Refresh** for the menu summary.

One bundle, no helper app: `/Applications/OpenJoystickDriver.app`.

```bash
ln -s /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver /usr/local/bin/ojd
ojd status
```

Uninstall: `--headless app login disable`, quit, delete the app. Optionally remove it from Input Monitoring and Accessibility.

## Virtual HID Profile

OJD automatically publishes each non-native controller as one of two virtual HID profiles, chosen from the controller's declared controls: `hid-xbox-one-s-bt` (Xbox One S Bluetooth, `045E:02FD`) when they fit, else `hid-generic`. Override a model's profile, or clear the override to return to automatic selection:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller \
  virtual set hid-generic --vid 0x045E --pid 0x02FD
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller \
  virtual reset --all
```

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| Runtime disconnected | `ojd service start`, then `ojd status` |
| SDL sees 0 controllers | Grant Input Monitoring and Accessibility, restart, retry |
| XboxUSBDevice install fails | Rebuild the signed app; `--headless extension enable` |
| Input stays held or status says Needs attention | Release the controls and check controller input health with `--headless status --json` |
| Bluetooth controller will not recover | Use Controller Details → Disconnect Wireless Controller, reconnect it manually, then verify neutral startup |

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless diagnose report
```

More: [troubleshooting](docs/troubleshooting/README.md), [report a bug](docs/troubleshooting/reporting-a-bug.md), [tester builds](contributing/testing/tester-builds.md).

Identical models: `controller output list`, then `--device <id>`. To close only the selected Bluetooth link, use `controller disconnect-wireless --device <id>`; this never reconnects it.

## Development

[CONTRIBUTING.md](CONTRIBUTING.md) · [LOCALIZATION.md](LOCALIZATION.md) · [docs/README.md](docs/README.md) · [Scripts/README.md](Scripts/README.md) · [Tools/README.md](Tools/README.md) · [AGENTS.md](AGENTS.md)

## License

[MIT](LICENSE)

## Star History

[![Star History Chart][4]][5]

[4]: https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U
[5]: https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left
