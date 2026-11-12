# OpenJoystickDriver Documentation

OpenJoystickDriver (OJD) lets you use game controllers on macOS that macOS does not support natively.

## Start here

Pick the goal that fits you.

- [Play a game with a controller](Start-Play-a-Game.md): Install OJD, connect a controller, and see it work in a game.
- [Control the Mac with a controller](Start-Control-the-Mac.md): Make controller buttons press keys, click the mouse, move the pointer, or scroll.
- [Set up OJD on several Macs](Start-Set-Up-Several-Macs.md): Read what the license and macOS allow, repeat the setup on each Mac, and copy your profiles.
- [Add support for a controller](Start-Add-Support-for-a-Controller.md): Draft, check, and install a controller record.

## About OJD

- [Getting started](Getting-Started.md): Learn what OJD is, install it, and use your first controller.
- [Using the app](Using-the-App.md): Learn the menu-bar item, the five areas of the app window, and the Settings window.
- [Testing a controller](Testing-a-Controller.md): Show live input from a controller, and test rumble and lighting.

## Controllers

- [Supported controllers](Supported-Controllers.md): See which controllers people tested, what each tier means, and how OJD treats clone and generic HID controllers.
- [Connecting controllers](Connecting-Controllers.md): Learn how USB, Bluetooth, and dongle connections differ, find the VID:PID of your controller, and use the Xbox USB driver extension.
- [Wii Remote](Wii-Remote.md): Pair a Wii Remote with macOS, and see what OJD reads from it and its extensions.
- [Support ladder](Support-Ladder.md): Support a controller with the first step that works: nothing, a patch, a record, a generator script, or source.
- [Controller records](Controller-Records.md): Add a controller that OJD does not know, or change how OJD drives a known one.
- [Writing controller mods](Writing-Controller-Mods.md): Package controllers, patches, profiles, and virtual devices in a folder, and install it with `ojd mod`.
- [Generating documents with scripts](Generating-Documents-with-Scripts.md): Write a JavaScript file that returns many records, and write them with `ojd generate`.

## Games

- [Playing games](Playing-Games.md): Learn how games see your controller, which games and apps work, and what to expect from rumble and lighting.

## Remapping

- [Remapping profiles](Remapping-Profiles.md): Create, activate, import, and export profiles.
- [Bindings and actions](Bindings-and-Actions.md): Assign buttons and actions, and use combinations, sequences, and layers.
- [Sticks, triggers, touchpad, and motion](Sticks-Triggers-Touchpad-and-Motion.md): Change how analog controls produce output.
- [Profile file reference](Profile-File-Reference.md): Read where OJD stores profiles, and their shape and limits.

## Your Mac

- [Permissions and security](Permissions-and-Security.md): Learn which macOS permissions OJD needs and how OJD protects your Mac.
- [Updating and uninstalling](Updating-and-Uninstalling.md): Get a new version, or remove OJD and its data.

## Command Line

- [Command line](Command-Line.md): Control OJD from Terminal, and read its output formats and exit codes.
- [Command reference](Command-Reference.md): Look up every `ojd` command and option.
- [Automating OpenJoystickDriver](Automating-OpenJoystickDriver.md): Use `ojd` in scripts, read its JSON output, change profiles, and drive a virtual gamepad.
- [WebRTC bridge](WebRTC-Bridge.md): Play on one Mac with a controller that is connected to another Mac.

## Help

- [Troubleshooting](Troubleshooting.md): Fix a controller that is not detected, a game that does not see the controller, and crashes.
- [Known issues](Known-Issues.md): Read current bugs and limits, with a workaround for each.
- [Error codes](Error-Codes.md): Look up the meaning of an error code and how to fix it.
- [FAQ](FAQ.md): Read short answers to common questions.
- [Glossary](Glossary.md): Look up what each term in the app and this wiki means.
- [Reporting a bug](Reporting-a-Bug.md): Learn what to include in a bug report.

## Advanced

- [Building from source](Building-from-Source.md): Build OJD yourself to get a fix before the next tester build.

## Contributor Documentation

Architecture, signing, release, and hardware test records are in the [contributor documentation](../docs/README.md).
