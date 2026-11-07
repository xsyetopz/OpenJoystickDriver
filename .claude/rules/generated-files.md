---
paths:
  - "**/*"
---

# Edit the source, then regenerate

A generated file changes only when its generator runs. Edit the source the generator reads, run the generator, and commit both. A hand-edit to a generated copy drifts from its source, and the next regenerate or `--check` throws it away or fails.

| Source | Command | Generated output |
| --- | --- | --- |
| `Resources/Protocols/*.json`, catalog sources | `./Scripts/ojd catalog regenerate --write` | `Sources/OpenJoystickDriverKit/Resources/Protocols/`, the `Controllers` files |
| DriverKit sources | `./Scripts/ojd driverkit generate` | the DriverKit files |
| `Resources/ErrorCodes.json` | `./Scripts/ojd errors regenerate --write` | the error code files and their strings |

- Before you edit a file, check whether a generator writes it. When it does, edit the source in the table above.
- After the generator runs, commit both the source and the output, and confirm that `--check` reports no diff.

GREEN: a new Wii mode goes into the repo-root `Resources/Protocols/nintendo-wii.json`. `./Scripts/ojd catalog regenerate --write` copies it into the Sources copy, and `catalog regenerate --check` passes.

RED: the mode-55 `modeChoice` went straight into `Sources/OpenJoystickDriverKit/Resources/Protocols/nintendo-wii.json`. The repo-root source never got it, so `catalog regenerate --check` failed with rc=1 until the entry was moved to the source.
