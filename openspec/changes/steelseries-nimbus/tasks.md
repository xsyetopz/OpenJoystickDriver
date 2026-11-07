# Tasks

## 1. Generic Fixes

- [x] 1.1 Map Generic Desktop usages `0x90` to `0x93` to the D-pad in `Resources/Protocols/hid-descriptor.json`. Reached by `HIDDescriptorDriver` at session start.
- [x] 1.2 Read an SDL `b#` D-pad binding as an `AxisDpad` half in `SDLMappingConverter`. Reached by the catalog generator.
- [x] 1.3 List only the controls that the descriptor declares in `HIDDescriptorDriver.capabilities`.

## 2. Record and Tests

- [x] 2.1 Author `Resources/Controllers/1038/1038-1420.json` and run `./Scripts/ojd catalog regenerate --write`.
- [x] 2.2 Cover the descriptor layout, thresholds, triggers, Menu, stick signs and the controls list in `SteelSeriesNimbusTests`.
- [x] 2.3 Update `SDLMappingConverterTests` and the Backbone One fixture for D-pad button bindings.

## 3. Docs

- [x] 3.1 Add the Nimbus section to `wiki/Supported-Controllers.md` and the entries to `CHANGELOG.md`.

## 4. Hardware Checks

- [ ] 4.1 Capture each control (D-pad, buttons 1 to 8, Menu, both sticks) with the controller connected over USB.
- [ ] 4.2 Confirm the button order and the sign of each stick axis from the capture.
- [ ] 4.3 Confirm the pressure threshold of 0.5 for the D-pad and the buttons.
- [ ] 4.4 Confirm that Menu is Consumer `0x0223` and reads as Start.
- [ ] 4.5 Check the four player LEDs and decide how a record describes the output report.
- [ ] 4.6 Check the Bluetooth identity `0111:1420`, then add its record.
