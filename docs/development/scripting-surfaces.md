# Scripting Surfaces

What the App Intents, the `ojd` command line, and the local endpoint expose, and what a mod author cannot do.

Method: source and `wiki/Automating-OpenJoystickDriver.md` on branch `feat/0.6.0-alpha.3`, read without a build or run. `Intents/` is `Sources/OpenJoystickDriver/platform/macos/Intents/`. `CLI/` is `Sources/OpenJoystickDriverCLI/`.

## App Intents

Twelve actions, macOS 13 or later (`Intents/ProfileEntity.swift:7`). They use the `AutomationService` dependency (`Intents/ProfileEntity.swift:48-49`, `Intents/ControllerEntity.swift:51-52`). They run in the app, not through `ojd` (`wiki/Automating-OpenJoystickDriver.md:309`).

| Action | file:line | Takes | Returns |
| -------- | ------------- | ------- | --------- |
| Get Controllers | Intents/ControllerIntents.swift:9, :26 | nothing | `[ControllerEntity]` |
| Get Battery Level | Intents/ControllerIntents.swift:35, :48, :63 | a controller | `Int` |
| Activate Profile | Intents/ProfileIntents.swift:8, :21, :31 | a profile | `ProfileEntity` |
| Deactivate Profile | Intents/ProfileIntents.swift:38, :51, :61 | a profile | `ProfileEntity` |
| Set Profile Value | Intents/ProfileIntents.swift:69, :85, :91, :97, :104 | a profile, a key, a value | `ProfileEntity` |
| Get OpenJoystickDriver Version | Intents/AppVersionIntent.swift:7, :20 | nothing | `String` |
| List Mod Packages | Intents/ModIntents.swift:9 | nothing | `[String]` |
| Install Mod Package | Intents/ModIntents.swift:25 | a folder, replace | `String` |
| Remove Mod Package | Intents/ModIntents.swift:56 | a name | `String` |
| Rumble Controller | Intents/ControllerOutputIntents.swift:10 | a controller, an intensity, a duration | nothing |
| Set Player Indicator | Intents/ControllerOutputIntents.swift:66 | a controller, a player number | nothing |
| Set Controller Light | Intents/ControllerOutputIntents.swift:104 | a controller, a color, a brightness | nothing |

Entities the actions pass:

| Entity | file:line | Fields |
| -------- | ------------- | -------- |
| `ControllerEntity` | Intents/ControllerEntity.swift:9 | `id`, `name`, `model`, `isModelMatch` (`:19-27`) |
| `ProfileEntity` | Intents/ProfileEntity.swift:8 | `id`, `name`, `model`, `isActive` (`:17-28`) |

The wiki lists actions that ran through `shortcuts run` ("Use Shortcuts" in the wiki page).

## The `ojd` Command Line

`ojd` is an ArgumentParser root command (`CLI/Root/OJDCommand.swift:8`) with 21 top-level subcommands (`:16-26`). The table lists each group, its subcommands, and the `commandName:` lines.

| Group | Subcommands | file:line |
| ------- | ------------- | ------------- |
| `status` | none | CLI/Commands/Status/StatusCommand.swift:12 |
| `controller` | `list`, `show`, `speaker` (`play`, `stop`), `calibrate`, `pair`, `unpair`, `claim`, `release`, `rumble`, `player`, `light`, `watch`, `capture`, `suspend`, `resume`, `disconnect` | CLI/Commands/Controller/ControllerCommand.swift:9, :47, :134; ControllerSpeakerCommands.swift:9, :69, :164; ControllerRemappingCommands.swift:10, :177, :264; ControllerClaimCommand.swift:9, :45; ControllerOutputCommands.swift:133, :339, :399; ControllerWatchCommand.swift:81, :336; ControllerSessionCommands.swift:54, :101, :148 |
| `profile` | `list`, `show`, `create`, `duplicate`, `rename`, `delete`, `get`, `set`, `activate`, `deactivate`, `import`, `validate`, `export`, `edit`, `recover` | CLI/Commands/Profile/ProfileCommand.swift:9, :68, :148, :193, :359, :407, :449; ProfileValueCommands.swift:155, :214; ProfileActivationCommands.swift:10, :89; ProfileFileCommands.swift:32, :104, :211, :313; ProfileRecoverCommand.swift:12 |
| `binding` | `list`, `set`, `clear` | CLI/Commands/Binding/BindingCommand.swift:9, :49, :154, :266 |
| `macro` | `list`, `show`, `set`, `remove` | CLI/Commands/Macro/MacroCommand.swift:9, :135, :210, :249, :340 |
| `virtual` | `show`, `set`, `reset`, `launch`, `feed`, `export-mapping` | CLI/Commands/Virtual/VirtualCommand.swift:10, :116, :277, :332; VirtualLaunchCommand.swift:10; VirtualFeedCommand.swift:10; VirtualExportMappingCommand.swift:48 |
| `service` | `start`, `stop`, `wait` | CLI/Commands/Service/ServiceCommand.swift:10, :52, :109, :167 |
| `record` | `list`, `show`, `validate`, `install`, `remove`, `draft`, `test` | CLI/Commands/Record/RecordCommand.swift:9, :33, :95; RecordFileCommands.swift:83, :143, :258; RecordDraftCommand.swift:10; RecordTestCommand.swift:12 |
| `mod` | `validate`, `install`, `list`, `remove` | CLI/Commands/Mod/ModCommand.swift:7, :10-12; ModFileCommands.swift:14, :56, :144, :187 |
| `permission` | `list`, `request` | CLI/Commands/Permission/PermissionCommand.swift:10, :54, :130 |
| `transport-extension` | `status`, `activate`, `deactivate` | CLI/Commands/TransportExtension/TransportExtensionCommand.swift:10, :53, :178, :207 |
| `setting` | `list`, `get`, `set`, `reset`, `test-notification` | CLI/Commands/Setting/SettingCommand.swift:10, :127, :173, :210, :284, :347 |
| `config` | `show`, `set`, `unset` | CLI/Commands/Config/ConfigCommand.swift:9, :26; ConfigChangeCommands.swift:10, :60 |
| `access` | `status`, `enable`, `disable`, `list`, `grant`, `revoke`, `web` (`enable`, `disable`) | CLI/Commands/Access/AccessCommand.swift:10, :61, :138, :178, :202; AccessGrantCommand.swift:61, :278; AccessWebCommand.swift:9, :30, :105 |
| `log` | `path`, `show`, `export` | CLI/Commands/Log/LogCommand.swift:9, :30, :64; LogExportCommand.swift:10 |
| `diagnose` | none | CLI/Commands/Diagnose/DiagnoseCommand.swift:9 |
| `update` | `check` | CLI/Commands/Update/UpdateCommand.swift:9, :26 |
| `explain` | none | CLI/Commands/Explain/ExplainCommand.swift:12 |
| `migrate` | none | CLI/Commands/Migrate/MigrateCommand.swift:9 |
| `protocol` | `validate`, `install`, `list` | CLI/Commands/Protocol/ProtocolCommand.swift:9; ProtocolSubcommands.swift:14, :50, :124 |
| `generate` | none | CLI/Commands/Generate/GenerateCommand.swift:9 |

`ojd mod` handles a package folder with a `mod.plist` manifest and `Controllers`, `Profiles`, and `VirtualDevices` folders. The service applies changes to the installed folder. The group works without a running service (`Localizable.strings` key `cli.mod.group.discussion`, line 2663; schema `Resources/Schemas/mod-package.schema.json`).

Scripts read JSON with `--json` and skip prompts with `--no-input` (`wiki/Automating-OpenJoystickDriver.md:25-35`).

`ojd generate <SCRIPT>` runs a `.js` generator in a helper process with no file or network access, checks the documents it returns, and writes each as a property list in `--output` (`ojd generate --help`). The helper does not run in the service.

## The Local Endpoint

The endpoint is a local socket. A WebSocket on `127.0.0.1` is enabled separately (`wiki/Automating-OpenJoystickDriver.md:61-63`, `:138-141`). It is off by default and serves only granted programs (`:63`). A line is a JSON object of at most 64 KiB (`:69`).

### Lines a Client Sends

| Line | file:line | Use |
| ------ | ------------- | ----- |
| `Hello` | Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointMessages.swift:25 | names `scopes`, and for a token a `tokenName` and `proof` (`:37-42`) |
| `Subscription` | EndpointMessages.swift:27, :44 | asks for the `Controllers`, `Profiles`, or `Mods` stream; `output` adds the virtual gamepad values to `Controllers` only (`:46`; `EndpointServer+Lists.swift:5`) |
| `FeedRequest` | EndpointMessages.swift:29, :48 | asks for a virtual gamepad with persona `as` |
| `ProfileRequest` | EndpointMessages.swift:31, :57; EndpointServer+Requests.swift:14 | activates, deactivates, or sets one value of a profile; answered with `ProfileResult` |
| `ModList` | EndpointMessages.swift:34; EndpointServer+Requests.swift:19, :29 | lists the installed mod packages with the `Read` scope; answered with `Mods` |
| `OutputRequest` | EndpointMessages.swift:36, :135; EndpointServer+Requests.swift:35, :63 | rumbles, sets the player number, or sets the light of one controller with the `Control` scope; answered with `OutputResult` |
| `Frame` | Sources/OpenJoystickDriverService/Runtime/Endpoint/EndpointServer+Feed.swift:98 | one frame for the virtual gamepad |
| `KeepAlive` | EndpointServer+Feed.swift:98 | counts as activity |
| `Drain` | EndpointServer+Feed.swift:98, :107 | asks for `Drained` after earlier frames have played |

### Lines the Endpoint Sends

| Line | file:line | Content |
| ------ | ------------- | --------- |
| `Challenge` | EndpointMessages.swift:11, :13 | 32-byte nonce |
| `Welcome` | EndpointMessages.swift:56-60 | service version, granted scopes |
| `ADDED`, `MODIFIED`, `DELETED` | wiki/Automating-OpenJoystickDriver.md:75 | the watch lines of `ojd controller watch --all --json` |
| `ProfileResult` | EndpointMessages.swift:120 | the profile after a `ProfileRequest` |
| `Mods` | EndpointMessages.swift:133; EndpointServer+Requests.swift:30 | the installed mod packages, after a `ModList` |
| `Profiles` | EndpointMessages.swift:265; EndpointServer+Handshake.swift:106 | the saved profiles, after a `Profiles` subscription and each change |
| `OutputResult` | EndpointMessages.swift:237; EndpointServer+Requests.swift:41 | the commands that ran, after an `OutputRequest` |
| `FeedSession` | EndpointMessages.swift:68-70 | the persona of the virtual gamepad |
| `Drained` | EndpointMessages.swift:78; EndpointServer+Feed.swift:63 | every earlier frame has played |
| `RumbleCommand` | EndpointMessages.swift:82-103 | rumble command a game sent to the virtual gamepad |
| `Status` failure | EndpointMessages.swift:133-151 | `code` `E1001` to `E1011`, `message` (`wiki/Automating-OpenJoystickDriver.md:193`) |

### Scopes, Streams, and Limits

| Item | file:line | Value |
| ------ | ------------- | ------- |
| Scope `Read` | Sources/OpenJoystickDriverKit/ApplicationService/Payloads/AccessPayloads.swift:7 | receive controller events |
| Scope `Control` | AccessPayloads.swift:9; checked at EndpointServer+Handshake.swift:62 | drive a virtual gamepad |
| Stream | EndpointServer+Handshake.swift:82; EndpointServer+Lists.swift:5, :19 | `Controllers`, `Profiles`, and `Mods`; the last two send the list on change |
| Personas | docs/sdk/endpoint.md, FeedRequest | `Generic`, `SDLCompatible`, and `GameControllerCompatible` for a client with `Control`; any other id is refused with `E1003` |
| Token with origins | AccessTokenGrant.swift:202 (Sources/OpenJoystickDriverService/Runtime/Endpoint/) | cannot hold `Control` |
| Connections | wiki/Automating-OpenJoystickDriver.md:193 | 8 on the socket, 8 on the WebSocket |
| Handshake time | wiki/Automating-OpenJoystickDriver.md:74 | `Hello` within 5 seconds |

## What a Mod Author Cannot Do Through Any Surface

1. Run author code in the service. The endpoint and intents take no code. `ojd` runs only the `ojd generate` script, in a helper process.
2. Add a protocol family through the endpoint or intents. Only `ojd protocol install` takes a protocol description (see `docs/development/document-defined-families.md`). `ojd record install` takes a controller record.
3. Change a binding or macro through the endpoint. It takes only `Hello`, `Subscription`, `FeedRequest`, `ProfileRequest`, `ModList`, `OutputRequest`, `Frame`, `KeepAlive`, and `Drain` (`EndpointMessages.swift:23-31`, `EndpointServer+Feed.swift:98`).
4. Change a binding or macro through the intents. They read controllers and battery, return a version, activate a profile or set one value, manage mod packages, and drive rumble, player number, and light.
5. Validate a mod package through the intents or endpoint. Only `ojd mod validate` validates a folder without installing it. An intent install runs the validation `ojd mod install` runs.
6. Drive the speaker through the endpoint or intents. Only `ojd controller speaker` does (`CLI/Commands/Controller/ControllerSpeakerCommands.swift:69`).
7. Receive an event inside the service. No surface takes a handler the service runs.
8. Subscribe to a stream beyond `Controllers`, `Profiles`, and `Mods` (`EndpointServer+Handshake.swift:82`), such as logs, bindings, or macros.
9. Use the endpoint without a user grant. The program needs `ojd access grant` first, and a token with origins cannot hold `Control` (`AccessTokenGrant.swift:202`).
10. Choose a virtual gamepad persona the service does not publish (see "Tried Against the Installed Build").
11. Call an intent without Shortcuts. The wiki points to `shortcuts run` and `shortcuts://` links (`wiki/Automating-OpenJoystickDriver.md:320-321`).

## Tried Against the Installed Build

These ran against `/Applications/OpenJoystickDriver.app`, build `8456f9de8665`, through the socket with a token holding `Read` and `Control`. The endpoint was off, with no grant or token, before and after. The scripts used a scratch profile and mod package, then removed both. No controller was connected.

| Surface | Result |
| --- | --- |
| `ProfileRequest` | `Activate`, `Set` (`name`), and `Deactivate` each answered a `ProfileResult`. An unknown profile got `E2012` and the connection stayed open. A `Set` without `value` got `E1003`. A `Read`-only client got `E1002`. |
| `ModList` | `Mods` was empty, listed `scratch-trial` after `ojd mod install` on the same connection, and was empty after `ojd mod remove`. A `Control`-only client got `E1002`. |
| `OutputRequest` | The refusal works, but the run shows no delivery. With the 8BitDo Ultimate 2C served over Bluetooth LE by `HIDDescriptor`, `Rumble`, `Player` and `Light` each got `E2013` ("has no rumble motor", "no player indicator lights", "no programmable light color"). `ojd controller rumble`, `player` and `light` print the same code and text. An unknown controller got `E2012`, and an out-of-range `duration` got `E1003`. With the 2C on its receiver as `2DC8:310A`, `Rumble` and `Player` were delivered and `Light` got `E2013` (`evidence/scripting/output_request-310A.txt`). |
| `Profiles` and `Mods` subscriptions | Each sent the list at once and again after each change made through `ojd`. `output` on `Profiles` and an unknown stream got `E1003`. |
| Personas | `Generic`, `SDLCompatible` and `GameControllerCompatible` each answered a `FeedSession`, and a frame and a `Drain` answered `Drained`. `DualShock` got `E1003` with the accepted personas, and a `Read`-only client got `E1002`. |
| App Intents | Through shortcuts built in the Shortcuts app and run with `shortcuts run` (`evidence/scripting/shortcuts.sh`, `shortcuts.txt`): List, Install, and Remove Mod Package each exit 0 and agree with `ojd mod list`. Install takes its folder as a `file://` URL, and a plain path fails with "Invalid URL". Set Controller Light refuses the 2C with the text `ojd controller light` prints. Rumble Controller and Set Player Indicator, fed the first item of Get Controllers, each exit 0 on the 2C. The run has no capture of the motors or the indicator. Set Profile Value renames the chosen profile to its input, and `ojd profile list` shows the changed name. |

## Further Reading

- [SDK Endpoint](../sdk/endpoint.md)
- [Document-Defined Protocol Families](document-defined-families.md)
- [Automating OpenJoystickDriver](../../wiki/Automating-OpenJoystickDriver.md)
