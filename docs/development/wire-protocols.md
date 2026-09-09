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

Each published device owns a host-protocol session. Event reports, idle reports,
and initialization replies use one ordered sender. Suppression pauses idle
publication; closing rejects queued work and drains the current native send
before releasing the device.

Native SetReport buffers follow IOKit/HIDAPI framing: numbered reports include
the report ID at byte zero; unnumbered reports contain only data. The internal
request type also accepts explicitly marked payloads without an ID. It does not
guess framing from payload contents. GetReport returns a complete report bounded
by the caller's positive capacity. Unsupported type/ID combinations and malformed
requests fail with native CoreHID/IOKit errors.

Sony USB sessions provide virtual identity and calibration feature reports
(DualShock 4 `12`/`02`; DualSense `09`/`05`), plus DualSense firmware report `20`.
Output reports `05` and `02` decode the respective rumble enable flags and motor
values. Nintendo USB sessions handle initialization commands `80:01...05` and
subcommands for identity, full input mode, SPI reads, lights, IMU configuration,
and vibration. A Nintendo subcommand can produce both an acknowledgement and
rumble. SPI reads are bounded to the explicit virtual factory/user pages and
29 bytes per reply. These layouts follow the consumer paths in SDL's
[PS4](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_ps4.c),
[PS5](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_ps5.c),
and [Switch](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_switch.c)
drivers. Report IDs in this paragraph are hexadecimal.

Codec and concurrency tests cover these contracts. They do not establish signed
SDL/GameController binding, TCC reopen behavior, or physical output delivery.
Sony/Nintendo automatic identities remain selected as described above. Virtual
calibration and session addresses are generated values, not hardware captures;
touchpad button state is supported, while touch contacts and motion remain inactive.

Building uses SwiftPM. Xcode.app is not required. Disabling SIP is not
required.
