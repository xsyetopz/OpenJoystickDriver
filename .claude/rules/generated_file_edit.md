---
paths:
  - "**/*"
---

# generated_file_edit

Generated files change only through their generator. Edit the source, regenerate, and commit both.

| Source | Generator |
| --- | --- |
| `Resources/Protocols/*.json` | `./Scripts/ojd catalog regenerate --write` |
| DriverKit sources | `./Scripts/ojd driverkit generate` |
| `Resources/ErrorCodes.json` | `./Scripts/ojd errors regenerate --write` |

```text
Sources/OpenJoystickDriverKit/Resources/Protocols/nintendo-wii.json:88:5: error: generated file edited [generated_file_edit]
note: edit Resources/Protocols/nintendo-wii.json, then run catalog regenerate --write
```
