# Changelog Entries For Task 18.1

Entries the task workers wrote, held here until task 18.1 writes `CHANGELOG.md`.

## Added

- The endpoint takes a `ProfileRequest` line with the `Control` scope to activate, deactivate or set one value of a remapping profile, and answers a `ProfileResult`. A refusal by the service is a `Status` failure with the code that `ojd` prints and keeps the connection open. Shortcuts lists a Set Profile Value action that does the same as `ojd profile set`. See the [endpoint protocol](docs/sdk/endpoint.md#profilerequest). (6.11)

## Changed

- The app sends the driver extension activation request only after a user action: the banner button, the **Claim** button, `ojd controller claim` for a model that Apple's driver holds, or `ojd transport-extension activate`. Launch, service start and a controller arrival send none. (4.3, 4.5)
- A controller on a model that Apple's driver holds (`045E:02EA`, `045E:0B00`, `045E:0B12`) is listed as served by macOS, with **Claim**, in the Controllers list and in `ojd controller show` (`served-by` and `heldByAppleDriver`). The Microsoft models `045E:02D1`, `045E:02DD`, `045E:02E3` and `045E:0B0A` take the direct route when the extension does not own them. (4.2, 4.4)
- The driver banner shows each state of the request: running with a disabled button, needs approval with a button that opens the approval pane, cancelled, timed out, and failed with the error domain, code and text. It shows only while a connected controller uses the extension route. (4.6)
- The wiki heading `extension` is `transport-extension`. (4.7)
- A controller session reports its input as `AwaitingInput` (`awaiting-input` in `ojd controller show`, "Waiting for the first input..." in the controller detail) until its first input report, and `Healthy` after it. (3.3)

- `ojd migrate [FOLDER]` converts the documents an earlier alpha wrote (`v1alpha1` and `v1alpha2` JSON) to `v1alpha3` property lists, gives each file one verdict (`Migrated`, `Current`, `Failed`, `Foreign`), keeps each original under `Migrated/`, never overwrites a backup, and exits `E5009` when a file failed. `--dry-run` writes nothing. A file that OJD 0.5 wrote fails with "re-create it". (5.2, 5.3, 5.4, 5.6)
- The service migrates the stored documents when it starts, before any store opens, and logs each verdict. (5.5)
- The app offers Migrate wherever it reports `E5001`, and the Profiles area names an earlier alpha's `.json` profile. (5.7)
- The implementation status and `Scripts/SDK/reference_client.py` name `openjoystickdriver/v1alpha3`. (18.4)

## Fixed

- A GIP pad that announces nothing and sends its first report to an input read that is already pending gets that read before the startup writes. Not checked on hardware. (3.2)
- OJD no longer seizes the HID device of a model that a record serves over raw USB or the extension, so it leaves that device to other apps such as Steam ([#18](https://github.com/xsyetopz/OpenJoystickDriver/issues/18)). Not checked on hardware. (9.17)
