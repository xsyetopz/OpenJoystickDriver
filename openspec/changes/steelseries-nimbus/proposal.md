# Proposal

## Why

The SteelSeries Nimbus (`1038:1420`, USB) is a HID Gamepad with a 17-byte input report that has no report ID. OJD has no record for it, and two generic faults hide under it. A HID descriptor that declares the D-pad as Generic Desktop usages `0x90` to `0x93` gets no D-pad on the descriptor path, and the controls list of a HID descriptor controller claims Back, Start and both stick clicks for every pad, whatever the descriptor or the SDL mapping declares.

## What Changes

- Add the record `Resources/Controllers/1038/1038-1420.json`: pressure bytes as digital buttons at a threshold, L2 and R2 as analog triggers, Menu on Consumer `0x0223`, and the four stick axes with Y inverted.
- Map Generic Desktop usages `0x90` to `0x93` to the D-pad through a pressure threshold in the standard HID descriptor map, and read an SDL `b#` D-pad binding the same way.
- List only the controls that the usage map drives from usages the descriptor declares.
- OJD leaves the Nimbus to macOS (`server` stays `System`): macOS serves it natively and OJD only reads its input.
- Document the controller in `wiki/Supported-Controllers.md` and `CHANGELOG.md`.

## Capabilities

### New Capabilities

- `steelseries-nimbus`: how OJD reads the Nimbus, the generic D-pad usages and the controls list that follow from its descriptor.

### Modified Capabilities

None.

## Impact

- `Resources/Controllers/1038/`, `Resources/Protocols/hid-descriptor.json` and the Kit resources that `./Scripts/ojd catalog regenerate --write` writes.
- `HIDUsageMap`, `HIDDescriptorDriver` and `SDLMappingConverter` in `Sources/OpenJoystickDriverKit/Protocol/`.
- Tests: `SteelSeriesNimbusTests`, `SDLMappingConverterTests` and the Backbone One SDL fixture.
- The four player LEDs and the Bluetooth identity `0111:1420` stay outside this change.
