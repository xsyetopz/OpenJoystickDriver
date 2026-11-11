---
paths:
  - "**/*"
---

# generated_file_edit

Generated files change only through their generator. Edit the source, regenerate, and commit both. A bundled document is a canonical XML property list: after a hand edit, run `swift run OJDRepositoryTool format-plist <file.plist>` so the file equals what `PropertyListSerialization` writes (sorted keys, no comment, no `null`, no `date` or `data`).

| Source | Generator |
| --- | --- |
| `Resources/Protocols/*.plist` | `./Scripts/ojd catalog regenerate --write` |
| DriverKit sources | `./Scripts/ojd driverkit generate` |
| `Resources/ErrorCodes.plist` | `./Scripts/ojd errors regenerate --write` |

```text
Sources/OpenJoystickDriverKit/Resources/Protocols/nintendo-wii.plist:88:5: error: generated file edited [generated_file_edit]
note: edit Resources/Protocols/nintendo-wii.plist, then run catalog regenerate --write
```
