# Mod Package Manifest

A package is a folder with `mod.plist` and up to four subfolders. It holds settings files only; OJD never runs or copies a script from it.

```text
ojd-sample/
  mod.plist
  Controllers/1209-0001.plist
  Profiles/sample-pad.plist
  VirtualDevices/1209-0001.plist
```

## Subfolders

| Folder | Holds | File name |
| --- | --- | --- |
| `Controllers/` | `Controller` and `ControllerPatch` files | `vvvv-pppp.plist`; patches `vvvv-pppp.patch.plist`, `model-vvvv-pppp.patch.plist`, or `all.patch.plist` |
| `Profiles/` | profiles | `.plist` files, such as `sample-pad.plist` |
| `VirtualDevices/` | `VirtualDevice` files | `vvvv-pppp.plist`, or `vvvv-pppp-U-UNIT.plist` for one controller |
| `Protocols/` | protocol descriptions | `FamilyName.plist`, UpperCamelCase, not a built-in family |

Hex in file names is lowercase.

## Manifest Keys

| Key | Rule |
| --- | --- |
| `apiVersion` | `openjoystickdriver/v1alpha4` |
| `kind` | `ModPackage` |
| `name` | lowercase letters, digits, hyphens |
| `version` | SemVer, no `v` prefix |
| `author` | non-empty text |
| `requires.minimum` | first OJD version the package runs on |
| `requires.below` | optional; first version too high |
| `controllers` | `Controller` files in `Controllers/` |
| `patches` | `ControllerPatch` files in `Controllers/` |
| `profiles` | files in `Profiles/` |
| `virtualDevices` | files in `VirtualDevices/` |
| `protocols` | files in `Protocols/` |

At least one list is present, and each present list names a file. Every file in a subfolder is listed, and every listed file exists.

## Refusals

| Code | Cause |
| --- | --- |
| E4001 | unknown manifest key, such as `records` |
| E4002 | `requires` leaves out the running version |
| E4003 | a `Controller` under `patches`, or a `ControllerPatch` under `controllers` |
| E4004 | a clash with the user's files or another package |
| E4005 | a package of the same name is installed; `--force` replaces it |
| E4006 | `mod remove` of a package that is not installed |
| E5001 | an invalid listed file |
| E5002, E5003 | a protocol description with a built-in family or a file name unlike its family |

`--force` never overrides `requires`, a clash, or an invalid file. A development build uses every package, but `mod validate` and `mod install` refuse all of them there.

## Precedence

Bundled catalog, then packages, then the user's files; the user's files win. Among packages, the first by name wins. A package `Controller` is for a model with no bundled record. Package profiles are read-only (E3029 on change).

## Example Manifest

```json
{
  "apiVersion": "openjoystickdriver/v1alpha4",
  "kind": "ModPackage",
  "name": "ojd-sample",
  "version": "1.0.0",
  "author": "OpenJoystickDriver",
  "requires": { "minimum": "0.6.0-alpha.1", "below": "0.7.0" },
  "controllers": ["1209-0001.plist"],
  "profiles": ["sample-pad.plist"],
  "virtualDevices": ["1209-0001.plist"]
}
```

`plutil -convert xml1 -o mod.plist mod.json` writes the property list.
