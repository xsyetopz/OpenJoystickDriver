# Glossary

Each term below names one concept in the app, the menus, the command line prose, and this wiki.

## Terms

| Term | Definition | Replaces | Command line |
| --- | --- | --- | --- |
| profile | A set of bindings that changes what the controls of a controller do. | "remapping profile" | `ojd profile` |
| virtual gamepad | The gamepad that OpenJoystickDriver shows to games in place of the physical controller. | "virtual device", "virtual controller", "Virtual HID profile", "persona" | `ojd virtual`, the `persona` key of a virtual gamepad file |
| virtual gamepad kind | The form of the virtual gamepad, chosen by what reads it: "For Steam and SDL games", "For Apple Game Controller games", or "Generic HID gamepad". | "persona", "profile" for this choice, the raw identifiers in Simple | `SDLCompatible`, `GameControllerCompatible`, `Generic` |
| Handled by macOS | macOS reads the physical controller, and OpenJoystickDriver shows no virtual gamepad for it. | "Served by", "Left to macOS", "macOS (native)" | `server` `system` (`System` in JSON), `ojd controller release` |
| Handled by OpenJoystickDriver | OpenJoystickDriver reads the physical controller and shows a virtual gamepad to games. | "Served by", "OpenJoystickDriver (virtual)" | `server` `ojd` (`OJD` in JSON), `ojd controller claim` |
| Xbox USB driver | The driver that OpenJoystickDriver installs in macOS to read Xbox controllers over USB. | "driver extension", "system extension", "transport extension", "USB extension", "DriverKit", "dext" | `ojd transport-extension` |
| connection | How a controller reaches the Mac: cable, receiver, or Bluetooth. | "transport", "Wireless Link" | `connection` |
| mode | The setting that a switch or button combination on the controller selects, such as XInput or DInput. | "protocol" where it names this setting | `modes` in a controller record |

## Rules

- The command line keeps every command, flag, schema value, and error code. The entry of a term names the value it stands for, so a script reads the same output as before.
- In All Controls, the app shows the command line value beside the term. In Simple, it shows the term alone. See [Using the app](Using-the-App.md).
- An error message that names a key of a file writes the key as the file spells it, such as `persona`.
- A text that names a place in System Settings writes the name as macOS shows it, such as "Driver Extensions".
- "Protocol" keeps its meaning as the language that a controller and the Mac speak, as in `ojd protocol`.
- Each language translates a term one way. See [LOCALIZATION.md](../LOCALIZATION.md).

## Further reading

- [Using the app](Using-the-App.md)
- [Command reference](Command-Reference.md)
- [Playing games](Playing-Games.md)
