# Support ladder

Support a controller with the first of five steps that works, and stop there: nothing, a patch, a record, a generator script, and source.

## Contents

- [Step 1: Nothing](#step-1-nothing)
- [Step 2: A Patch](#step-2-a-patch)
- [Step 3: A Record](#step-3-a-record)
- [Step 4: A Generator Script](#step-4-a-generator-script)
- [Step 5: Source](#step-5-source)
- [Further Reading](#further-reading)

Steps 1 to 3 need no build and no pull request. Every document is an XML property list. `plutil -lint FILE.plist` checks one, `plutil -convert json -o - FILE.plist` reads one as JSON, and `plutil -convert xml1 -o FILE.plist FILE.json` writes one from JSON. Each document declares `apiVersion` `openjoystickdriver/v1alpha3`.

## Step 1: Nothing

OJD binds a controller without a record by its interface signature (Xbox USB and GIP) or by its HID report descriptor.

1. Run `ojd controller list` and find the VID:PID of the controller.
2. Run `ojd controller show VVVV:PPPP`. It shows the identity, who serves the controller, its capabilities, and its virtual gamepad.
3. Open **Open Input Test...** in the **Controllers** area, and press every control.

Stop here when every control reads correctly. When macOS serves the controller itself and you want OJD to serve it, run `ojd controller claim VVVV:PPPP`.

## Step 2: A Patch

A `ControllerPatch` changes the fields of a bundled record that differ: an endpoint, a startup write, a control, a tuning value. The `selector` names the model, `patch` holds the values to change, and `remove` lists key paths to delete. See [Controller records](Controller-Records.md#how-records-work).

1. Run `ojd record draft VVVV:PPPP > 045e-02ea.patch.plist` and press every control for 10 seconds. For a model with a bundled record, the draft is a patch. Or write the file yourself.
2. Correct the file. This complete patch sets the stick deadzone of `045E:02EA`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>apiVersion</key>
	<string>openjoystickdriver/v1alpha3</string>
	<key>kind</key>
	<string>ControllerPatch</string>
	<key>patch</key>
	<dict>
		<key>tuning</key>
		<dict>
			<key>stickDeadzone</key>
			<real>0.08</real>
		</dict>
	</dict>
	<key>selector</key>
	<dict>
		<key>productID</key>
		<integer>746</integer>
		<key>vendorID</key>
		<integer>1118</integer>
	</dict>
</dict>
</plist>
```

3. Run `ojd record validate 045e-02ea.patch.plist`. It exits with code 1 when the patch is invalid, and refuses a patch that changes nothing in the record.
4. Run `ojd record install 045e-02ea.patch.plist`. The running service applies it without a replug.
5. Run `ojd record show 045E:02EA` to see the effective record and the layer of each field.

To undo, run `ojd record remove 045E:02EA`.

## Step 3: A Record

A `Controller` states the whole model: modes, input, rumble, and tuning. OJD refuses a `Controller` for a model that has a bundled record; write a patch instead.

1. Run `ojd record draft VVVV:PPPP > 1209-0001.plist` for a connected controller, or `ojd record draft VVVV:PPPP --from-sdl > 1209-0001.plist` to start from its SDL_GameControllerDB line.
2. Correct the file. This complete record is the sample controller of [`docs/sdk/sample`](../docs/sdk/sample) (`1209:0001`, a pid.codes test ID):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>apiVersion</key>
	<string>openjoystickdriver/v1alpha3</string>
	<key>input</key>
	<dict>
		<key>layouts</key>
		<array>
			<dict>
				<key>axes</key>
				<array>
					<dict>
						<key>bitOffset</key>
						<integer>16</integer>
						<key>bitSize</key>
						<integer>8</integer>
						<key>control</key>
						<string>LeftStickX</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>24</integer>
						<key>bitSize</key>
						<integer>8</integer>
						<key>control</key>
						<string>LeftStickY</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>32</integer>
						<key>bitSize</key>
						<integer>8</integer>
						<key>control</key>
						<string>RightStickX</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>40</integer>
						<key>bitSize</key>
						<integer>8</integer>
						<key>control</key>
						<string>RightStickY</string>
					</dict>
				</array>
				<key>buttons</key>
				<array>
					<dict>
						<key>bitOffset</key>
						<integer>0</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>South</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>1</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>East</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>2</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>West</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>3</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>North</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>4</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>LeftShoulder</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>5</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>RightShoulder</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>6</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>Back</string>
					</dict>
					<dict>
						<key>bitOffset</key>
						<integer>7</integer>
						<key>bitSize</key>
						<integer>1</integer>
						<key>control</key>
						<string>Start</string>
					</dict>
				</array>
				<key>hat</key>
				<array>
					<dict>
						<key>bitOffset</key>
						<integer>8</integer>
						<key>bitSize</key>
						<integer>4</integer>
						<key>encoding</key>
						<string>EightWay</string>
					</dict>
				</array>
				<key>leftTrigger</key>
				<dict>
					<key>bitOffset</key>
					<integer>48</integer>
					<key>bitSize</key>
					<integer>8</integer>
				</dict>
				<key>report</key>
				<dict>
					<key>length</key>
					<dict>
						<key>atLeast</key>
						<integer>8</integer>
					</dict>
				</dict>
				<key>rightTrigger</key>
				<dict>
					<key>bitOffset</key>
					<integer>56</integer>
					<key>bitSize</key>
					<integer>8</integer>
				</dict>
			</dict>
		</array>
	</dict>
	<key>kind</key>
	<string>Controller</string>
	<key>modes</key>
	<array>
		<dict>
			<key>id</key>
			<string>default</string>
			<key>protocol</key>
			<dict>
				<key>family</key>
				<string>HIDReportLayout</string>
			</dict>
		</dict>
	</array>
	<key>productID</key>
	<integer>1</integer>
	<key>vendorID</key>
	<integer>4617</integer>
</dict>
</plist>
```

3. Run `ojd record validate 1209-0001.plist`.
4. Run `ojd record install 1209-0001.plist`. Add `--dry-run` to see the target path and write nothing.
5. Replay a capture against the record: run `ojd --json controller capture VVVV:PPPP > capture.jsonl`, then `ojd record test VVVV:PPPP --packets capture.jsonl --expect state.json`. The command lists each control that differs.

To share a record with others, pack it in a [mod package](Writing-Controller-Mods.md).

## Step 4: A Generator Script

One JavaScript file whose `generate` function returns the records of a product family. Use it when several models share one layout and differ in a few values.

1. Write the script. [Generating documents with scripts](Generating-Documents-with-Scripts.md) shows one that writes three records.
2. Print the documents: `ojd generate family.js`.
3. Write them into a folder: `ojd generate family.js --output Controllers`. The command checks every document before it writes any, and writes nothing when one fails.
4. Validate and install each file as in step 3: `ojd record validate Controllers/VVVV-PPPP.plist`, then `ojd record install Controllers/VVVV-PPPP.plist`.

## Step 5: Source

A protocol family OJD lacks needs source: a handshake, an encryption, or a transport that no document can state. Before you write Swift, check that steps 2 and 3 cannot state the fact: a fact about one model is a record field and never a model branch in Swift. [CONTRIBUTING.md](../CONTRIBUTING.md) lists the setup and the checks, and [Reporting a bug](Reporting-a-Bug.md) lists what to include with a capture.

## Further Reading

- [Start: add support for a controller](Start-Add-Support-for-a-Controller.md)
- [Controller records](Controller-Records.md)
- [Writing controller mods](Writing-Controller-Mods.md)
- [Command reference](Command-Reference.md)
