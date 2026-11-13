# Writing controller mods

The product list of the [Xbox USB driver](Connecting-Controllers.md#xbox-usb-driver) is signed by Apple, and a mod package cannot add a controller to it.

## Contents

- [Package Layout](#package-layout)
- [The Manifest](#the-manifest)
- [Precedence and Clashes](#precedence-and-clashes)
- [Package Profiles Are Read-Only](#package-profiles-are-read-only)
- [Manage Packages With ojd mod](#manage-packages-with-ojd-mod)
- [Further Reading](#further-reading)

## Package Layout

A mod package is a folder that holds controllers, controller patches, [profiles](Glossary.md#terms), [virtual gamepads](Glossary.md#terms), and protocol descriptions. You can share the folder and install it with `ojd mod`.

A package adds files to the layers that OpenJoystickDriver (OJD) already reads. It holds no code. A package record for a raw-USB controller works only when macOS lets OJD open the device directly.

A package is a folder with a `mod.plist` manifest and up to four subfolders:

```text
ojd-sample/
  mod.plist
  Controllers/1209-0001.plist
  Profiles/sample-pad.plist
  VirtualDevices/1209-0001.plist
```

- `Controllers/` holds [controller records](Controller-Records.md). Name a `Controller` file `vvvv-pppp.plist` after its model, in lowercase hexadecimal. Name a `ControllerPatch` file `vvvv-pppp.patch.plist`, `model-vvvv-pppp.patch.plist`, or `all.patch.plist`. Both kinds share the folder, as they do in your own `Controllers` folder, because OpenJoystickDriver reads the records and patches of one layer from one folder.
- `Profiles/` holds [profiles](Profile-File-Reference.md).
- `VirtualDevices/` holds `VirtualDevice` files, which choose the virtual gamepad that games see. Name each file `vvvv-pppp.plist` after the model it matches, or `vvvv-pppp-U-UNIT.plist` for one controller, where `UNIT` is the 16-character unit ID that `ojd controller show` prints.
- `Protocols/` holds protocol description files that define a family the `Controller` files of the package or your own files can name. Name each file `FamilyName.plist` after the UpperCamelCase family it defines. See [Define a Family With a Description](Controller-Records.md#define-a-family-with-a-description).

The sample package, `ojd-sample`, is in the [`docs/sdk/sample`](../docs/sdk/sample) folder of the repository. It adds a generic HID pad (`1209:0001`), a profile that maps Start to the space key, and a virtual gamepad. `1209:0001` is a pid.codes test ID: it is not unique to one product, so use it only for testing, and use the real VID and PID of your controller in a package you share.

Every file of a package is an XML property list. `plutil -lint FILE.plist` checks one, `plutil -convert xml1 -o FILE.plist FILE.json` writes one from JSON, and `plutil -convert json -o - FILE.plist` prints one as JSON.

A package folder holds nothing else. OJD refuses a package with a file or folder that is not in the layout, and a package with a link. It skips hidden files and `.js` files: OJD never runs a script in a package, and an install does not copy it. To make documents with a script, run it with [`ojd generate`](Generating-Documents-with-Scripts.md).

## The Manifest

The `mod.plist` file names the package and lists every file it holds. This is the sample manifest:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
 <key>apiVersion</key>
 <string>openjoystickdriver/v1alpha3</string>
 <key>author</key>
 <string>OpenJoystickDriver</string>
 <key>controllers</key>
 <array>
  <string>1209-0001.plist</string>
 </array>
 <key>kind</key>
 <string>ModPackage</string>
 <key>name</key>
 <string>ojd-sample</string>
 <key>profiles</key>
 <array>
  <string>sample-pad.plist</string>
 </array>
 <key>requires</key>
 <dict>
  <key>below</key>
  <string>0.7.0</string>
  <key>minimum</key>
  <string>0.6.0-alpha.1</string>
 </dict>
 <key>version</key>
 <string>1.0.0</string>
 <key>virtualDevices</key>
 <array>
  <string>1209-0001.plist</string>
 </array>
</dict>
</plist>
```

- `apiVersion`: `openjoystickdriver/v1alpha3`. OJD rejects a missing or any other version, and names the file, the version it found, and the supported one.
- `kind`: `ModPackage`.
- `name`: Lowercase letters, digits, and hyphens. The package installs into a folder of this name.
- `version`: A SemVer version without a `v` prefix.
- `author`: Text that is not empty.
- `requires`: The OJD versions the package runs on. `minimum` is the first version, and `below` is the first version that is too new. `below` is optional. Prerelease versions follow SemVer order.
- `controllers`: The `Controller` files in `Controllers/`. Each name is `vvvv-pppp.plist`.
- `patches`: The `ControllerPatch` files in `Controllers/`. Each name is `vvvv-pppp.patch.plist`, `model-vvvv-pppp.patch.plist`, or `all.patch.plist`.
- `profiles`: The `Profile` files in `Profiles/`.
- `virtualDevices`: The `VirtualDevice` files in `VirtualDevices/`.
- `protocols`: The protocol description files in `Protocols/`. Each name is `FamilyName.plist`. OJD refuses a file with E5002 or E5003 when its family is built in, its file name is not its family name, or it sets no display name or no `defaults.input.layouts`.

A list that you include must name at least one file, and at least one list must name a file. OJD refuses a `mod.plist` with any other key, such as `records` or `personas`, with E4001. It refuses a `Controller` file listed under `patches` and a `ControllerPatch` file listed under `controllers` with E4003.

A file that is in a subfolder but not in the manifest, or in the manifest but not in the folder, makes OJD refuse the package. Each listed file must be valid for its kind.

OJD does not use a package whose `requires` leaves out the running version. It skips the package and lists the reason. `ojd mod list` shows it with the code E4002. A development build, whose version is not a SemVer version, uses every package, but `ojd mod validate` and `ojd mod install` refuse every package on it.

## Precedence and Clashes

A package is a read-only layer between the bundled catalog and your own files. When you and a package both have a `Controller` file for a model, OJD uses your file and ignores the package file. Your `ControllerPatch` applies over the package record and over a package patch, and wins over it. A package `Controller` file is for a model that has no bundled record, and a package `ControllerPatch` changes a bundled or packaged one. A package cannot add a `Controller` for a model that has a bundled record.

- `ojd mod install` and `ojd mod validate` refuse a package whose controller, patch, or virtual gamepad covers a model that your files or another package already hold, and one whose protocol description has the file name of one that you or another package already hold. They also refuse a profile that has the ID or the name of one that you or another package already hold. The code is E4004. `--force` does not override this.
- A clash can also appear after the install, for example when you add a record later. Your file then wins. Among packages, the first by package name wins. `ojd record list` names each package record that OJD ignores and the reason. OJD does not report a package profile that it ignores because of a clash. `ojd status` and `ojd diagnose` list each virtual gamepad file that OJD ignores and the reason.
- A `ControllerPatch` of yours for a model that only a package defines applies over the package record. If you remove the package later, OJD lists the patch as a problem and skips it.

## Package Profiles Are Read-Only

You can activate a profile that a package ships, but you cannot change it. A change is refused with the code E3029. To change one, duplicate the profile and edit the copy.

## Manage Packages With ojd mod

These commands need no service. The running service watches the `Packages` folder in `~/Library/Application Support/OpenJoystickDriver` and applies a change without a restart.

```text
ojd mod validate FOLDER
ojd mod install FOLDER [--force] [--dry-run]
ojd mod list
ojd mod remove NAME [--force] [--dry-run]
```

- `mod validate`: Check a package folder without installing it. It checks the manifest, `requires`, the files, and clashes. It exits with code 1 and the E4xxx or E5001 code when the package is refused.
- `mod install`: Check the package and copy it to `Packages/NAME`. A package of the same name that is installed is refused with E4005 unless you pass `--force`. `--force` never overrides `requires`, a clash, or an invalid file. `--dry-run` writes nothing.
- `mod list`: List each installed package with its version, author, and files. A package that OJD does not use shows the reason with its code.
- `mod remove`: Delete only the folder of that package. It asks first on a terminal and needs `--force` otherwise. It exits with code 1 and E4006 when the package is not installed.

To try the sample package:

1. Run `ojd mod validate` with the path of the sample folder.
2. Run `ojd mod install` with the same path.
3. Run `ojd mod list` to see the files it holds.
4. Run `ojd mod remove ojd-sample` to remove it.

[Error codes](Error-Codes.md) lists E4001 to E4007. Use `ojd explain E4004` to read what a code means.

## Further Reading

- [Controller records](Controller-Records.md)
- [Profile file reference](Profile-File-Reference.md)
- [Command reference](Command-Reference.md#mod)
- [Error codes](Error-Codes.md)
