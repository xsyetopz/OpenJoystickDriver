Request for owners of an Xbox controller with identity `045E:02EA`, `045E:0B00` or `045E:0B12`. Destination issue is undecided: post it where the owners are, or in an issue of its own.

Apple's driver holds these three controllers and shows them to games as a macOS gamepad. I want to know whether OJD can read the pad through Apple's HID device and hide that device from games, because that decides whether a later release can drop the extension.

1. Install the tester build posted in Discord `#tester-builds`.
2. Plug the controller in by cable and run:
   ```
   ojd controller list
   ojd controller show VVVV:PPPP
   ojd transport-extension status
   ```
   Replace `VVVV:PPPP` with your controller's identity from the list. Copy all three outputs.
3. Press each control once while this runs:
   ```
   ojd controller watch VVVV:PPPP --duration 60
   ```
   Tell me whether OJD saw each press.
4. With the same controller, open a game or `OpenJoystickDriverGameControllerViewer` and tell me whether it lists one gamepad or two while OJD runs.
5. Run:
   ```
   ojd diagnose --output support-apple-hid.txt
   ```
   Read the file before you share it, then attach it.

State the identity, your macOS version, and whether the transport extension was active.
