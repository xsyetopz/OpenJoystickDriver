# States and Proof

## Contents

- [Required states](#required-states)
- [State tests](#state-tests)
- [Localized copy](#localized-copy)
- [Proof points](#proof-points)

## Required states

**Definition.** Each async surface models every state that applies to it, as an enum case or explicit property, rather than as a combination of optionals:

- loading, and cancellation;
- empty;
- unavailable, which covers a runtime not running, a missing system extension, and an IPC failure;
- permission denied, and requesting;
- saving, and conflict;
- stale, where an older response must not replace a newer one;
- failed, with a retry or recovery action;
- success.

The rules in "State And Permission Rules" of `contributing/development/menu-bar-settings-architecture.md` apply:

- A superseded permission request does not open System Settings.
- A denied result opens the matching recovery pane.
- Only an authoritative follow-up read establishes a grant.
- A transient failure keeps the last authoritative inventory.

**Use when.** Every view that awaits the gateway.

**Do not use when.** The view is purely static, such as About.

**Example.** A request carries a generation number. The view model publishes the response only when that generation is still current, and the controller's runtime identifier still matches.

**Cost removed.** A late response from a disconnected controller would otherwise overwrite the selected controller's state.

**Verify.** A test sends two requests, completes them in reverse order, and asserts that the newer state wins (see `PermissionGenerationTests.swift`).

## State tests

**Definition.** Swift Testing tests drive a `@MainActor` view model against the `GatewayStub` actor, and assert on published state, not rendered text.

**Use when.** Any change to a view model or coordinator.

**Do not use when.** Layout, spacing, and appearance cannot be asserted this way. Check them in the running app.

**Verify.** `swift test --filter OpenJoystickDriverPresentationTests.<Type>` fails without the change and passes with it.

## Localized copy

**Definition.** Every user-visible string, including tooltips, accessibility labels, and compact symbol actions, is a key in `Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings` (plurals go in `.stringsdict`). Views read it with `OJDLocalized.string("key", fallback: "English")`.

The punctuation and translation rules are in `LOCALIZATION.md`:

- English uses ASCII `...`.
- Use sentence case, and one key per label.
- Keep placeholders and runtime identifiers unchanged in every locale.

**Use when.** Adding or changing copy.

**Do not use when.** The value is a runtime identifier, such as a controller name, a VID/PID, or a path. Show it verbatim.

**Verify.** Run `swift test --filter OpenJoystickDriverKitTests.LocalizationTests`. To check truncation, put a long-string locale such as German or Finnish first in the macOS languages, then run the app.

## Proof points

Check these in the running app. Report each one as checked or unverified.

- Opening Settings twice gives one window, and its geometry and pane persist across relaunch.
- Every control is reachable with Full Keyboard Access. Escape cancels capture and sheets.
- VoiceOver announces a useful name for every non-text control, and the full value of any truncated text.
- Light and dark appearance, increased contrast, and reduced motion all render.
- The minimum window size shows long localized strings without clipping.
- Newer APIs sit behind `#available`, with a macOS 12 path. Profile alerts use one `alert(item:)`, and capture uses one `sheet(item:)`.
- Interactive targets are at least 20 points, and 28 is preferred.
- Permission copy links to System Settings, and does not claim access that was not observed.
