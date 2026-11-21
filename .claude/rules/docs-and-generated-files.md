# Docs and Generated Files

Comments, the wiki, and schema descriptions say what the code does, and change in the same commit as the behavior. History ("now", "previously", "new", "no longer") belongs only in `CHANGELOG.md`. Code is removed after a search of `Sources Tests wiki docs Resources/Schemas` finds no reference left.

Generated files change only through their generator: edit the source, regenerate, and commit both.

| Source | Generator |
| --- | --- |
| `Resources/Protocols`, `Resources/VirtualDevices`, `Resources/Controllers`, `Resources/ControllerPatches` | `just catalog-regenerate --write` |
| `Resources/ErrorCodes.plist` | `just errors-regenerate --write` |
| DriverKit sources | `just driverkit-generate` |
| `Tests/EquivalenceSnapshots` | the snapshot tests with `OJD_SNAPSHOT_WRITE=1` |

A hand-edited bundled property list is made canonical with `swift run OJDRepositoryTool format-plist <file.plist>`: sorted keys, no comment, `null`, `date`, or `data`.

```swift
/// Previously used the raw report; now reads the parsed IR state.
    ^ warning: history outside CHANGELOG.md
// fix: /// Reads the pointer from the parsed IR state.
```
