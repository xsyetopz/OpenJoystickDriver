# OpenJoystickDriver shortcuts

Signed shortcut files that run the App Intents of `com.openjoystickdriver`. Import each once in the Shortcuts app; every later run is headless through `shortcuts run`.

Status: each file is signed (`shortcuts sign --mode anyone`) but none was imported or run, because importing opens the Shortcuts window. Two parts of the format are written from memory, not from a file on disk: the entity parameter value (`controller`) and the `is.workflow.actions.output` action with `WFOutput`. The action identifier, a text parameter, and a plain value parameter follow `SummarizePDF.wflow` in `WorkflowKit.framework`.

| File | Intent | Input | Output |
| --- | --- | --- | --- |
| `OJD List Mod Packages.shortcut` | `ListModsIntent` | none | installed package names |
| `OJD Install Mod Package.shortcut` | `InstallModIntent` | text: folder that holds `mod.plist`; `replace` is false | package name |
| `OJD Remove Mod Package.shortcut` | `RemoveModIntent` | text: package name | package name |
| `OJD Rumble Controller.shortcut` | `RumbleControllerIntent` | none; controller `045e:02e0`, intensity 180, duration 0.45 | `done` |
| `OJD Set Player Indicator.shortcut` | `SetPlayerIndicatorIntent` | none; controller `045e:02e0`, player 1 | `done` |
| `OJD Set Controller Light.shortcut` | `SetControllerLightIntent` | none; controller `045e:02e0`, color `FF0000`, brightness 128 | `done` |

Not expressed: Activate Profile, Deactivate Profile, Set Profile Value, and the wiki example. Each takes a `ProfileEntity` whose ID is the UUID of a profile in the user's library, and no fixture holds one.

## Run

```sh
shortcuts run "OJD List Mod Packages" --output-path mods.txt
printf 'ojd-sample' > name.txt
shortcuts run "OJD Remove Mod Package" --input-path name.txt --output-path removed.txt
shortcuts run "OJD Install Mod Package" --input-path folder.txt --output-path installed.txt
shortcuts run "OJD Rumble Controller" --output-path out.txt
shortcuts run "OJD Set Player Indicator" --output-path out.txt
shortcuts run "OJD Set Controller Light" --output-path out.txt
```
