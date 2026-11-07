---
paths:
  - "**/*"
---

# generated_file_edit

- **Severity:** error
- **Description:** Edit the generator's source, run the generator, and commit both. A hand-edit to a generated file fails `--check` and is lost on the next regenerate.

| Source | Generator | Output |
| --- | --- | --- |
| `Resources/Protocols/*.json` | `./Scripts/ojd catalog regenerate --write` | `Sources/OpenJoystickDriverKit/Resources/Protocols/`, `Controllers` files |
| DriverKit sources | `./Scripts/ojd driverkit generate` | DriverKit files |
| `Resources/ErrorCodes.json` | `./Scripts/ojd errors regenerate --write` | error code files and strings |

Non-triggering:

```text
edit   Resources/Protocols/nintendo-wii.json
run    ./Scripts/ojd catalog regenerate --write
commit both files; catalog regenerate --check passes
```

Triggering:

```text
edit   ↓Sources/OpenJoystickDriverKit/Resources/Protocols/nintendo-wii.json
catalog regenerate --check → rc=1
```
