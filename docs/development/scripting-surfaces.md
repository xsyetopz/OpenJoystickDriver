# Scripting surfaces

Scope: what the App Intents, the `ojd` command line, and the local endpoint each expose, and what a mod author cannot do through any of them.

Method: read the source and `wiki/Automating-OpenJoystickDriver.md` on branch `feat/0.6.0-alpha.3`. Nothing was built or run. Paths under `Sources/OpenJoystickDriver/platform/macos/Intents/` are shortened to `Intents/`, and under `Sources/OpenJoystickDriverCLI/` to `CLI/`.

## App Intents

Twelve actions, all for macOS 13 or later (`Intents/ProfileEntity.swift:7`). The actions reach the service through the `AutomationService` dependency (`Intents/ProfileEntity.swift:48-49`, `Intents/ControllerEntity.swift:51-52`). The wiki says the actions run in the app and do not use `ojd` (`wiki/Automating-OpenJoystickDriver.md:309`).

| Action | `file:line` | Takes | Returns |
|--------|-------------|-------|---------|
| Get Controllers | `Intents/ControllerIntents.swift:9`, `:26` | nothing | `[ControllerEntity]` |
| Get Battery Level | `Intents/ControllerIntents.swift:35`, `:48`, `:63` | a controller | `Int` |
| Activate Profile | `Intents/ProfileIntents.swift:8`, `:21`, `:31` | a profile | `ProfileEntity` |
| Deactivate Profile | `Intents/ProfileIntents.swift:38`, `:51`, `:61` | a profile | `ProfileEntity` |
| Set Profile Value | `Intents/ProfileIntents.swift:69`, `:85`, `:91`, `:97`, `:104` | a profile, a key, a value | `ProfileEntity` |
| Get OpenJoystickDriver Version | `Intents/AppVersionIntent.swift:7`, `:20` | nothing | `String` |
| List Mod Packages | `Intents/ModIntents.swift:9` | nothing | `[String]` |
| Install Mod Package | `Intents/ModIntents.swift:25` | a folder, replace | `String` |
| Remove Mod Package | `Intents/ModIntents.swift:56` | a name | `String` |
| Rumble Controller | `Intents/ControllerOutputIntents.swift:10` | a controller, an intensity, a duration | nothing |
| Set Player Indicator | `Intents/ControllerOutputIntents.swift:66` | a controller, a player number | nothing |
| Set Controller Light | `Intents/ControllerOutputIntents.swift:104` | a controller, a color, a brightness | nothing |

Entities the actions pass:

| Entity | `file:line` | Fields |
|--------|-------------|--------|
| `ControllerEntity` | `Intents/ControllerEntity.swift:9` | `id`, `name`, `model`, `isModelMatch` (`:19-27`) |
| `ProfileEntity` | `Intents/ProfileEntity.swift:8` | `id`, `name`, `model`, `isActive` (`:17-28`) |

The wiki states that no action is verified live in the Shortcuts app (`wiki/Automating-OpenJoystickDriver.md:323`).

## The `ojd` command line

`ojd` is an ArgumentParser root command (`CLI/Root/OJDCommand.swift:8`). It has 19 top-level subcommands (`CLI/Root/OJDCommand.swift:16-24`). The table lists each group, its subcommands, and the `commandName:` lines.

| Group | Subcommands | `file:line` |
|-------|-------------|-------------|
| `status` | none | `CLI/Commands/Status/StatusCommand.swift:12` |
| `controller` | `list`, `show`, `speaker` (`play`, `stop`), `calibrate`, `pair`, `unpair`, `claim`, `release`, `rumble`, `player`, `light`, `watch`, `capture`, `suspend`, `resume`, `disconnect` | `CLI/Commands/Controller/ControllerCommand.swift:9`, `:47`, `:134`; `ControllerSpeakerCommands.swift:9`, `:69`, `:164`; `ControllerRemappingCommands.swift:10`, `:177`, `:264`; `ControllerClaimCommand.swift:9`, `:45`; `ControllerOutputCommands.swift:133`, `:339`, `:399`; `ControllerWatchCommand.swift:81`, `:336`; `ControllerSessionCommands.swift:54`, `:101`, `:148` |
| `profile` | `list`, `show`, `create`, `duplicate`, `rename`, `delete`, `get`, `set`, `activate`, `deactivate`, `import`, `validate`, `export`, `edit`, `recover` | `CLI/Commands/Profile/ProfileCommand.swift:9`, `:68`, `:148`, `:193`, `:359`, `:407`, `:449`; `ProfileValueCommands.swift:155`, `:214`; `ProfileActivationCommands.swift:10`, `:89`; `ProfileFileCommands.swift:32`, `:104`, `:211`, `:313`; `ProfileRecoverCommand.swift:12` |
| `binding` | `list`, `set`, `clear` | `CLI/Commands/Binding/BindingCommand.swift:9`, `:49`, `:154`, `:266` |
| `macro` | `list`, `show`, `set`, `remove` | `CLI/Commands/Macro/MacroCommand.swift:9`, `:135`, `:210`, `:249`, `:340` |
| `virtual` | `show`, `set`, `reset`, `launch`, `feed`, `export-mapping` | `CLI/Commands/Virtual/VirtualCommand.swift:10`, `:116`, `:277`, `:332`; `VirtualLaunchCommand.swift:10`; `VirtualFeedCommand.swift:10`; `VirtualExportMappingCommand.swift:48` |
| `service` | `start`, `stop`, `wait` | `CLI/Commands/Service/ServiceCommand.swift:10`, `:52`, `:109`, `:167` |
| `record` | `list`, `show`, `validate`, `install`, `remove`, `draft`, `test` | `CLI/Commands/Record/RecordCommand.swift:9`, `:33`, `:95`; `RecordFileCommands.swift:83`, `:143`, `:258`; `RecordDraftCommand.swift:10`; `RecordTestCommand.swift:12` |
| `mod` | `validate`, `install`, `list`, `remove` | `CLI/Commands/Mod/ModCommand.swift:7`, `:10-12`; `ModFileCommands.swift:14`, `:56`, `:144`, `:187` |
| `permission` | `list`, `request` | `CLI/Commands/Permission/PermissionCommand.swift:10`, `:54`, `:130` |
| `transport-extension` | `status`, `activate`, `deactivate` | `CLI/Commands/TransportExtension/TransportExtensionCommand.swift:10`, `:53`, `:178`, `:207` |
| `setting` | `list`, `get`, `set`, `reset`, `test-notification` | `CLI/Commands/Setting/SettingCommand.swift:10`, `:127`, `:173`, `:210`, `:284`, `:347` |
| `config` | `show`, `set`, `unset` | `CLI/Commands/Config/ConfigCommand.swift:9`, `:26`; `ConfigChangeCommands.swift:10`, `:60` |
| `access` | `status`, `enable`, `disable`, `list`, `grant`, `revoke`, `web` (`enable`, `disable`) | `CLI/Commands/Access/AccessCommand.swift:10`, `:61`, `:138`, `:178`, `:202`; `AccessGrantCommand.swift:61`, `:278`; `AccessWebCommand.swift:9`, `:30`, `:105` |
| `log` | `path`, `show`, `export` | `CLI/Commands/Log/LogCommand.swift:9`, `:30`, `:64`; `LogExportCommand.swift:10` |
| `diagnose` | none | `CLI/Commands/Diagnose/DiagnoseCommand.swift:9` |
| `update` | `check` | `CLI/Commands/Update/UpdateCommand.swift:9`, `:26` |
| `explain` | none | `CLI/Commands/Explain/ExplainCommand.swift:12` |
| `migrate` | none | `CLI/Commands/Migrate/MigrateCommand.swift:9` |

The `mod` group handles a package folder with a `mod.plist` manifest and `Controllers`, `Profiles`, and `VirtualDevices` folders. The service applies a change when the installed folder changes. The group needs no running service (`Sources/OpenJoystickDriverKit/Resources/en-US.lproj/Localizable.strings` key `cli.mod.group.discussion` at line 2663; the schema is `Resources/Schemas/mod-package.schema.json`).

The wiki names the output and prompt options as `--json` and `--no-input`, and scripts read JSON with them (`wiki/Automating-OpenJoystickDriver.md:25-35`).

No command named `generate` exists under `CLI/`: `grep -rn '"generate"' Sources/OpenJoystickDriverCLI` finds nothing. The design text plans `ojd generate` (`openspec/changes/0-6-0-alpha-3/design.md`, decision D2).

## The local endpoint

The endpoint is a local socket, plus a WebSocket on `127.0.0.1` that is turned on separately (`wiki/Automating-OpenJoystickDriver.md:61-63`, `:138-141`). It is off by default and serves only granted programs (`:63`). A line is a JSON object of at most 64 KiB (`:69`).

### Lines a client sends

| Line | `file:line` | Use |
|------|-------------|-----|
| `Hello` | `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointMessages.swift:25` | names `scopes`, and for a token a `tokenName` and `proof` (`:37-42`) |
| `Subscription` | `EndpointMessages.swift:27`, `:44` | asks for the `Controllers`, `Profiles`, or `Mods` stream; `output` adds the virtual gamepad values to `Controllers` only (`:46`; `EndpointServer+Lists.swift:5`) |
| `FeedRequest` | `EndpointMessages.swift:29`, `:48` | asks for a virtual gamepad with persona `as` |
| `ProfileRequest` | `EndpointMessages.swift:31`, `:57`; `EndpointServer+Requests.swift:14` | activates, deactivates, or sets one value of a profile; answered with `ProfileResult` |
| `ModList` | `EndpointMessages.swift:34`; `EndpointServer+Requests.swift:19`, `:29` | lists the installed mod packages with the `Read` scope; answered with `Mods` |
| `OutputRequest` | `EndpointMessages.swift:36`, `:135`; `EndpointServer+Requests.swift:35`, `:63` | rumbles, sets the player number, or sets the light of one controller with the `Control` scope; answered with `OutputResult` |
| `Frame` | `Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointServer+Feed.swift:98` | one frame for the virtual gamepad |
| `KeepAlive` | `EndpointServer+Feed.swift:98` | counts as activity |
| `Drain` | `EndpointServer+Feed.swift:98`, `:107` | asks for `Drained` after earlier frames have played |

### Lines the endpoint sends

| Line | `file:line` | Content |
|------|-------------|---------|
| `Challenge` | `EndpointMessages.swift:11`, `:13` | 32-byte nonce |
| `Welcome` | `EndpointMessages.swift:56-60` | service version, granted scopes |
| `ADDED`, `MODIFIED`, `DELETED` | `wiki/Automating-OpenJoystickDriver.md:75` | the watch lines of `ojd controller watch --all --json` |
| `ProfileResult` | `EndpointMessages.swift:120` | the profile after a `ProfileRequest` |
| `Mods` | `EndpointMessages.swift:133`; `EndpointServer+Requests.swift:30` | the installed mod packages, after a `ModList` |
| `Profiles` | `EndpointMessages.swift:265`; `EndpointServer+Handshake.swift:106` | the saved profiles, after a `Profiles` subscription and each change |
| `OutputResult` | `EndpointMessages.swift:237`; `EndpointServer+Requests.swift:41` | the commands that ran, after an `OutputRequest` |
| `FeedSession` | `EndpointMessages.swift:68-70` | the persona of the virtual gamepad |
| `Drained` | `EndpointMessages.swift:78`; `EndpointServer+Feed.swift:63` | every earlier frame has played |
| `RumbleCommand` | `EndpointMessages.swift:82-103` | rumble command a game sent to the virtual gamepad |
| `Status` failure | `EndpointMessages.swift:133-151` | `code` `E1001` to `E1011`, `message` (`wiki/Automating-OpenJoystickDriver.md:193`) |

### Scopes, streams, and limits

| Item | `file:line` | Value |
|------|-------------|-------|
| Scope `Read` | `Sources/OpenJoystickDriverKit/ApplicationService/Payloads/AccessPayloads.swift:7` | receive controller events |
| Scope `Control` | `AccessPayloads.swift:9`; checked at `EndpointServer+Handshake.swift:62` | drive a virtual gamepad |
| Stream | `EndpointServer+Handshake.swift:82`; `EndpointServer+Lists.swift:5`, `:19` | `Controllers`, `Profiles`, and `Mods`; the last two send the list on change |
| Personas | `wiki/Automating-OpenJoystickDriver.md:214` | `Generic` and `SDLCompatible` |
| Token with origins | `AccessTokenGrant.swift:202` (`Sources/OpenJoystickDriverService/Runtime/Endpoint/`) | cannot hold `Control` |
| Connections | `wiki/Automating-OpenJoystickDriver.md:193` | 8 on the socket, 8 on the WebSocket |
| Handshake time | `wiki/Automating-OpenJoystickDriver.md:74` | `Hello` within 5 seconds |

## What a mod author cannot do through any surface

Each item rests on the tables above. A surface that is not listed for an item does not offer it.

1. Run author code in the service or as part of `ojd`. `ojd` has no `generate` command, and the endpoint and the intents hold no code upload. The author's program runs outside and calls in.
2. Add a protocol family. No surface takes a family name or a description document into the closed lists of `docs/development/document-defined-families.md`. `ojd record install` takes a controller record, not a family.
3. Change a binding or macro through the endpoint. The endpoint takes `Hello`, `Subscription`, `FeedRequest`, `ProfileRequest`, `ModList`, `OutputRequest`, `Frame`, `KeepAlive`, and `Drain` only (`EndpointMessages.swift:23-31`, `EndpointServer+Feed.swift:98`); `ProfileRequest` activates, deactivates, or sets one value of a profile.
4. Change a binding or macro through the intents. The intents list controllers, read a battery level, activate or deactivate a profile, set one value of a profile, list, install, or remove a mod package, rumble a controller, set its player number or light, and return a version.
5. Validate a mod package through the intents or the endpoint. The intents list, install and remove a package, and the endpoint lists them; only `ojd mod validate` validates a folder without installing it. An install through an intent runs the validation that `ojd mod install` runs.
6. Drive the speaker through the endpoint or the intents. Only `ojd controller speaker` does it (`CLI/Commands/Controller/ControllerSpeakerCommands.swift:69`). Rumble, player numbers, and lights have an endpoint message and an intent each.
7. Receive an event inside the service. The endpoint streams `Controllers` to an outside program, and no surface takes a handler that the service runs.
8. Subscribe to anything but `Controllers`, `Profiles`, and `Mods` (`EndpointServer+Handshake.swift:82`). No stream carries logs, bindings, or macros.
9. Use the endpoint without a grant by the user. The program needs `ojd access grant` first, and a token with origins cannot hold `Control` (`AccessTokenGrant.swift:202`).
10. Choose a virtual gamepad persona beyond `Generic` and `SDLCompatible` through the endpoint (`wiki/Automating-OpenJoystickDriver.md:214`).
11. Call an intent from a program without Shortcuts. The wiki points to `shortcuts run` and `shortcuts://` links (`wiki/Automating-OpenJoystickDriver.md:320-321`).

Gaps for a mod author: 11, with item 6 narrowed to the speaker.
