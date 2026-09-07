# Wire protocols

OJD classifies physical pads by host wire protocol, not by consumer API.
XInput, DirectInput, SDL, and `GCController` are consumers of a virtual HID
device.

| Family | Official name | USB identity | Linux | Windows | macOS 10.15+ without SIP |
| --- | --- | --- | --- | --- | --- |
| XID | Xbox Input Device | class `'X'/'B'/0` | `xpad` `XTYPE_XBOX` | no inbox driver | IOUSBHost if the kernel leaves the interface; userspace XID parser; virtual Generic HID |
| XUSB | [MS-XUSBI](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-xusbi/c0beb1e6-054f-4e2c-b6c3-7b5dff1299a5) | `FF/5D/01` wired (Krypton), `FF/5D/81` wireless adapter (Argon) | `XTYPE_XBOX360` / `XTYPE_XBOX360W` | `XUSB22.sys` | IOUSBHost userspace; virtual first-party `045E:028E` |
| GIP | [MS-GIPUSB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gipusb/e7c90904-5e21-426e-b9ad-d82adeee0dbc) | `FF/47/D0` | `XTYPE_XBOXONE` | `xboxgip.sys` | IOUSBHost, or entitled DEXT for Apple-approved Microsoft pairs; virtual first-party `045E:0B13` |
| HID | USB/Bluetooth HID | class `03` | `hid-sony`, `hid-playstation`, `hid-nintendo`, `hid-steam`, hid-generic | `hidclass.sys` | `IOHIDManager` / CoreHID; DualShock 4 / DualSense / Switch Pro first-party USB packers when the physical dialect matches; otherwise Generic HID |

Xbox One S 1708+ Bluetooth is HID, not USB GIP. DualShock 1/2 used the
PlayStation controller-port serial bus, not USB HID.

Automatic compatibility has one publishable identity per family that can
spoof today: XUSB → `sdl2-3`, GIP → `apple-gamecontroller`. HID DualShock 4,
DualSense, and Switch Pro physical pads publish their first-party USB identities.
Other HID and XID stay Generic HID. Catalog membership still comes from pinned Linux sources, HID
tables, and local overrides. Apple GameController MobileAsset is diagnostic
evidence, not the support catalog.

Building uses SwiftPM. Xcode.app is not required. Disabling SIP is not
required.
