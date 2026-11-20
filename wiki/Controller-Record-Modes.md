# Controller Record Modes

Many controllers can act in more than one way. A switch on the back might turn one into an Xbox pad or a PlayStation pad. A mode is the part of a [controller record](Controller-Records.md) that tells OJD how to handle one of those ways.

A mode has two parts:

- The session: what OJD sends to the controller when it starts, while it runs, and when it stops.
- The match: how OJD picks the mode. It looks at the connection (link), the device's details, or the controller's answer to a question (a probe).

A pad can change identity with a switch, a key combination, or the cable. Each identity sends different reports. Describe each mode's session in your record, then say how OJD tells which mode is active.

```mermaid
flowchart LR
    pad[Controller] -->|"switch set to X"| mx[Mode X]
    pad -->|"switch set to P"| mp[Mode P]
    mx -->|"record says how to read it"| ojd[OJD]
    mp -->|"record says how to read it"| ojd
```

## Contents

- [Describe a Mode's Session](#describe-a-modes-session)
- [Offer Alternative Modes Chosen by Link, Keys, and Probes](#offer-alternative-modes-chosen-by-link-keys-and-probes)
- [Further Reading](#further-reading)

## Describe a Mode's Session

A mode's `session` lists the steps OJD runs around a controller session, like a pilot's checklist for takeoff, flight, and landing. A description's `defaults.session` uses the same keys. A mode runs only the steps its own `session` names. It never borrows steps from another mode. A `session` names at least one key.

```mermaid
flowchart LR
    C[control<br/>raw USB setup messages] --> S[startup<br/>fixed reports]
    S --> W[settleMilliseconds<br/>wait]
    W --> R[Running<br/>input, rumble, keepAlive]
    R --> X[shutdown<br/>goodbye packets]
```

- `startup`: 1 to 16 writes of one format. See [Send Fixed Reports at Startup](Controller-Records.md#send-fixed-reports-at-startup).
- `rumble`: the rumble template. See [Add Rumble to a Controller](Controller-Records.md#add-rumble-to-a-controller).
- `control` (raw USB): 1 to 16 vendor control transfers. They run in order, before the startup packets, in each handshake attempt.
- `settleMilliseconds` (raw USB, 1 to 60000): how long to wait after the handshake, before the first input transfer.
- `shutdown` (raw USB): 1 to 8 packets sent when the session closes. If one fails, OJD logs it and sends the next.
- `keepAlive` (raw-USB modes of `XboxXID` and `XboxXUSB`): `intervalMilliseconds` (1 to 60000) and 1 to 8 `writes`. Their descriptions declare no keep-alive, so the mode supplies it. Each write is a raw-USB packet with `bytes`, and can add `endpoint`, `timeoutMilliseconds`, and `sessionByte`.

A HID mode takes only `startup` and `rumble`. Write bytes as uppercase hex pairs with single spaces, such as `42 03 00 00`. Lowercase digits, a `0x` prefix, or other separators fail validation.

### Vendor Control Transfers

```xml
<key>session</key>
<dict>
 <key>control</key>
 <array>
  <dict>
   <key>bRequest</key>
   <integer>1</integer>
   <key>bmRequestType</key>
   <integer>192</integer>
   <key>match</key>
   <dict>
    <key>manufacturer</key>
    <string>SHANWAN</string>
   </dict>
   <key>wIndex</key>
   <integer>0</integer>
   <key>wLength</key>
   <integer>8</integer>
   <key>wValue</key>
   <integer>0</integer>
  </dict>
 </array>
</dict>
```

- `bmRequestType` is a vendor type: 64 to 67 (host to device) or 192 to 195 (device to host). `bRequest` is 0 to 255. `wValue` and `wIndex` are 0 to 65535.
- `wLength` is 0 to 64.
  - An IN transfer (192 to 195) reads `wLength` bytes. It needs a `wLength` of at least 1 and has no `data`.
  - An OUT transfer (64 to 67) writes `data`, and the byte count of `data` equals `wLength`.
  - An OUT transfer with `wLength` 0 has no data stage and no `data`.
- `timeoutMilliseconds` is 1 to 60000. The default is 1000.
- `delayMilliseconds` (0 to 1000) waits after the transfer.
- `toleratesRejection`: if the device rejects the transfer, OJD logs it and keeps going. Without it, startup fails.
- `match` limits which devices get the transfer. It takes `manufacturer`, `product` (non-empty text), and `bcdDevice` (`min`, `max`). Every key you give must hold. A device that doesn't report a value you named never gets the transfer. Without `match`, every device gets it.

## Offer Alternative Modes Chosen by Link, Keys, and Probes

Use modes when one VID:PID speaks more than one protocol (XInput, DInput, Switch mode). Use them too when it needs different handling over USB and Bluetooth.

Every record has a `modes` list. A controller runs the `protocol` of one mode. The mode with id `default` has no `match`, and it runs when no other mode matches.

A record can skip `default`. Then every mode needs a `match`. This suits a VID:PID that several models share, where the product string tells them apart.

```mermaid
flowchart TD
    P[Controller connects] --> M{Does a mode's match fit?}
    M -->|yes| U[Use that mode]
    M -->|no| D{Is there a default mode?}
    D -->|yes| UD[Use default]
    D -->|no| N[No mode matched]
```

```xml
<key>modes</key>
<array>
 <dict>
  <key>id</key>
  <string>default</string>
  <key>protocol</key>
  <dict>
   <key>family</key>
   <string>SonySixaxis</string>
  </dict>
 </dict>
 <dict>
  <key>id</key>
  <string>bluetooth</string>
  <key>match</key>
  <dict>
   <key>link</key>
   <string>BluetoothClassic</string>
  </dict>
  <key>protocol</key>
  <dict>
   <key>family</key>
   <string>SonySixaxis</string>
  </dict>
  <key>session</key>
  <dict>
   <key>startup</key>
   <array>
    <dict>
     <key>bytes</key>
     <string>42 03 00 00</string>
     <key>report</key>
     <dict>
      <key>id</key>
      <integer>244</integer>
      <key>kind</key>
      <string>Feature</string>
      <key>length</key>
      <integer>5</integer>
     </dict>
    </dict>
   </array>
  </dict>
 </dict>
 <dict>
  <key>id</key>
  <string>feature-ef-answers</string>
  <key>match</key>
  <dict>
   <key>probes</key>
   <array>
    <dict>
     <key>expect</key>
     <string>Answers</string>
     <key>length</key>
     <integer>49</integer>
     <key>report</key>
     <integer>239</integer>
    </dict>
   </array>
  </dict>
  <key>protocol</key>
  <dict>
   <key>family</key>
   <string>SonySixaxis</string>
  </dict>
 </dict>
</array>
```

- `id`: lowercase words joined by hyphens, unique in a record.
- `protocol`: the protocol the mode runs.
- `match`: required except in `default`, with at least one key. OJD selects a mode only when all its keys hold.
- `interface` (`first` and `last`, inclusive, 0 to 255): picks the USB interface a HID mode binds to. OJD takes the lowest one in range that the controller has. A raw-USB mode has no `interface`, because its `usb` section already names the interface it claims.
- `session`: the mode's steps. See [Describe a Mode's Session](#describe-a-modes-session). A mode inherits nothing from the default mode.

The `match` keys:

- `link`: `USB`, `BluetoothClassic`, `BluetoothLE`, or `ProprietaryRadioReceiver`. It holds when every interface reaches the controller over that link, as discovery saw it. Without discovery data, OJD uses `proprietary-radio-receiver` for a model whose own record runs a `receiver` or `dongle` variant. Otherwise it uses the link macOS reports.
- `interfaceSignature`: holds when one interface has the given `interfaceClass`, `interfaceSubclass`, and `interfaceProtocol` (each 0 to 255). When given, it also checks:
  - the HID `usagePage` and `usage` (0 to 65535; `usage` needs `usagePage`)
  - the whole `endpoints` set

  `endpoints` lists 1 or more endpoints. Each has at least one of `address` (0 to 255), `direction` (`In`, `Out`), `transferType` (`Control`, `Isochronous`, `Bulk`, `Interrupt`), and `maxPacketSize` (0 to 65535). Each listed endpoint pairs with a different endpoint of the interface, with none left over. So two interfaces with the same class numbers but different endpoints pick different modes. If discovery doesn't report an interface's endpoints, an `endpoints` key never holds for it.
- `manufacturer`, `product`: hold when the device's strings equal the given non-empty text.
- `bcdDevice`: holds when the release number lies in `min` to `max` (inclusive, 0 to 65535).
- `probes`: 1 or more. A probe reads a feature report (`report` 0 to 255, `length` 1 to 65535) and expects `Answers`, `Stalls`, or `Bytes`. `Bytes` also takes `offset` (0 to 65534) and `bytes`, the uppercase hex pairs the reply must hold there. The others take neither.

OJD reads the controller's mode. It never changes it. It tries modes in record order and runs the first one whose keys all hold.

A probe is the slowest key, so OJD checks it last, after the mode's other keys hold. If several probes name the same report, OJD reads it once.

When no mode matches, the default mode runs. A record without a default leaves the controller unsupported with the reason `NoModeMatched`. OJD sends it nothing, and the Controllers page says it matches no supported model.

A mode with a probe needs a HID route. It never runs on another route, such as a Bluetooth LE GATT peripheral.

A probe only reads, and gives up after 2 seconds. Without a usable reply, OJD stops choosing. The controller stays in its default mode, or unsupported if there is none. OJD logs a line naming the report. These give no usable reply:

- a timeout
- a route that isn't available
- any failure other than a refusal, such as a device that isn't open, is gone, or is held exclusively

A refusal is a stalled pipe (`0xE000404F` or `0xE0005000`) or an unsupported request (`kIOReturnUnsupported`). A refusal satisfies `Stalls` and fails the other expectations. So a stall where a mode expects `Answers` leaves the default mode running.

A raw-USB record can list alternative modes too. OJD chooses among them when it detects the USB device, using the keys it can see without asking: `link`, `interfaceSignature`, `endpoints`, and the strings. A raw-USB route can't read a feature report, so a probe never holds there. A mode with probes on that route leaves the default mode running.

Every mode follows its protocol's record rules for `input.layout`, `session.rumble`, `usb`, `server`, `route`, `heldByAppleDriver`, `tuning`, and `capabilities`. One exception: a `capabilities` delta needs only one mode's family description to declare it. A mode whose driver doesn't declare the delta ignores it.

At most one mode has the id `default`. A patch merges `modes` by `id`, so it names only the modes it changes or adds.

macOS reports a radio dongle as a USB device. So the `ProprietaryRadioReceiver` link comes from the model's own record: a model whose default mode runs a `Receiver` or `Dongle` variant reports it. A mode keyed on that link then narrows down the receiver. No bundled record uses one product ID both through a dongle and over USB. The six receiver and dongle records (`045e:0291`, `045e:02a9`, `045e:0719`, `28de:1142`, `28de:1304`, `28de:1305`) each have one default mode.

Only the raw USB scanner reports endpoint sets. The IOKit registry shows only the interface's `bNumEndpoints`. So a HID mode that names `endpoints` could never be chosen, and the schema, the decoder, and the Python validator refuse it. Only a raw-USB mode may name `endpoints`.

The DualShock 3 record has the `bluetooth` mode shown above. When the controller connects over Bluetooth Classic, it sends feature report `0xF4` (`42 03 00 00`), as Linux `hid-sony.c` does. Its other mode probes feature report `0xEF`. That probe is only a candidate way to tell units apart: it runs the same protocol as the default mode, and the record doesn't say which unit is genuine. The `length` of 49 is the size of a Sixaxis input report. It was picked by hand, not read from a DualShock 3 reply.

Pairing is not part of the record. Pair a DualShock 3 with the Mac first, with macOS or a pairing tool, so a Bluetooth link exists. Pairing a real DualShock 3 is still an open hardware check, so these docs list no pairing steps.

### Read Another Input In One Mode

Use this when two pads share a model ID but send different reports. A mode other than `default` can have its own `input` (`layouts` or `hidUsageMap`). While that mode runs, its `input` replaces the record's. Other modes read the record's `input`.

- A mode `input` has no `descriptorShapes`.
- The `default` mode and an idle mode have no `input`.
- A patch mode entry sets `input` like any other key.

Two examples: the `1949:0402` record reads touch contacts only in its `v3` mode. The `054C:0268` patch maps the face buttons of the NITHO MLT-KRMA-K only when the manufacturer is `Sony Computer Entertainment`.

### Record an Identity That Handles Nothing

Use `idle` for a device OJD knows but must leave alone. One example is a receiver that shows the controller only later, under another ID. While an `idle` mode matches, OJD does nothing with the device. It is unsupported with the named reason, gets no data and no [virtual gamepad](Glossary.md#terms), and the Controllers page says why. The value is one of:

- `NoControllerLinked`: a receiver with no controller linked
- `Bootloader`: a controller in its bootloader

An idle mode has no `interface`, `session`, or `input`. A record whose modes are all idle has no `usb`, `bluetoothLE`, `capabilities`, `server`, `route`, `heldByAppleDriver`, `input`, or `tuning`. To add controls, replace `idle` with the `protocol` and `input` of a captured descriptor. A patch sets `idle` on a mode entry like any other key.

A record whose default mode is `idle: Bootloader` belongs only to the bundled catalog. OJD refuses a user or package file that adds or patches that identity.

## Further Reading

- [Controller Records](Controller-Records.md)
- [Writing Controller Mods](Writing-Controller-Mods.md)
