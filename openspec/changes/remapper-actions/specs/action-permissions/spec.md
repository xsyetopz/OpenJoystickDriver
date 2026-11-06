## ADDED Requirements

### Requirement: REQ-50 Missing Permission Is Named

Every action that needs a permission MUST check it before it acts. Keyboard, pointer, system key, type text and macro outputs need Post Event access (Accessibility access in the app and wiki); an Apple Event to another application needs Automation access. When a permission is missing, OJD MUST NOT act, MUST show a coded error that names the permission and the action in the Access area, Activity log and `ojd log`, and MUST NOT retry or fall back.

#### Scenario: Post Event Missing

- **WHEN** a button is assigned to `SystemKey` `VolumeUp`, Post Event access is not granted and the user presses it
- **THEN** no key is sent and OJD reports an error that names Post Event access and the `VolumeUp` action

#### Scenario: Automation Denied

- **WHEN** an action sends an Apple Event to an application and Automation access for it is denied
- **THEN** OJD reports an error that names Automation access and the application, and sends nothing

### Requirement: REQ-51 Activation Preflight

Before a profile is activated, OJD MUST list the permissions that its actions need and the ones that are missing. The app MUST show the list in the activation alert, and `ojd profile activate` MUST print it. A profile with `OpenApplication`, `OpenURL`, `RunShortcut` or `TypeText` destinations MUST need a confirmation of the user at activation that lists those actions, each URL in full (a click in the app, `--confirm-actions` on the command line). An imported profile MUST NOT activate itself.

#### Scenario: Confirmation Needed

- **WHEN** the user runs `ojd profile activate` for a profile with an `OpenURL` destination and does not pass `--confirm-actions`
- **THEN** the command fails and lists the URL

#### Scenario: Permission List

- **WHEN** the user activates a profile with a keyboard destination while Post Event access is missing
- **THEN** the alert and the command output name Post Event access as missing

### Requirement: REQ-52 Permission Names Are Localized

The user-facing names of the permissions MUST be keys under `platform.macos.` in the localization catalog, because they are operating system words. Neutral keys MUST carry neutral wording. Each key MUST exist in all 22 bundles with a translator comment.

#### Scenario: Key Rules

- **WHEN** `python3 Scripts/Quality/check_localization_keys.py` runs
- **THEN** it reports no violation for the keys of this change
