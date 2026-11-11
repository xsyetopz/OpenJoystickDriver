## ADDED Requirements

### Requirement: A Controller With No Record Is Served by Its Protocol

OJD SHALL serve a controller that has no record when its USB interface signature names a protocol family OJD has, or when its HID descriptor meets the `HIDDescriptor` contract. The user MUST NOT need a record, a patch, or a setting for such a controller.

#### Scenario: Xbox 360 class pad with no record

- **WHEN** a pad with no record exposes the XUSB interface signature
- **THEN** OJD binds it by that signature, publishes its input, and `ojd controller show` names the rule `InterfaceSignature`

#### Scenario: HID pad with a database line

- **WHEN** a HID pad with no record has a line in the bundled SDL_GameControllerDB
- **THEN** OJD maps its controls from that line and publishes its input

#### Scenario: HID pad with no database line

- **WHEN** a HID pad with no record and no database line meets the `HIDDescriptor` contract
- **THEN** OJD maps its controls from the standard HID usage map and publishes its input

### Requirement: A Pad Stays With macOS Only When macOS Lists a Controller for It

OJD SHALL leave a HID pad to macOS only while the GameController framework lists a controller for it. OJD MUST serve a pad for which `GCController.supportsHIDDevice` answers yes and GameController lists no controller, and a record's `server` MUST override the detection in both directions.

#### Scenario: Pad that macOS supports and does not list

- **WHEN** a HID pad passes `GCController.supportsHIDDevice`, GameController lists no controller for it within the settle time, and its record names no server
- **THEN** OJD takes the pad and publishes its virtual gamepad

#### Scenario: Pad that macOS lists

- **WHEN** GameController lists a controller for a connected HID pad whose record names no server
- **THEN** OJD publishes no gamepad for it and `ojd controller show` reports `Served by System`

#### Scenario: Record that names the server

- **WHEN** a record or patch sets `server` to `System` for a pad that GameController does not list
- **THEN** OJD leaves the pad to macOS

#### Scenario: Second-controller warning

- **WHEN** OJD serves a pad and GameController lists no controller for the physical pad
- **THEN** `ojd controller list` prints no warning about a second system controller

### Requirement: A Controller That Is Not Served Says Why and What to Do

OJD SHALL show, for a connected controller it does not serve, the reason and the next step of the support ladder: draft a record, or report the controller with a capture.

#### Scenario: HID pad that fails the contract

- **WHEN** a connected HID pad fails the `HIDDescriptor` contract and has no record
- **THEN** the controller detail shows the reason and offers to draft a record

#### Scenario: Unknown USB protocol

- **WHEN** a connected USB device matches no family and has no record
- **THEN** `ojd controller show` prints the reason `NoProtocolMatch` and the command that captures its traffic

### Requirement: A Per-Model Fact Is a Record Field

OJD SHALL take every fact that belongs to one controller model from a record or a patch: its identity, modes, mode matches, endpoints, startup writes, input, rumble, idle state, and tuning. Swift source MUST NOT name a vendor and product pair outside the driver extension's match list.

#### Scenario: Model identifier added to Swift

- **WHEN** a Swift file under `Sources/` compares a device with a literal vendor and product pair outside the driver extension's match list
- **THEN** the repository check fails and names the file and line

#### Scenario: Controller fixed in this release

- **WHEN** the release adds support for a controller of a family OJD has
- **THEN** the change holds a record or a patch for that model and no Swift branch for it

### Requirement: An Input Layout Applies to Any Protocol Family

OJD SHALL decode with a record's `input.layouts` for every protocol family. A layout MUST change only the controls it names in the reports it selects; the family's decoder handles every other report and control.

#### Scenario: GIP device with its own report shape

- **WHEN** an `XboxGIP` record holds a layout for the input report and the device sends that report
- **THEN** OJD publishes the controls the layout names from the bytes the layout names

#### Scenario: Control the layout leaves out

- **WHEN** an `XboxXUSB` patch holds a layout that names one button
- **THEN** OJD decodes that button from the layout and every other control as the family does

#### Scenario: Report no layout selects

- **WHEN** the device sends a report that no layout of the record selects
- **THEN** the family's decoder handles it

### Requirement: Idle Is a State of a Mode

A record SHALL mark a mode as idle with `idle` and a reason, `NoControllerLinked` or `Bootloader`. OJD MUST send no data to a device while an idle mode matches it and MUST publish no gamepad for it. A record MUST NOT hold `idle` outside a mode.

#### Scenario: Receiver with no pad linked

- **WHEN** a receiver's record holds an idle mode that matches the product string `IDLE` and the receiver reports that string
- **THEN** OJD lists the receiver as idle with the text for `NoControllerLinked` and sends it nothing

#### Scenario: Receiver with a pad linked

- **WHEN** the same receiver reports another product string
- **THEN** OJD binds the record's default mode and publishes input

#### Scenario: Record-level flag

- **WHEN** a record holds `idle` beside `modes`
- **THEN** the reader refuses it as an unknown property

#### Scenario: Migration of an idle record

- **WHEN** `ojd migrate` converts a `v1alpha2` record that holds `"idle": true`
- **THEN** the converted record's default mode holds `idle` with the reason `NoControllerLinked`

### Requirement: A Bootloader Identity Receives Nothing

OJD SHALL send no data to a device whose bundled record has a default mode that is idle for `Bootloader`, and MUST refuse a user or package document that replaces or patches that record.

#### Scenario: Pad in bootloader state

- **WHEN** an 8BitDo pad connects as `2DC8:3208`
- **THEN** OJD lists it with the bootloader text and sends it nothing

#### Scenario: User record for a bootloader identity

- **WHEN** the user installs a record for `2DC8:3208`
- **THEN** `ojd record install` refuses it and names the reason

### Requirement: A Record Change Applies Without a Restart

The service SHALL apply a record, patch, or package the user adds, changes, or removes without a restart of the service, and MUST report a file it skipped with the reason.

#### Scenario: Record installed while the controller is connected

- **WHEN** the user runs `ojd record install` for a connected controller
- **THEN** the controller's session restarts with that record and `ojd record show` names the layer `User`

#### Scenario: Property list saved from an editor

- **WHEN** the user saves a `.plist` record into `Controllers/` from a text editor
- **THEN** the service applies it

#### Scenario: Invalid file

- **WHEN** the saved file breaks a schema rule
- **THEN** the service keeps the record in force before the change, and `ojd record list` names the file, the key path, and the rule

### Requirement: One Command Path Leads From a Controller to an Installed Record

OJD SHALL provide commands that draft a record from a connected controller, check it, replay a capture through it, and install it, each reading and writing the current property-list format.

#### Scenario: Draft to install

- **WHEN** the user pipes `ojd record draft` for a connected HID pad into `ojd record install -`
- **THEN** the record folder holds `vvvv-pppp.plist` and the service applies it

#### Scenario: Replay before install

- **WHEN** the user runs `ojd record test` with a capture and an expected state
- **THEN** the command reports each control that differs, or a match

### Requirement: The Support Ladder Is Documented for People and Agents

The wiki SHALL describe the steps to support a controller in order (nothing, a patch, a record, a generator script, a source change) with the command for each and one complete example of a patch and of a record. `llms.txt` and `llms-full.txt` MUST carry the same steps.

#### Scenario: Reader with an unsupported pad

- **WHEN** a reader follows the wiki page from its first step for a HID pad OJD maps wrongly
- **THEN** the reader ends with an installed patch and edits no source file

#### Scenario: Agent instructions

- **WHEN** an agent reads `llms.txt`
- **THEN** it finds the ladder, the schema location, and the commands `record draft`, `record validate`, `record test`, and `record install`

### Requirement: A Draft Starts From Any Connected Device

`ojd record draft` SHALL accept every connected controller, served or not. For a device with a HID gamepad interface it MUST draft a `HIDDescriptor` mode from the descriptor; for a device with none it MUST draft the identity and one mode per interface signature and name what the user has to add.

#### Scenario: Device OJD does not serve

- **WHEN** the user runs `ojd record draft` for a connected controller that OJD lists as not served
- **THEN** the command writes a draft and does not exit with `E2012`

#### Scenario: Device with a HID interface and a record that does not fit

- **WHEN** the device has a HID gamepad interface and a bundled record whose modes fit none of its interfaces
- **THEN** the command writes a patch that adds a `HIDDescriptor` mode matched on that interface

#### Scenario: Device with no HID interface

- **WHEN** the device has only vendor-class interfaces
- **THEN** the draft holds the identity and each interface signature, and the command names the input section as missing

### Requirement: A Known Controller Falls Back to Its HID Descriptor

OJD SHALL serve a controller by its HID descriptor when the controller has a record, no mode of the record fits the interfaces the device exposes, and a HID interface of the device meets the `HIDDescriptor` contract. OJD MUST show that the record did not fit.

#### Scenario: Dongle that exposes HID where the record expects another interface

- **WHEN** a device with a record exposes only HID gamepad interfaces and the record's modes name another interface class
- **THEN** OJD publishes the controller's input from the HID descriptor
- **AND** the controller detail and `ojd controller show` say that the record did not fit and name the rule `HIDDescriptor`

#### Scenario: No HID interface that meets the contract

- **WHEN** no mode fits and no HID interface meets the contract
- **THEN** OJD does not serve the device and shows the reason and the next step

#### Scenario: Idle mode

- **WHEN** an idle mode of the record matches the device
- **THEN** OJD does not fall back and sends the device nothing

### Requirement: OJD Takes Only a Device It Serves

OJD SHALL open a HID device for its exclusive use only after it has decided to serve that device.

#### Scenario: HID device OJD does not serve

- **WHEN** a HID device arrives that OJD will not serve
- **THEN** OJD does not seize it, and another app still reads its input

#### Scenario: HID device OJD serves

- **WHEN** a HID device arrives that OJD serves
- **THEN** OJD seizes it and publishes its virtual gamepad
