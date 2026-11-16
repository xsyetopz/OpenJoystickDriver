# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS app (AppKit shell with SwiftUI content) plus a menu-bar status item. Deployment
target macOS 12; the window uses the current macOS look where the running system provides it.

## Users

Primary: players who plug in a game controller that macOS does not support, or does not support
well, and want it to work in a game, emulator, SDL app or native macOS app. They open the window
to see whether the controller is connected and working, and to fix it when it is not.

Secondary: tinkerers who remap controls with profiles, install controller records and mods, read
diagnostics and logs, and use the `ojd` command line. Their depth stays one level down from what
players see first.

## Product Purpose

OpenJoystickDriver (OJD) is a userspace gamepad driver for macOS. The signed app hosts the runtime,
a DriverKit extension for Xbox USB controllers, and the `ojd` CLI. It reads physical controllers
over USB, Bluetooth and dongles, and publishes them to games as virtual gamepads. Success: a
connected controller works in the user's game, and when it does not, the app says why and what to do.

## Positioning

Open-source (MPL-2.0) driver that covers controllers macOS lacks, with a catalog of controller records
(about 700 bundled), user-installable records and mods, remapping profiles, and a CLI with the same
actions as the GUI.

## Operating Context

The window opens on Controllers: what is connected, whether it works, and what games see. Problems
(missing permission, driver extension not active, service not running) appear as one banner only
while they exist. Other areas: Profiles (remapping), Library (records and mods), Access (macOS
permissions and which programs may use controller data), Activity (service log, error codes).
Settings live in a separate Settings window. The status item gives quick actions per controller.

## Capabilities and Constraints

- Every GUI action has a CLI counterpart and the reverse.
- 22 locales; every user-facing string is a localization key. Right-to-left (Arabic) is supported.
- Unknown, missing or not-applicable values show a single hyphen; capabilities a controller cannot
  have (lighting, motion) are hidden rather than shown as unavailable.
- Each fact and each action appears once per screen ("one obvious way").
- Brand names Xbox and PlayStation are trademarks of their owners; the project is not affiliated.

## Brand Commitments

Name "OpenJoystickDriver", short form "OJD". Plain, direct wording that states what happens. No
binding visual identity beyond native macOS conventions; area navigation uses toolbar tabs.

## Evidence on Hand

Wiki pages under `wiki/`; screenshots of the app exist only in the user's review. No testimonials,
usage numbers or press; do not invent them.

## Product Principles

1. Working controller first: the first view answers "is my controller working, and what do games see".
2. One obvious way: one place per action and per fact; no duplicate controls or sections.
3. Problems are loud only while they exist; a healthy app is quiet.
4. Native before custom: standard macOS controls, menus and shortcuts.
5. Depth on demand: technical detail (IDs, endpoints, logs) one level down, never in the way.

## Accessibility & Inclusion

VoiceOver labels for every control (`a11y.` keys), full keyboard use, right-to-left layout, and the
system's text size, contrast and reduced-motion settings.
