# Support Ladder

Try these five ways to add OpenJoystickDriver (OJD) support for a controller, from least work to most. Stop at the first that works.

## Contents

- [Step 1: Nothing](#step-1-nothing)
- [Step 2: A Patch](#step-2-a-patch)
- [Step 3: A Record](#step-3-a-record)
- [Step 4: A Generator Script](#step-4-a-generator-script)
- [Step 5: Source](#step-5-source)
- [Further Reading](#further-reading)

Steps 1 to 3 need no build and no pull request.

A patch or a record is a small XML property list that tells OJD how a controller works. `plutil -lint FILE.plist` checks one, and `plutil -convert json -o - FILE.plist` reads one as JSON. Each file declares `apiVersion` `openjoystickdriver/v1alpha3`.

## Step 1: Nothing

Many controllers work with no file. Without a record, OJD recognizes a controller by its interface signature (Xbox USB and GIP) or its HID report descriptor.

1. Run `ojd controller list` to find the vendor and product numbers (VID:PID, such as `045E:02EA`).
2. Run `ojd controller show VVVV:PPPP`. It shows the identity, handler, capabilities, and [virtual gamepad](Glossary.md#terms). For a device OJD doesn't handle, it shows the reason and next step.
3. In **Controllers**, click **Open Input Test** and press every control.

Stop here if every control reads correctly. If the controller is [Handled by macOS](Glossary.md#terms) and you want OJD to handle it, run `ojd controller claim VVVV:PPPP`.

## Step 2: A Patch

Use a patch when OJD knows your controller but one detail is wrong, such as a stick deadzone. A `ControllerPatch` changes only the differing fields of the bundled record. `selector` names the model, `patch` holds the changes, and `remove` lists key paths to delete. See [Controller records](Controller-Records.md#how-records-work).

1. Run `ojd record draft VVVV:PPPP > 045e-02ea.patch.plist` and press every control for 10 seconds. For a model with a bundled record, the draft is a patch.
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

3. Run `ojd record validate 045e-02ea.patch.plist`. It exits with code 1 for an invalid patch or one that changes nothing.
4. Run `ojd record install 045e-02ea.patch.plist`. The running service applies it.
5. Run `ojd record show 045E:02EA` to see the applied record and the layer of each field.

To undo it, run `ojd record remove 045E:02EA`.

## Step 3: A Record

Use a record when OJD has no entry for your controller. A `Controller` describes the whole model: modes, input, rumble, and tuning. For a model with a bundled record, write a patch instead.

1. Run `ojd record draft VVVV:PPPP > 1209-0001.plist` for a connected controller. To start from its SDL_GameControllerDB line, run `ojd record draft VVVV:PPPP --from-sdl > 1209-0001.plist` instead.
2. Correct the file. This record is the sample in [`docs/sdk/sample`](../docs/sdk/sample), with pid.codes test ID `1209:0001`:

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
4. Run `ojd record install 1209-0001.plist`. Add `--dry-run` to see the target path without writing.
5. Test the record against a capture. Run `ojd --json controller capture VVVV:PPPP > capture.jsonl`, then `ojd record test VVVV:PPPP --packets capture.jsonl --expect state.json`. It lists each differing field.

To share a record, put it in a [mod package](Writing-Controller-Mods.md).

## Step 4: A Generator Script

Use a generator script when several models share one layout. One JavaScript file returns the records of a product family.

1. Write the script. [Generating documents with scripts](Generating-Documents-with-Scripts.md) shows one for three records.
2. Print the documents with `ojd generate family.js`, or write them into a folder with `ojd generate family.js --output Controllers`.
3. Validate and install each file as in step 3: `ojd record validate Controllers/VVVV-PPPP.plist`, then `ojd record install Controllers/VVVV-PPPP.plist`.

## Step 5: Source

Use source when the controller needs a protocol family OJD lacks, such as a handshake or encryption. First check that steps 2 and 3 can't state the fact. A fact about one model is a record field, not a Swift branch. See [CONTRIBUTING.md](../CONTRIBUTING.md) and [Reporting a bug](Reporting-a-Bug.md).

## Further Reading

- [Start: add support for a controller](Start-Add-Support-for-a-Controller.md)
- [Controller records](Controller-Records.md)
- [Writing controller mods](Writing-Controller-Mods.md)
- [Command reference](Command-Reference.md)
