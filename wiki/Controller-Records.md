# Adding Or Changing a Controller Record

This page explains how to add a controller that OpenJoystickDriver does not know, or change how it drives a known one, with your own controller record.

## Contents

- [How Records Work](#how-records-work)
- [Choose Who Drives the Controller](#choose-who-drives-the-controller)
- [Describe a Controller's Input Reports](#describe-a-controllers-input-reports)
- [Add Rumble To a Controller](#add-rumble-to-a-controller)
- [Send Fixed Reports At Startup](#send-fixed-reports-at-startup)
- [Tune Timings and the Stick Deadzone](#tune-timings-and-the-stick-deadzone)
- [Select a Model With Protocol Parameters](#select-a-model-with-protocol-parameters)
- [Map HID Usages](#map-hid-usages)
- [Control Names and Other Vocabularies](#control-names-and-other-vocabularies)
- [Offer Alternative Modes Chosen By Link, Keys, and Probes](#offer-alternative-modes-chosen-by-link-keys-and-probes)
- [Connect a Switch 2 Controller Over Bluetooth LE][toc-2]
- [Draft a Record From a Connected Controller][toc-1]
- [Install a Record](#install-a-record)
- [Check Which Records Apply](#check-which-records-apply)
- [Remove a Record](#remove-a-record)
- [Schema Versions and Compatibility](#schema-versions)
- [Further Reading](#further-reading)

[toc-1]: #draft-a-record-from-a-connected-controller
[toc-2]: #connect-a-switch-2-controller-over-bluetooth-le

## How Records Work

A controller record tells OpenJoystickDriver which protocol family drives one controller model, identified by its VID:PID. The app contains a bundled record for each supported model. Your records are JSON files in `~/Library/Application Support/OpenJoystickDriver/Controllers`. Each file is named after its model in lowercase hexadecimal, for example `045e-028e.json`.

A file in that folder is one of two kinds:

- `Controller`: a complete record for a model that has no bundled record. Name it `VVVV-PPPP.json`.
- `ControllerPatch`: new values for a model that already has a record. Name it `VVVV-PPPP.patch.json`. Its `selector` names the model by `vendorID` and `productID`, and its `patch` holds the fields to change.

A patch follows RFC 7396 JSON Merge Patch. An object in `patch` merges into the record key by key, a value you give overrides the record's value, an array overrides the whole array, and `null` deletes the key. Deleting the last key of a section leaves an empty section, which a record does not accept, so set the whole section (`tuning`) to `null` instead. An array overrides the whole array, so a patch that changes the protocol restates the whole `modes` list, including the `default` mode, as in [Offer Alternative Modes](#offer-alternative-modes-chosen-by-link-keys-and-probes).

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 1118, "productID": 746 },
  "patch": { "tuning": { "stickDeadzone": 0.08 } }
}
```

Several patches can apply to one model. The layers apply from the weakest to the strongest: the bundled record, a bundled patch, a patch from an installed [mod package](Writing-Controller-Mods.md), then your patch. Inside one layer, a patch with `"selector": { "all": true }` applies first, a `vendorID` and `productID` patch next, and a patch with `"selector": { "model": "VVVV-PPPP" }` last. A `Controller` file of yours replaces a package's `Controller` file for the same model. A `ControllerPatch` of yours applies over the package record instead of replacing it. If you remove the package later, OJD lists your patch as a problem and skips it.

A record for a model that uses raw USB works only when macOS lets OpenJoystickDriver open the device directly. The Xbox USB part of the [OJD driver extension](Connecting-Controllers.md#xbox-usb-driver-extension) claims only the Xbox models in its signed product list, and your record cannot add a model to that list. `ojd record validate` says when this applies.

## Choose Who Drives the Controller

macOS serves some controllers natively through the Game Controller framework. OpenJoystickDriver leaves those to macOS by default and only reads their input. The record's `server` field changes this:

- `System`: macOS drives the controller when it can. This is the default.
- `OJD`: OpenJoystickDriver opens the controller exclusively even when macOS supports it, and drives it like a controller macOS does not know.

A raw-USB family, such as `XboxGIP`, has no `server` field, because macOS cannot serve those controllers. A new `server` value applies to a connected controller as soon as the running service reloads the records. You do not need to unplug the controller.

To change `server` without editing the file, run `ojd controller claim CONTROLLER` or `ojd controller release CONTROLLER`. `claim` sets `OJD`, and `release` sets `System`. The command writes the value to your record for the model, and creates a `ControllerPatch` file when you have none and the bundled catalog or an installed package has a record of the model. It refuses a raw-USB family, a controller that macOS does not serve natively, and a model that has no record at all, with the code E2023. For a model with no record, run `ojd record draft` to start one. `ojd controller show` names the choice and the layer it comes from, and the serving route and persona. In the app, the controller detail has the same choice as the **Served by** picker, shown for a controller that macOS serves natively or that a record gives to OpenJoystickDriver, and never for a raw-USB family.

## Describe a Controller's Input Reports

Some controllers send fixed input reports that their HID descriptor describes wrongly. A record with the protocol family `HIDReportLayout` names where each control sits in the report, in its `input` field. The family requires `input`, and no other family takes it in a record. The bundled `XboxXID`, `NintendoSwitchInputOnly` and `VendorFlydigi` protocol descriptions declare their own `input` layout as data (`defaults.input` in `Resources/Protocols`), and a record of those families takes none.

```json
"modes": [{ "id": "default", "protocol": { "family": "HIDReportLayout" } }],
"input": {
  "report": { "length": { "atLeast": 19 } },
  "buttons": [
    { "control": "South", "byte": 13, "mask": 128 },
    { "control": "Back", "byte": 1, "mask": 1 }
  ],
  "axes": [
    { "control": "LeftStickX", "byte": 3 },
    { "control": "LeftStickY", "byte": 4 }
  ],
  "hat": [
    {
      "encoding": "Directions",
      "up": { "byte": 9, "mask": 128 },
      "right": { "byte": 7, "mask": 128 },
      "down": { "byte": 10, "mask": 128 },
      "left": { "byte": 8, "mask": 128 }
    }
  ],
  "leftTrigger": { "byte": 17 },
  "rightTrigger": { "byte": 18 }
}
```

Offsets count from the first byte of the report as macOS delivers it.

- `report`: `length` is `{ "atLeast": N }` or `{ "exactly": N }`, with N from 1 to 64 and exactly one of the two keys. `atLeast` reads every report of N bytes or more; `exactly` reads only reports of N bytes. With `id`, from 1 to 255, byte 0 must hold that report ID, and N counts it. OpenJoystickDriver ignores shorter reports, reports of another length under `exactly`, and reports with another ID.
- `buttons`: each entry names a control, a `byte`, and a `mask`. The button is pressed while any masked bit is set. Repeat a control to read it from several places. A button cannot be a D-pad direction or a stick axis. A `LeftTrigger` or `RightTrigger` button reports the digital press of that trigger; the analog value comes from `leftTrigger` and `rightTrigger`.
- `axes`: each entry names a stick axis and its `byte`. `bits` is 8, the default, or 16 for a little-endian value in `byte` and the next byte. `signed` reads the value as two's complement. `min` and `max` set the raw range, which defaults to the full range of the width. `inverted` flips the direction. `symmetric` reads a signed value as the raw value divided by `max`, so the lowest raw value reads as full negative; it requires `signed`; `min` and `max` default to the full range, and if given must be negative and positive. X grows right and Y grows down, as in HID.
- `hat`: a list of sources; the first that reads a direction wins. An `EightWay` source reads the masked bits as 0 for north, clockwise to 7 for north-west, and any other value as centered. With `neutralUntilNonzero`, 0 also reads centered until the bits have been nonzero once, for a controller that sends 0 before its hat is live. A `directions` source names one bit for each direction; opposing directions cancel. A `table` source takes a `byte`, a `mask`, and `values`, which maps each masked number, written in decimal without leading zeros, to a direction name from `north`, `northEast`, `east`, `southEast`, `south`, `southWest`, `west`, and `northWest`; any other number reads as centered.
- `leftTrigger` and `rightTrigger`: a `byte` read from 0 to 255, a `button` that reads as fully pulled, or both.

Name at least one control. `ojd record validate` checks that every field lies inside the report.

## Add Rumble To a Controller

A `HIDReportLayout` or `VendorPS3ThirdParty` controller is input-only unless its mode names its rumble report in `session.rumble`:

```json
"session": {
  "rumble": {
    "report": { "kind": "Output", "id": 2, "length": 8 },
    "lowFrequency": { "byte": 3 },
    "highFrequency": { "byte": 2 }
  }
}
```

- `report` names the HID report: `kind` is `Output` or `Feature`, `id` is the report ID, and `length` counts every byte, including the report ID.
- `lowFrequency`, `highFrequency`, `leftTrigger`, and `rightTrigger` each give the byte offset of that motor's intensity, from 0 to 255. Name at least one.
- `resendIntervalMilliseconds` (optional, 1 to 60000): while any motor runs, the driver's keep-alive sends the last report again at this interval, and a report with every motor at zero stops the resends. A record that also sets a mode's `session.keepAlive`, or whose family's description declares a keep-alive (`VendorGameSir`), is rejected. Without it the report goes out once.

OpenJoystickDriver sets the report ID in byte 0 when the ID is not 0, writes each motor's intensity, and sends 0 in every other byte. It sends this report even when macOS drives the controller, because macOS does not drive these motors. Only a family that encodes rumble from a template takes `session.rumble`.

## Describe a Mode's Session

A mode's `session` is the one shape that lists everything OpenJoystickDriver does around a controller session. A protocol description's `defaults.session` and a record's modes use the same keys. A mode runs exactly the steps its own `session` names; a mode without a `session` runs none of a record's steps, and no mode inherits another mode's session.

- `startup`: 1 to 16 startup writes of one format. See [Send Fixed Reports At Startup](#send-fixed-reports-at-startup).
- `rumble`: the rumble report template. See [Add Rumble To a Controller](#add-rumble-to-a-controller).
- `control` (raw-USB modes): 1 to 16 vendor control transfers, run in order before the startup packets, inside each handshake attempt.
- `settleMilliseconds` (raw-USB modes, 1 to 60000): the wait after the handshake before the first input transfer.
- `shutdown` (raw-USB modes): 1 to 8 raw-USB packets, sent when the session closes. A failed packet is logged and the next one is still sent.
- `keepAlive` (raw-USB modes of `XboxXID` and `XboxXUSB`, whose descriptions declare none): `intervalMilliseconds` (1 to 60000) and 1 to 8 `writes`, each a raw-USB packet with `bytes` and optionally `endpoint`, `timeoutMilliseconds` and `sessionByte`.

A HID mode takes only `startup` and `rumble`.

Raw bytes are uppercase hex pairs separated by single spaces, such as `42 03 00 00`. A byte string with lowercase digits, a `0x` prefix, or other separators fails validation.

### Vendor Control Transfers

```json
"session": {
  "control": [
    {
      "bmRequestType": 192,
      "bRequest": 1,
      "wValue": 0,
      "wIndex": 0,
      "wLength": 8,
      "match": { "manufacturer": "SHANWAN" }
    }
  ]
}
```

- `bmRequestType` is a vendor request type: 64 to 67 (host to device) or 192 to 195 (device to host). `bRequest` is 0 to 255, `wValue` and `wIndex` are 0 to 65535.
- `wLength` is 0 to 64. An IN transfer (192 to 195) reads `wLength` bytes, needs `wLength` of at least 1, and carries no `data`. An OUT transfer (64 to 67) writes `data`, whose byte count equals `wLength`; with `wLength` 0 it has no data stage.
- `timeoutMilliseconds` is 1 to 60000. A step that names none waits 1000 ms.
- `delayMilliseconds` (0 to 1000) waits after the transfer. `toleratesRejection` logs a rejected transfer and goes on instead of failing startup.
- `match` gates the transfer with `manufacturer`, `product` (non-empty text) and `bcdDevice` (`min` and `max`). The transfer runs only for a device where every key present holds; a device that does not report a keyed value never receives it. A transfer without `match` runs for every device.

## Send Fixed Reports At Startup

A HID controller that needs a fixed report before it sends input names it in the `session.startup` of its mode. The DualShock 3 record `054c:0268` and the Sixaxis clone record `2563:0523` use it in a `bluetooth` mode. A write applies on every link unless a `transport` limits it (`USB`, `BluetoothClassic`, or `BluetoothLE`; a write never names `ProprietaryRadioReceiver`):

```json
"session": {
  "startup": [
    {
      "report": { "kind": "Feature", "id": 244, "length": 5 },
      "bytes": "42 03 00 00",
      "transport": "BluetoothClassic"
    }
  ]
}
```

- `report` names the HID report as in `session.rumble`. `length` is 2 to 128 bytes.
- `bytes` lists every byte after the report ID, or every byte of the report when `id` is 0, as uppercase hex pairs.
- `delayMilliseconds` waits before this write, from 0 to 1000. Without it, a `Startup`-phase write waits the family's startup interval and an `Activation`-phase write does not wait.
- `phase` is `Activation`, the default, or `Startup`. An `Activation` write is sent after the protocol driver's own startup, when the controller opens; a `Startup` write is sent with the driver's startup writes.
- `crc32Seed` (0 to 255) makes OpenJoystickDriver write the Sony Bluetooth CRC-32 of the report, with this seed, in its last 4 bytes. `length` then counts those 4 bytes and must exceed 4. The DualShock 4 Bluetooth report uses it.
- `transport` limits the write to `USB`, `BluetoothClassic`, or `BluetoothLE`. Without it, OpenJoystickDriver sends the write on every transport.

List 1 to 16 writes. OpenJoystickDriver sends them in order after the protocol driver's own startup, only when it opens the controller. A failed write is logged and the next one is still sent. A family's description may also carry startup writes in its `defaults.session.startup`, which a mode's writes of the same format replace. In a description a HID write may add `variants` (the family variants it applies to) and `when` (`{"parameter": "layout", "is": ["Pro"]}` or `isNot`, naming a declared enumeration parameter). A record may not use `variants` or `when`.

### Raw-USB Startup Writes

A raw-USB family that carries startup packets in its description (`XboxXUSB`, `XboxGIP`, `NintendoSwitch2`) takes them in a raw-USB mode's `session.startup` too, in place of the description's. A raw-USB write has no `report`: `bytes` (1 to 64 bytes), `endpoint` (1 to 127, default the family's output endpoint), `timeoutMilliseconds` (1 to 60000, default the family's timeout), `delayMilliseconds` (0 to 1000), `sessionByte` (the index of a byte the driver fills with its per-session value, such as the GIP sequence), and `toleratesRejection`. One list holds one format only, and a mode that names `protocol.initialization` takes no raw-USB writes.

## Tune Timings and the Stick Deadzone

A record's `tuning` field changes a value that the protocol driver otherwise sets. Name at least one value. A value you leave out keeps the family's default, which its protocol description holds (see [Family Defaults](#family-defaults-live-in-protocol-descriptions)).

```json
"tuning": {
  "stickDeadzone": 0.02,
  "hidStartupRecoveryRounds": 3
}
```

| Field | Range | Applies to | What it sets |
| --- | --- | --- | --- |
| `stickDeadzone` | more than 0, less than 1 | every family | The radial deadzone of both sticks on the virtual gamepad, as a fraction of full deflection. Movement past the deadzone is rescaled to the full range. Without it, the sticks have no deadzone: games and browsers get the values the controller reports. |
| `inputLivenessTimeoutMs` | 1 to 60000 | `SonyDualShock4`, `SonySixaxis` over USB | How long the controller can send no input before OpenJoystickDriver releases its held controls. The default is 1000. |
| `hidStartupIntervalMs` | 0 to 60000 | HID families | The gap between the startup writes. |
| `minimumHIDOutputIntervalMs` | 0 to 60000 | HID families | The shortest gap between rumble and lighting reports. 0 sends them without a limit. |
| `hidStartupRecoveryIntervalMs` | 1 to 60000 | `NintendoSwitch1` | The gap between startup recovery rounds. The family's description gives the default (200). |
| `hidStartupRecoveryRounds` | 1 to 10 | `NintendoSwitch1` | The startup recovery rounds before OpenJoystickDriver gives up. The family's description gives the default (2). |
| `lizardResendTicks` | 1 to 100000 | `ValveSteamTriton` | The keep-alive ticks between resends of the lizard-mode-off request. The family's description gives the default (75). |
| `usbCommandTimeoutMs` | 1 to 60000 | `NintendoSwitch2`, `VendorGameSir` (USB) | The timeout of one USB command transfer. The description gives the default: 1000 for `NintendoSwitch2`, 2000 for `VendorGameSir`. |
| `presenceResendReports` | 1 to 1000 | `XboxGIP` | The input reports between resends of the request that makes a controller announce itself. The description gives the default: 4. |
| `adapterDisconnectDelayMs` | 1 to 60000 | `SonyDualShock4`, `SonyDualSense` | How long an adapter or dongle can stay silent before its controller counts as disconnected. The default is 500. |
| `usbStartupIntervalMs` | 0 to 60000 | `XboxGIP` | The gap between the raw-USB startup writes. The default is 50. |
| `usbStartupRetryDelayMs` | 1 to 60000 | `XboxGIP` | The wait before the first startup retry; each later retry waits twice as long. The default is 1000. |
| `usbTransferTimeoutMs` | 1 to 60000 | `XboxGIP`, `XboxXID`, `XboxXUSB` | The timeout of each raw-USB transfer: startup packets, rumble and output. The description gives the default, 2000. |
| `frameQueueCapacity` | 1 to 1024 | every family | How many virtual gamepad reports may wait behind the one being sent. The default is 64. When the queue is full, the newest state replaces the oldest waiting state, so a slow consumer never grows memory and always receives the newest state. A reply to an app's output report is never dropped. |

### Set the Deadzone of a Stick That Rests Off Center

OpenJoystickDriver keeps no default deadzone. XInput leaves the deadzone to the game: Microsoft's documentation says "your game must implement dead zone correctly" and gives `XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE` (8689 of 32767) as the value to use. The rest position differs from one unit to the next, and a driver deadzone stacks with the game's own deadzone, so a default here would be wrong for some controllers and doubled for others. A web page reads the raw values, and a game that has no deadzone sees every drift.

A stick that rests off center needs the setting. The Razer controller `1532:0A15` reported its right stick at `RS=(-4672,-1312)` while at rest, which is 0.148 of full deflection from the center. `stickDeadzone` is radial: a stick closer to the center than the value, measured as `sqrt(x² + y²)` over the full deflection, reads as centered, so the value must exceed the distance of the rest position, not the offset of one axis. Here the distance is `sqrt(4672² + 1312²) / 32767`, about 0.148. Set `stickDeadzone` for the model above that distance, then check the rest value with `ojd controller watch`:

```text
ojd config set stickDeadzone 0.15 --controller 1532:0A15
ojd config show --controller 1532:0A15
```

`ojd config unset stickDeadzone --controller 1532:0A15` removes it. The **Stick deadzone** stepper above the **Tuning** group of the controller detail in the app writes the same key. `stickDeadzone` is radial and applies to both sticks, so size it for the stick that rests furthest off center.

The default for `frameQueueCapacity` is 64, the `default` of `tuning.frameQueueCapacity` in `controller.schema.json`. It also applies to a controller that has no record. A protocol description's `defaults.tuning` (`Resources/Protocols/<file stem>.json`) may set another value for its family, and a record, a patch, or `all.patch.json` overrides both, per model or for every controller. Reports queue only while the system takes a long time to accept the previous one; button changes that arrive in the same moment still reach the virtual gamepad in order until the queue is full.

Raw-USB families, such as `XboxGIP`, do not take the two HID timings. The two recovery values apply only to `NintendoSwitch1`, because the `NintendoSwitch2` and `NintendoSwitchInputOnly` drivers have no startup recovery. `ojd record validate` rejects a value outside its range or its families.

A `tuning` in a `ControllerPatch` merges per value into the bundled `tuning`: a value you leave out keeps its bundled value. Timings apply when the running service connects the controller again after the record changes.

### Family Defaults Live In Protocol Descriptions

A family's default timings and control set are data in `Resources/Protocols/<file stem>.json`, not Swift constants. [`protocol-description.schema.json`](../Resources/Schemas/protocol-description.schema.json) defines the file, and it holds these members:

- `endpoints`: the USB endpoint addresses the driver uses.
- `rawUSB`: `true`, or the variants that talk raw USB.
- `recordSections`: the record sections the driver reads: `input` (a byte layout), `rumble` (a rumble template), `hidUsageMap` (`input.hidUsageMap`), `bluetoothLE` (the `bluetoothLE` section) and `keepAlive` (`protocol.keepAlive`). A record names a section only when every mode's family lists it.
- `sessionKeys`: the general `defaults.session` keys the family uses besides the rumble template, which the description may set: `startup` and `keepAlive`; absent means none. A description whose `sessionKeys` differ from the keys its family uses, or whose `defaults.session` sets a `startup` or `keepAlive` it does not list, is rejected (E5002). `defaults.input` is a byte layout where `recordSections` lists `input` and a HID usage map where it lists `hidUsageMap`, and a default rumble template (`defaults.session.rumble` or a variant's) needs `rumble` in `recordSections`. A `defaults.tuning` key that `tuningKeys` and `rawUSBTuningKeys` do not list is rejected too, so a HID family's description cannot default a timing its driver does not read.
- `parameters` and `parameterRules`: the parameters a record of the family may set, and the rules it obeys beyond each parameter's type. A rule has a `rule` (`None`, `AtMostOne`, `ExactlyOne` or `Requires`), the `parameters` it lists and the `variants` it is limited to. The validators check a record's parameters against them.
- `writeTransports`: the transports an `activation` or `deactivation` write may name; a family without it names none.
- `tuningKeys`: the `tuning` keys a record may set for the family. `rawUSBTuningKeys` lists the keys of its raw-USB variants, and a description that is always raw USB takes only `rawUSBTuningKeys`.
- `macOSOwnedOutput`: the output that macOS owns for the family, and a `rationale` that says why.
- `inputStart`: what the user does before a controller of the family sends input, limited to its `variants` (every variant when absent). `PressGuide` is a press of the home button: a DualShock 3 over USB sends no input report until its PS button is pressed, so until its first input the app and `ojd controller list` tell you to press it. An unknown action is rejected (E5002), and a variant that the family does not list is rejected (E5004).
- `controls`: the controls the driver reports. `recordCapabilities` names the control deltas (`present`, `rumbleAbsent`) that a record of the family may declare; the driver adds the record-derived parts.
- `defaults.tuning`: the default value of each tuning key, such as `lizardResendTicks`. The keep-alive interval is not a tuning key: `defaults.session.keepAlive.intervalMilliseconds` is its only source, and a description or record that names `keepAliveIntervalMs` anywhere is rejected. `defaults.variants.<variant>.tuning` gives another value for a transport, for example the Switch 1 `hidStartupIntervalMs` of 60 over Bluetooth and 20 over USB.

- `defaults.session.keepAlive`: the family's keep-alive. `intervalMilliseconds` (1 to 60000) is the period, and the optional `writes` (1 to 8) are the fixed packets of each run, in the formats of `session.startup` (a HID report with `report` and `bytes`, or a raw-USB packet with `bytes`, `endpoint`, `timeoutMilliseconds` and `sessionByte`) without `phase`, `delayMilliseconds`, `transport`, `crc32Seed`, `toleratesRejection` and `when`. Unlike startup, one list may mix both formats, each limited with `variants` (`VendorGameSir` sends a HID report on `enhanced-hid` and a raw-USB packet on `usb`). `resendTuning: "lizardResendTicks"` sends a write only every that-many runs (`ValveSteamTriton`); the family must read the key and default it in `defaults.tuning`. A mode's `session.keepAlive` is allowed only where the description declares none, so it never replaces a description's writes, and the interval of a description's keep-alive has no record key. The writes that follow driver state, such as a running rumble, stay in the driver (see [Wire Protocols](../docs/development/wire-protocols.md#coded-behavior)). A HID write needs a family with HID variants, and a raw-USB write needs one with raw-USB variants.
- `defaults.session.subcommands` (read by the `NintendoSwitch1` driver): the subcommand report. `reportID` is the output report that carries a subcommand, `counterModulus` (2 to 256) is the rule of the rolling packet counter (it starts at 0, the next value is `(n + 1)` modulo the modulus, and the rumble-only report shares the counter), and `requests` (1 to 16) are sent in order at startup. A request has a `subcommand` byte and exactly one of `data` (1 to 16 bytes) or `spiRead` (`address`, `length` of 1 to 29, and a `purpose` of `factoryMotionCalibration` or `userMotionCalibration`, each at most once). An SPI read sends the address as four little-endian bytes and then the length. A startup recovery round re-sends the reads whose reply has not arrived. The rumble bytes in the header and the player-indicator subcommand stay in the driver (see [Wire Protocols](../docs/development/wire-protocols.md#coded-behavior)).
- `defaults.session.handshakeAttempts` (1 to 10) and `defaults.session.announceResendLimit` (1 to 100) (read by the `XboxGIP` driver): the number of startup handshake attempts, and the most resends of the request that makes a controller announce itself. They are protocol limits, so a record's `tuning` cannot change them, and a description that lacks a session field its driver reads, or sets one its driver does not read, is rejected when it loads (E5002).
- `defaults.session.namedPackets` (a family that has them accepts `protocol.initialization`): the GIP packets a record can select by name in `protocol.initialization` (1 to 16). Each has an `id` (the family name, a slash and a lowercase hyphenated name, such as `XboxGIP/power-on`, each at most once), `bytes` (3 to 64) and `sessionByte`, which is 2: the driver stamps byte 2 with the next sequence number of the packet's command. A record that names an id the description lacks is rejected. The description's own default startup (`defaults.session.startup`) lists its packets as bytes.

Change a default by editing the description: every record of the family follows it, and a record's or patch's own `tuning` still wins. Then run `./Scripts/ojd catalog regenerate --write`, which copies the descriptions into the Kit bundle.

### Set a Default for Every Controller

`~/Library/Application Support/OpenJoystickDriver/Controllers/all.patch.json` sets a `tuning` default for every controller. It is a `ControllerPatch` with `"selector": { "all": true }`, and [`controller-patch.schema.json`](../Resources/Schemas/controller-patch.schema.json) describes it. Only `tuning` may appear in its `patch`.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "ControllerPatch",
  "selector": { "all": true },
  "patch": { "tuning": { "stickDeadzone": 0.05 } }
}
```

Each value takes the first layer that sets it, from the strongest down: a patch of yours for the model, your `all.patch.json`, the package, the bundled record, then the driver's own default. A value in `all.patch.json` applies only to the families that read it, as in the table above. The file is optional. An invalid file is ignored whole, and `ojd config show`, `ojd status`, and the `config-files` check of `ojd diagnose` report why. `ojd config show` prints each value and the layer that set it.

The record's `stickDeadzone` shapes the virtual gamepad's stick report. A profile's `innerDeadzone` calibrates a stick that the profile maps to aim, flick, pointer, scroll, or steering output. The two do not inherit from each other: a deadzone in a record or in `all.patch.json` does not change what a profile mapping does. `ojd config show --controller` lists the active profile's `innerDeadzone` values in the `profile` layer next to the record's keys, when the service runs.

### Change the Virtual Gamepad Identity

A `VirtualDevice` file in `~/Library/Application Support/OpenJoystickDriver/VirtualDevices` chooses the virtual gamepad that games see for one controller model, or for one controller unit. [`virtual-device.schema.json`](../Resources/Schemas/virtual-device.schema.json) describes it.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "VirtualDevice",
  "match": { "vendorID": 1356, "productID": 3302 },
  "persona": "SDLCompatible"
}
```

`match` names the model by VID:PID in decimal. Add `unit` with a `U-` ID from `ojd controller show` to match one controller. A unit file wins over a model file. `persona` is `Generic`, `SDLCompatible` or `GameControllerCompatible`. Automatic selection publishes `SDLCompatible` when the controller's main controls fit it and `Generic` otherwise. `SDLCompatible` publishes the Xbox Adaptive Controller identity (`045E:0B0C`) over Xbox One GIP reports, which SDL's Xbox One driver reads with the default hints and Apple's GameController framework does not bind. `Generic` is the `1209:4A4F` identity (pid.codes) and gets no gamepad mapping in those apps without OJD's SDL mapping. An optional `identity` gives a vendor ID, product ID, product name, manufacturer, and `version`, and an optional `labels` gives the glyph family (`xbox` or `generic`). OpenJoystickDriver publishes the virtual gamepad with that identity over the persona's report layout. The transport, the report layout, and the virtual LocationID stay those of the persona, and `version` defaults to the persona's. While the service runs, it watches the `VirtualDevices` folder. When a file is added, edited, or removed and a connected controller's `identity` or `persona` changes, OpenJoystickDriver creates that controller's virtual gamepad again with the new identity, so you do not reconnect the controller. Games and other apps see the old virtual gamepad disappear and a new one appear. A change that leaves a controller's identity and persona the same, or that concerns another controller, does not touch its virtual gamepad. A file with a wrong `apiVersion` or `kind` fails with `E5001`. Any other file that fails validation is skipped, and `ojd status` and the `config-files` check of `ojd diagnose` name it and the reason.

## Select a Model With Protocol Parameters

Some families drive several models that differ in one detail. A typed parameter in the `protocol.parameters` object of a mode selects the detail. Each family declares its own parameters, and a record with an unknown parameter, a parameter another family declares, or a value of the wrong type is rejected. A flag parameter is `true` or left out.

- `shareButton` (`XboxGIP`): `{"fromEnd": N}` reads the Share button N bytes back from the end of the packet (Linux xpad `MAP_SHARE_BUTTON` is 18, and 26 with `MAP_SHARE_OFFSET`). Without it, the pad has no Share. If your pad has a Share button that `ojd controller watch` does not show, add the parameter in a patch. 18 fits most pads with a 32-byte input payload.
- `layout` (`NintendoSwitch1`, `NintendoSwitch2`): `Pro`, `JoyConLeft` or `JoyConRight`, and `GameCube` on `NintendoSwitch2`, the NSO GameCube controller. `usbProtocol` (`NintendoSwitch1`): `ChargingOnly` for a pad whose USB link only charges it, which binds the Bluetooth Classic link only; it excludes `layout`.
- `innerGrips` and `lightingMemory` (`VendorGameSir`): an enhanced HID record names exactly one. `innerGrips` reports the inner grips; `lightingMemory: "ProfileSlots"` makes lighting memory slot-based. A GameSir USB record names neither.
- `hatSource: "DpadPressure"` (`VendorPS3ThirdParty`): any nonzero D-pad pressure byte holds its direction.
- `motionCalibration: "Factory"` (`SonyDualShock4`): read the motion calibration from the controller. Without it, OpenJoystickDriver uses nominal calibration, as for third-party DualShock 4 controllers.
- `role: "WirelessAdapter"` (`SonyDualShock4`): the Sony DUALSHOCK 4 USB wireless adapter. Output waits until a controller connects to the adapter.
- `motionScale: "StrikePad"` (`SonyDualShock4`): a controller whose motion reports half the acceleration in the opposite direction on all axes.
- `reportRevision: "Shield2015"` (`VendorNVIDIAShield`): the 2015 SHIELD controller, which has rumble. Without it, the driver treats the controller as the 2017 model, which is input-only on macOS.
- `maker: "ThirdParty"` (`SonyDualSense`): the controller is not a Sony DualSense. The driver reads feature report `0x03` for its features and limits output to them, as SDL's `HIDAPI_DriverPS5` does.
- `unprobedSensors` and `unprobedTouchpad` (`SonyDualSense`): a third-party DualSense that does not answer the capability probe still has motion sensors or a touchpad, and either parameter reads its input in the alternate report layout.
- `forcedVibration` (`SonyDualSense`): a third-party DualSense keeps vibration when its probe reply omits it.
- `role: "Receiver"` (`SonyDualSense`): a third-party DualSense wireless receiver, which reports with no controller paired. OJD treats the controller as connected only while the packet sequence advances.

A DualShock 4 record takes at most one of `role` and `motionScale`. A `SonyDualSense` record runs as a third-party controller only with `maker: "ThirdParty"`, whatever its vendor ID, and the other DualSense parameters describe that model and need it; a record without parameters is a Sony DualSense. The catalog gives `maker: "ThirdParty"` to every `SonyDualSense` record whose vendor ID is not Sony's (`054C`). A `patch` merges its parameters key by key into the bundled ones and cannot remove one, but it can set a bundled parameter to another value.

## Map HID Usages

A `HIDDescriptor` record maps the usages of its report descriptor to controls in `input.hidUsageMap`. Without one, the record uses the standard map in `Resources/Protocols/hid-descriptor.json`. Each entry names a usage by decimal `page` and `usage` and one `control`, as a `kind`:

- `button`: the control is pressed while the value is nonzero. It cannot be a D-pad id or a stick axis.
- `axis`: the control is a stick axis (`LeftStickX`, `LeftStickY`, `RightStickX`, `RightStickY`) or `LeftTrigger` or `RightTrigger`. A stick reads -1 to 1 and a trigger 0 to 1 across the element's logical range. `range` (`{"min": 0, "max": 100}`, `min` below `max`) replaces that range, `inverted` reverses the axis, and `deadZone` (above 0 and below 1) reads 0 within that fraction of full travel and rescales the rest.
- `hat`: the entry has no `control`; it drives `DpadUp`, `DpadDown`, `DpadLeft` and `DpadRight`. `range` is `{"min": 0, "max": 7}` or `{"min": 1, "max": 8}` and names the value of north, then clockwise; any other value is neutral. Without `range`, the element's logical minimum is north.

`reportID` limits the map to one report. A usage the map does not name is ignored, and both the app and `./Scripts/ojd check profiles` reject a usage named twice or an axis `range` whose `min` is not below its `max`. The description may also list `descriptorShapes` that choose a map from the usages a controller's report descriptor declares: the shape in `hid-descriptor.json` gives a controller with Z, Rz, a Brake or Accelerator and no Rx or Ry the Z/Rz layout, with Brake as LT and Accelerator as RT. The records for the WR007 (`11C1:5600`), SCUF Envision (`2E95:434D`), 8BitDo Ultimate 2C (`2DC8:301B`, `301C`) and DragonRise (`0079:0006`, by patch) show complete maps.

## Control Names and Other Vocabularies

Every document, profile, endpoint message and record names a control with one UpperCamelCase id. `Resources/Schemas/vocabulary.schema.json` defines the ids, and `Resources/Vocabulary/crosswalk.json` holds the names the same control has elsewhere. The crosswalk is documentation: it is not a schema alias, and a document that uses another spelling is refused. A `-` means the other vocabulary has no name for the control, and the crosswalk guesses none. The W3C column is the `buttons` or `axes` index of the standard gamepad mapping. In the HID column a usage is hexadecimal, and `device` means the report descriptor assigns the usage number. `Capture` and `Microphone` share the SDL3 name `MISC1`. A stick's Y axis is positive down in the W3C, SDL3 and evdev columns; Apple's `y` axis is positive up. The table below is generated from the JSON file, so edit the JSON and run `./Scripts/ojd vocabulary regenerate --write`.

<!-- BEGIN GENERATED: control-crosswalk -->

| Control | W3C | SDL3 | evdev | HID page:usage | Apple GameController |
| --- | --- | --- | --- | --- | --- |
| `South` | button 0 | `SOUTH` | `BTN_SOUTH` | `Button:0x1` | `ButtonA` |
| `East` | button 1 | `EAST` | `BTN_EAST` | `Button:0x2` | `ButtonB` |
| `West` | button 2 | `WEST` | `BTN_WEST` | `Button:0x3` | `ButtonX` |
| `North` | button 3 | `NORTH` | `BTN_NORTH` | `Button:0x4` | `ButtonY` |
| `LeftShoulder` | button 4 | `LEFT_SHOULDER` | `BTN_TL` | `Button:device` | `LeftShoulder` |
| `RightShoulder` | button 5 | `RIGHT_SHOULDER` | `BTN_TR` | `Button:device` | `RightShoulder` |
| `LeftTrigger` | button 6 | `LEFT_TRIGGER` | `ABS_Z` | `GenericDesktop:0x32`, `Simulation:0xc5` | `LeftTrigger` |
| `RightTrigger` | button 7 | `RIGHT_TRIGGER` | `ABS_RZ` | `GenericDesktop:0x35`, `Simulation:0xc4` | `RightTrigger` |
| `Back` | button 8 | `BACK` | `BTN_SELECT` | `GenericDesktop:0x3e`, `Consumer:0x224`, `Button:device` | `ButtonOptions` |
| `Start` | button 9 | `START` | `BTN_START` | `GenericDesktop:0x3d` | `ButtonMenu` |
| `LeftStickClick` | button 10 | `LEFT_STICK` | `BTN_THUMBL` | `Button:device` | `LeftThumbstickButton` |
| `RightStickClick` | button 11 | `RIGHT_STICK` | `BTN_THUMBR` | `Button:device` | `RightThumbstickButton` |
| `DpadUp` | button 12 | `DPAD_UP` | `BTN_DPAD_UP` | `GenericDesktop:0x90`, `GenericDesktop:0x39` | `DirectionPad` |
| `DpadDown` | button 13 | `DPAD_DOWN` | `BTN_DPAD_DOWN` | `GenericDesktop:0x91`, `GenericDesktop:0x39` | `DirectionPad` |
| `DpadLeft` | button 14 | `DPAD_LEFT` | `BTN_DPAD_LEFT` | `GenericDesktop:0x93`, `GenericDesktop:0x39` | `DirectionPad` |
| `DpadRight` | button 15 | `DPAD_RIGHT` | `BTN_DPAD_RIGHT` | `GenericDesktop:0x92`, `GenericDesktop:0x39` | `DirectionPad` |
| `Guide` | button 16 | `GUIDE` | `BTN_MODE` | `GenericDesktop:0x85`, `Consumer:0x223` | `ButtonHome` |
| `Capture` | - | `MISC1` | `KEY_RECORD` | `Consumer:0xb2` | `ButtonShare` |
| `Microphone` | - | `MISC1` | - | `Telephony:0x2f`, `Consumer:0xe2` | - |
| `TouchpadClick` | - | `TOUCHPAD` | `BTN_LEFT` | `Button:device` | `DualShockTouchpadButton` |
| `LeftPaddle1` | - | `LEFT_PADDLE1` | `BTN_GRIPL` | `Button:device` | `XboxPaddleThree` |
| `LeftPaddle2` | - | `LEFT_PADDLE2` | `BTN_GRIPL2` | `Button:device` | `XboxPaddleFour` |
| `RightPaddle1` | - | `RIGHT_PADDLE1` | `BTN_GRIPR` | `Button:device` | `XboxPaddleOne` |
| `RightPaddle2` | - | `RIGHT_PADDLE2` | `BTN_GRIPR2` | `Button:device` | `XboxPaddleTwo` |
| `Auxiliary1` | - | `MISC2` | `BTN_TRIGGER_HAPPY1` | `Button:device` | - |
| `Auxiliary2` | - | `MISC3` | `BTN_TRIGGER_HAPPY2` | `Button:device` | - |
| `Auxiliary3` | - | `MISC4` | `BTN_TRIGGER_HAPPY3` | `Button:device` | - |
| `Auxiliary4` | - | `MISC5` | `BTN_TRIGGER_HAPPY4` | `Button:device` | - |
| `Auxiliary5` | - | `MISC6` | `BTN_TRIGGER_HAPPY5` | `Button:device` | - |
| `Auxiliary6` | - | - | `BTN_TRIGGER_HAPPY6` | `Button:device` | - |
| `Auxiliary7` | - | - | `BTN_TRIGGER_HAPPY7` | `Button:device` | - |
| `Auxiliary8` | - | - | `BTN_TRIGGER_HAPPY8` | `Button:device` | - |
| `LeftStickX` | axis 0 | `LEFTX` | `ABS_X` | `GenericDesktop:0x30` | `LeftThumbstick` |
| `LeftStickY` | axis 1 | `LEFTY` | `ABS_Y` | `GenericDesktop:0x31` | `LeftThumbstick` |
| `RightStickX` | axis 2 | `RIGHTX` | `ABS_RX` | `GenericDesktop:0x33` | `RightThumbstick` |
| `RightStickY` | axis 3 | `RIGHTY` | `ABS_RY` | `GenericDesktop:0x34` | `RightThumbstick` |
| `LeftStickTouch` | - | - | - | - | - |
| `RightStickTouch` | - | - | - | - | - |
| `LeftTrackpadClick` | - | - | - | - | - |
| `RightTrackpadClick` | - | - | - | - | - |
| `LeftTrackpadTouch` | - | - | - | - | - |
| `RightTrackpadTouch` | - | - | - | - | - |

Each column is checked against this source:

| Column | Document | Version | Revision | Checked on |
| --- | --- | --- | --- | --- |
| W3C | [W3C Gamepad, Standard Gamepad (section 'Standard Gamepad')](https://www.w3.org/TR/2025/WD-gamepad-20250710/#remapping) | Working Draft 10 July 2025 | - | 2026-10-16 |
| SDL3 | [SDL3 SDL_gamepad.h, enums SDL_GamepadButton and SDL_GamepadAxis](https://github.com/libsdl-org/SDL/blob/release-3.4.18/include/SDL3/SDL_gamepad.h) | release-3.4.18 | `829a65d769d935c4852f8159e964312c0957260a` | 2026-10-16 |
| evdev | [Linux include/uapi/linux/input-event-codes.h, with Documentation/input/gamepad.rst](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/input-event-codes.h?h=v7.2) | v7.2 | `8d3ae59288f1e7d58d76558a6ee96d533bc5019f` | 2026-10-16 |
| HID page:usage | [USB-IF HID Usage Tables for Universal Serial Bus (USB)](https://usb.org/document-library/hid-usage-tables-17) | 1.7 | - | 2026-10-16 |
| Apple GameController | [Apple GameController framework, GCInput element name constants (names shown without the GCInput prefix)](https://developer.apple.com/documentation/gamecontroller) | developer.apple.com documentation, macOS 11 and later | - | 2026-10-16 |

Notes on single cells:

| Control | Column | Note |
| --- | --- | --- |
| `LeftShoulder` | HID page:usage | A Button page usage number is assigned by the device descriptor. |
| `LeftTrigger` | evdev | ABS_Z is what the xpad and hid-playstation drivers report; the Linux gamepad documentation names BTN_TL2 or ABS_HAT2Y. |
| `LeftTrigger` | HID page:usage | Brake is the left trigger and Accelerator the right, as the standard HID usage map maps them. |
| `RightTrigger` | evdev | ABS_RZ is what the xpad and hid-playstation drivers report; the Linux gamepad documentation names BTN_TR2 or ABS_HAT2X. |
| `RightTrigger` | HID page:usage | Accelerator is the right trigger and Brake the left, as the standard HID usage map maps them. |
| `Back` | HID page:usage | Select is the HID Usage Tables name; the Xbox Bluetooth descriptor reports AC Back (Consumer 0x224). |
| `Start` | HID page:usage | Start is the HID Usage Tables name; Gamepad usages use Start and Select (section 8.4). |
| `DpadUp` | evdev | For all four D-pad ids, a driver may report ABS_HAT0X and ABS_HAT0Y instead (Linux gamepad documentation). |
| `DpadUp` | HID page:usage | For all four D-pad ids, the D-pad usage comes first; a Hat Switch (0x39) carries all four directions as one value. |
| `DpadUp` | Apple GameController | DpadUp, DpadDown, DpadLeft and DpadRight are one GCControllerDirectionPad element. |
| `Guide` | HID page:usage | System Main Menu is the HID Usage Tables name; the Xbox Bluetooth descriptor reports AC Home (Consumer 0x223). |
| `Capture` | evdev | KEY_RECORD is the Xbox Share button (Linux xpad driver); a Nintendo Switch controller reports its Capture button as BTN_Z (Linux hid-nintendo driver). |
| `Capture` | HID page:usage | Record (Consumer 0xB2) is how the standard HID usage map maps Share and Capture. |
| `Microphone` | evdev | No gamepad code: hid-playstation reports no mute button, and KEY_MICMUTE is a keyboard key. |
| `Microphone` | Apple GameController | The GameController documentation has no microphone button name. |
| `Microphone` | HID page:usage | Phone Mute (Telephony 0x2F) and Mute (Consumer 0xE2) are the HID Usage Tables mute usages. |
| `TouchpadClick` | evdev | The click is BTN_LEFT on the touchpad input device, not on the gamepad device (Linux hid-playstation driver). |
| `TouchpadClick` | Apple GameController | GCInputDualShockTouchpadButton also names the DualSense touchpad button. |
| `TouchpadClick` | HID page:usage | A Button page usage number is assigned by the device descriptor. |
| `LeftPaddle1` | Apple GameController | Apple names the Xbox Elite paddle P3; SDL3 and the Linux xpad driver number the paddles the same way. |
| `LeftPaddle2` | Apple GameController | Apple names the Xbox Elite paddle P4; SDL3 and the Linux xpad driver number the paddles the same way. |
| `RightPaddle1` | Apple GameController | Apple names the Xbox Elite paddle P1; SDL3 and the Linux xpad driver number the paddles the same way. |
| `RightPaddle2` | Apple GameController | Apple names the Xbox Elite paddle P2; SDL3 and the Linux xpad driver number the paddles the same way. |
| `Auxiliary1` | evdev | BTN_TRIGGER_HAPPYn for Auxiliary1 to Auxiliary8 is an OpenJoystickDriver choice: no source gives the Auxiliary buttons a role. |
| `Auxiliary6` | SDL3 | SDL3 has the buttons MISC1 to MISC6 only, so Auxiliary6 to Auxiliary8 have no SDL3 name. |
| `LeftStickX` | W3C | Axes 0 to 3 of the standard mapping; negative is left or up and positive is right or down. |
| `LeftStickY` | Apple GameController | Apple's y axis is positive up; every other column is positive down. |
| `RightStickY` | Apple GameController | Apple's y axis is positive up; every other column is positive down. |

<!-- END GENERATED: control-crosswalk -->

PlayStation Share (Create) and Xbox View are `Back`. PlayStation Options, Xbox Menu and Switch Plus are `Start`. Xbox Share and Switch Capture are `Capture`. The names `Share` and `Options` are not controls.

## Offer Alternative Modes Chosen By Link, Keys, and Probes

Every record has a `modes` list, and the protocol a controller runs is the `protocol` of one of its modes. The list holds exactly one mode with the id `default`, which has no `match` and runs when no other mode matches. A HID record can add alternatives for controllers that run one of several protocols, such as XInput, DInput, or Switch mode, or that need different handling over USB and over Bluetooth:

```json
"modes": [
  { "id": "default", "protocol": { "family": "SonySixaxis" } },
  {
    "id": "bluetooth",
    "protocol": { "family": "SonySixaxis" },
    "match": { "link": "BluetoothClassic" },
    "session": {
      "startup": [{ "report": { "kind": "Feature", "id": 244, "length": 5 }, "bytes": [66, 3, 0, 0] }]
    }
  },
  {
    "id": "feature-ef-answers",
    "protocol": { "family": "SonySixaxis" },
    "match": {
      "probes": [{ "report": 239, "length": 49, "expect": "Answers" }]
    }
  }
]
```

- `id` is lowercase words joined by hyphens. IDs are unique in a record.
- `protocol` names the protocol that mode runs.
- `match` is required in every mode except `default`, and names at least one key. A mode is selected only when all of its keys hold.
- `interface` (`first` and `last`, inclusive, from 0 to 255) limits which USB interface a HID mode binds to: the lowest interface in the range that the controller exposes. A raw-USB mode has none, because it claims the interface its `usb` transport resolves.
- `session` lists the mode's steps (see [Describe a Mode's Session](#describe-a-modes-session)). A mode names every step it runs; it inherits nothing from the default mode.

The `match` keys are:

- `link` is `USB`, `BluetoothClassic`, `BluetoothLE`, or `ProprietaryRadioReceiver`. It holds when every interface of the device reaches the controller over that link: the physical link where discovery observed one, otherwise `proprietary-radio-receiver` for a model whose own record runs a `receiver` or `dongle` protocol variant, otherwise the host link macOS reports.
- `interfaceSignature` holds when one interface has the given `interfaceClass`, `interfaceSubclass`, and `interfaceProtocol` (0 to 255) and, when given, the HID `usagePage` and `usage` (0 to 65535, `usage` needs `usagePage`) and the whole `endpoints` set. `endpoints` lists 1 or more endpoints, each with at least one of `address` (0 to 255), `direction` (`in` or `out`), `transferType` (`control`, `isochronous`, `bulk`, or `interrupt`), and `maxPacketSize` (0 to 65535). Each listed endpoint must pair with a distinct endpoint of the interface, and none of the interface's endpoints may be left over, so two interfaces with one class triple and different endpoint sets select different modes. An interface whose endpoints discovery does not report never holds an `endpoints` key.
- `manufacturer` and `product` hold when the device's strings equal the given non-empty text.
- `bcdDevice` holds when the device's release number lies in `min` to `max`, both inclusive, from 0 to 65535.
- `probes` lists 1 or more probes. A probe reads a feature report (`report` 0 to 255, `length` 1 to 65535) and expects `Answers`, `Stalls`, or `Bytes`. `Bytes` also takes `offset` and `bytes`, uppercase hex pairs the reply must hold at that offset; the other expectations take neither.

OpenJoystickDriver never switches a controller's mode. It tries the modes in record order and runs the first whose keys all hold. A probe is the costly key: it is read only after every other key of its mode holds, and a report that several probes name is read once. When no mode matches, the default mode runs. A mode without a probe can be selected on any route, while a mode with a probe needs a HID route, so a controller on another route, such as a Bluetooth LE GATT peripheral, runs a mode with a probe never.

A probe only reads. It cannot write to the controller. Each read gives up after 2 seconds. When a probe gets no usable reply, the selection stops, the controller stays enabled in its default mode, and OpenJoystickDriver logs a line that names the report. No usable reply means a timeout, an unavailable route, or any failure other than the controller's own refusal, such as a device that is not open, gone, or held exclusively. Only a stalled pipe (`0xE000404F` or `0xE0005000`) or an unsupported request (`kIOReturnUnsupported`) is a refusal. It satisfies `stalls` and fails the other expectations, so a stall where a mode expects `answers` leaves the default mode running.

A raw-USB record may list alternative modes too. They are selected at USB detection from the passive keys (`link`, `interfaceSignature`, `endpoints`, and the strings); a probe never holds on a raw-USB route, because it has no feature-report read, so a mode with probes there leaves the default running. Every mode follows the record-level rules of its own protocol for `input.layout`, `session.rumble`, `usb`, `server`, `route`, `tuning`, and `capabilities`, in a record with one mode as in a record with several. Exactly one mode has the id `default`, and the schema and the Swift decoder reject zero or two. A patch overrides `modes` as an array, so it restates every mode it keeps.

macOS reports a radio dongle as a USB device, so the `ProprietaryRadioReceiver` link comes from the model's own record: a model whose default mode runs a `Receiver` or `Dongle` variant reports it, and a mode keyed on that link refines the receiver. No bundled record attaches one product ID both through a dongle and over USB: the six receiver and dongle records (`045e:0291`, `045e:02a9`, `045e:0719`, `28de:1142`, `28de:1304`, `28de:1305`) each hold one default mode. A model that did would need an observed radio link, which nothing reports yet. Endpoint sets come from the raw USB scanner only. The IOKit registry publishes just the interface's `bNumEndpoints`, with no pipe or endpoint descriptor entries, so HID discovery reports no endpoints. A HID mode that names `endpoints` could never be selected, so the schema, the decoder and the Python validator refuse the record; only a raw-USB mode may name them.

The DualShock 3 record has the `bluetooth` mode above, which sends feature report `0xF4` (`42 03 00 00`) when the controller connects over classic Bluetooth, the enable report that Linux `hid-sony.c` sends. It also carries one mode that probes feature report `0xEF`. That mode is a candidate discriminator only: it runs the same protocol as the default, and the record does not say which unit is genuine. The `length` of 49 is a chosen length, the size of a Sixaxis input report, not a size recorded from a DualShock 3 reply.

Pairing is not part of the record. A DualShock 3 has to be paired with the Mac before a Bluetooth link exists, and the pairing steps belong to macOS or to a pairing tool, not to this data. The record describes only what runs once the link is up. Pairing a real DualShock 3 is still an open hardware check, so these docs list no verified steps.

## Connect a Switch 2 Controller Over Bluetooth LE

OpenJoystickDriver connects a Nintendo Switch 2 controller over Bluetooth LE only when its record names the GATT characteristic that carries vibration:

```json
"bluetoothLE": {
  "vibrationCharacteristic": "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149"
}
```

Write the UUID in uppercase. Only a `NintendoSwitch2` record takes `bluetoothLE`. The service looks for Switch 2 advertisements with the Nintendo vendor ID (`057E`) only.

A Switch 2 record without `bluetoothLE` connects over USB only, and `ojd record validate` and `ojd record show` say so. The bundled Switch 2 records have the section, and a `ControllerPatch` that leaves `bluetoothLE` out keeps the bundled value. A `Controller` for a new Switch 2 model needs its own `bluetoothLE`.

## Draft a Record From a Connected Controller

`ojd record draft CONTROLLER` builds a starting record for a connected controller. The service must be running.

1. Run `ojd record draft CONTROLLER > record.json`, where `CONTROLLER` is an ID from `ojd controller list` or the controller's VID:PID.
2. For 10 seconds, press every button and move each stick, trigger, and the D-pad. `--duration SECONDS` changes the time.
3. Read the bytes that changed. For each report byte that took more than one value, the command prints its offset and its lowest and highest value on stderr.

The record maps what the HID report descriptor states plainly: buttons 1 to 11 in the order the `HIDDescriptor` family reads them, X, Y, Rx, and Ry sticks, Z and Rz triggers, and the hat, with the `HIDReportLayout` family. When nothing maps, it names `HIDDescriptor` instead. Check every control against the changed bytes and correct the record before you install it. The draft is a `ControllerPatch` for a model with a bundled record and a `Controller` otherwise.

## Install a Record

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id).
2. Write the record file. Set `apiVersion` to `openjoystickdriver/v1alpha1` and `kind` to `Controller` or `ControllerPatch`.
3. Check the file. Run `ojd record validate FILE`.
4. Install the file. Run `ojd record install FILE`.

The running service applies the record when the folder changes. It connects each connected controller of that model again with the new record, and leaves other controllers connected. A controller that you disconnected stays disconnected. You do not need to restart the service or unplug the controller.

## Check Which Records Apply

Run `ojd record list`. Each line shows a model, its protocol family, and its layer: `bundled`, `package`, or `user`.

Run `ojd record show VVVV:PPPP` to see one model's effective record and the layer of each field.

OpenJoystickDriver skips a file that is not valid and uses the bundled record for that model. `ojd record list`, `ojd status`, and `ojd diagnose` name each skipped file and the reason.

## Remove a Record

1. Run `ojd record remove VVVV:PPPP`.
2. Confirm the deletion.

The command removes the `Controller` file and the patch file of that model. A bundled model then goes back to its bundled record.

## Schema Versions

Each file that OJD reads declares `apiVersion: openjoystickdriver/v1alpha1` and its `kind`, such as `Controller`, `ControllerPatch`, `VirtualDevice`, `Profile`, or `ModPackage`. Files do not declare `$schema`. OJD accepts only the `apiVersion` it supports and rejects every other one, a missing one, and a `kind` it does not read there. The error names the file, the version it found, and the supported one. It does not convert files. The schemas are flat files in `Resources/Schemas/`, and each `$id` is `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/<kind>.schema.json`. Those IDs are not published.

- Before 1.0, a `v1alpha1` schema may change incompatibly. The release notes list each such change.
- At 1.0 the schemas are promoted to `v1`. A `v1` schema takes only additive changes: a new optional field, or a new value where a reader can ignore it.
- A change that is not additive needs a new version, `v2`. OJD names the version it accepts, so a file for an unknown version is rejected rather than half read.

The `--json` output schema has its own release check: within a major version, or a minor version before 1.0, it only gains keys and values. See [Using the command line](Command-Line.md).

## Further Reading

- [Command reference](Command-Reference.md)
- [Writing controller mods](Writing-Controller-Mods.md)
- [Supported controllers](Supported-Controllers.md)
- [Generic HID controllers](Supported-Controllers.md#generic-hid-controllers)
