# InputConfig preset library: import measurement

This page measures whether an importer for InputConfig's library presets is worth writing. It writes no importer. Each claim is marked observed (read in a file or printed by the script) or inferred.

## Source and scope

- Observed: the repository is `https://github.com/ryleighnewman/InputConfig`, read at commit `958bdd97ceecb182004b3d7d8521761b5a7e7756` ("1.8 (34)"), in a clone kept outside this repository. Nothing from the clone was run or built.
- Observed: the library is a JSON array in the Swift raw string `ExamplePresets.swift` (`static let libraryJSON`, decoded into `SmartPresetProfile` at line 2996). It holds 456 profiles with 456 distinct ids: 294 `game`, 125 `app`, 37 `workflow`. The README calls it "more than 450". The app also ships built-in presets written as Swift code (`ExamplePresets.swift`, `static var ...: Preset`). They number 46. They are outside this measurement; they are Swift values, not data.
- Observed: the license file is `LICENSE` at the repository root, MIT, "Copyright (c) 2026 Ryleigh Newman". The repository has no `NOTICE` file and no separate license for the preset data.

## The library preset format

A profile has `id`, `category`, `displayName`, `subtitle`, `appPath`, `launchURL`, `light` (r, g, b), `confineCursor`, `autoRecenter`, `hideCursor`, `bindings`, `tips`, and in one profile `drive`. A binding has `input`, `outputs`, `note`, and optionally `hold`/`holdMs`, `double`/`doubleMs`, `with`, `toggle`, `turbo`, `repeatCount`/`repeatMs`, `deadzone`, `outer`, `curve`, `variable`, `ramp`, `rumble`, `speak`, `needs` (`SmartPresetProfile.Binding`).

- Observed: the library is controller-independent. An input is a GameController index: `btn 0..13`, `axi 0..5` with a sign, `hat 0 U|D|L|R`. The header of `ExamplePresets.swift` gives the indices: 0 to 3 face buttons, 4 and 5 shoulders, 8 Options/Share, 9 Menu/Start, 10 Home, 11 and 12 stick clicks, 13 touchpad; axes 0 to 3 sticks, 4 and 5 triggers. The Smart Preset Maker fuses a profile with a chosen controller.
- Observed: an output is a text token. Keys are USB HID usage codes (`key 4` is A, `key 227` is Left Command). The library uses `key`, `mbt` (0, 1, 2 = left, right, middle), `mou <axis> <sign> <speed>`, `whe <axis> <sign> <speed>`, `whs <axis> <sign>`, and one `sys dct`. The row counts are in the script output below.
- Observed: the other output types in `OutputType` (MIDI, `txt`, `app`, `avl`, `lit`, `cpf`) do not occur in the library.

## How one preset maps to an OJD profile

The OJD shape is `Resources/Schemas/profile.schema.json` (`v1alpha3`). One library preset becomes one profile for one controller model, because the profile names a `device` (vendor and product id) and the library names none. Inferred: an importer must ask for a model, so 456 presets make 456 profiles per model chosen, and a source the model lacks (`btn 13`, `btn 10`) needs a decision.

| Library field | OJD field | Result |
| --- | --- | --- |
| `displayName` | `name` (at most 80 characters, no outer spaces) | maps; the script checks the length |
| (generated) | `id`, `apiVersion`, `kind`, `device` | importer supplies |
| `btn 0..3` | `Button` `South`, `East`, `West`, `North` | maps |
| `btn 4`, `5` | `LeftShoulder`, `RightShoulder` | maps |
| `btn 6`, `7` | `LeftTrigger`, `RightTrigger` as buttons | maps (does not occur in the library) |
| `btn 8`, `9`, `10` | `Back`, `Start`, `Guide` | maps |
| `btn 11`, `12`, `13` | `LeftStickClick`, `RightStickClick`, `TouchpadClick` | maps |
| `axi 0..3 +/-` | `AxisDirection` on `LeftStickX/Y`, `RightStickX/Y`, `Positive`/`Negative` | maps; see the Y direction note |
| `axi 4 +`, `axi 5 +` | `AxisDirection` `Positive` on `LeftTrigger`, `RightTrigger` | maps |
| `hat 0 U/D/L/R` | `Dpad` `DpadUp/Down/Left/Right` | maps |
| `key N` (not a modifier) | `Keyboard` `key` | maps for every code in the library (the script lists the codes that have an OJD name) |
| `key 224..227` with a key in the same row | `Keyboard` `modifiers` (`Control`, `Shift`, `Alt`, `Meta`) | maps |
| `key 224..227` alone | none | blocks |
| several outputs in one row | the first key is `destination`; the rest are `additionalActions` | maps |
| `mbt 0, 1, 2` | `MouseButton` `Left`, `Right`, `Middle` | maps |
| `mou <axis> <sign> <speed>` | `MouseMovement` `X`/`Y`; `-` is `axisTuning.inverted`; speed is `axisTuning.gain` | maps; speed needs calibration |
| `whe <axis> <sign> <speed>` | `Scroll` `X`/`Y`, same tuning | maps; speed needs calibration |
| `whs` | none | blocks |
| `sys dct` (start dictation) | `systemKey` has no dictation; `systemAction` holds only `MissionControl` | blocks |
| `hold` + `holdMs` | `longHold` (`destination`, `durationMs` 100 to 5000) | maps for one output |
| `double` | `multiTap` with `count` 2 | maps for one output |
| `toggle` | `behavior` `Toggle` | maps |
| `repeatCount` + `repeatMs` | a `Macro` of `Tap`, `Wait`, `Tap` (16 macros at most) | maps |
| `needs` | the source exists only on a model that has it | maps per model |
| `light` | `physicalColor` | maps for models with a light |
| `confineCursor` | none | blocks (no match for `confine`, `recenter`, or `hideCursor` in `Sources`, `Resources`, `wiki`, or `docs`) |
| `autoRecenter`, `hideCursor` | none | would block; no profile in the library sets them |
| `appPath` | `applicationScope` needs a bundle identifier, which the data lacks; InputConfig also launches the app when the preset starts, and OJD has no launch on activation | blocks |
| `launchURL` | no profile-level launch | blocks |
| `drive` (one-stick driving) | none | blocks |
| `subtitle`, `tips`, row `note`, `category` | none (`additionalProperties` is `false`) | text only; not counted |

Notes on the table:

- Observed: `Destination.swift` and the schema define a `Keyboard` destination with a required `key` from a list that has no modifier key. A row that holds Shift, Control, Option, or Command alone, such as sprint on Left Shift, has no OJD destination.
- Observed: in the Minecraft row set, `axi 1 -` is "Walk forward" (`key 26`), so the library takes negative as up. `wiki/Controller-Records.md` lists W3C as "negative is left or up" and Apple GameController as "positive up". Not checked: which of the two the OJD engine reads for `LeftStickY`, which no page traces. An importer needs that answer before it writes any `axi 1` or `axi 3` row. It decides nothing in the counts.
- Inferred: a speed of 6 to 28 in `mou` and `whe` has no stated unit in OJD. The importer would pick a gain per speed by measuring. The counts treat speed as mapped; if a lossless speed is required, the 360 presets with `mou` and 130 with `whe` need a measurement first.
- Inferred: `hold` and `double` map by type and range. The timing semantics (the tap output, and when it fires) were not compared; two presets use them.

## Counting rule

- A preset maps without loss when it has no blocker. A blocker is a binding, a modifier, or a setting of the preset with no OJD profile equivalent, as the table marks it.
- A feature is counted once per preset, however many rows use it. A preset can have several blockers, so the per-feature counts add up to more than the blocked total. The bracketed figure is the presets whose only blocker is that feature.
- Descriptive text (`subtitle`, `tips`, row `note`, `category`) is not a binding, modifier, or setting and is not counted. All 456 presets carry such text, so a faithful import loses it unless OJD adds a notes field; with text counted, 0 of 456 are lossless.
- Two totals are printed: all rules, and bindings only (the preset-level settings `confineCursor`, `appPath`, `launchURL`, and `drive` ignored).
- Calibration (speed, the Y direction) and per-model choices (`device`, absent sources) are not blockers. They are listed above.
- The script keeps a check for row fields the library does not use today (`turbo`, `deadzone`, `with`, and the others), so a later library commit that adds one is counted as a blocker, not skipped.

## Result

Command, run from a clone at the pinned commit (`git -C <clone> rev-parse HEAD` prints `958bdd97ceecb182004b3d7d8521761b5a7e7756`):

```sh
python3 -I docs/development/inputconfig-presets-count.py <clone>/InputConfig/Resources/ExamplePresets.swift
```

Output:

```text
presets read: 456 | distinct ids: 456
categories: {'app': 125, 'game': 294, 'workflow': 37}
rows read: 8513 | rows with no blocker: 8062
Presets that map without loss (all rules): 117 of 456
Presets whose bindings alone map without loss (preset settings ignored): 218 of 456
Blocking feature -> presets blocked (sole blocker in brackets):
    217 [ 45]  output: modifier key alone (OJD keyboard destination needs a key)
    164 [  2]  setting: confine cursor
    136 [ 84]  setting: launch app on activation (appPath)
     58 [  3]  setting: launch URL on activation (launchURL)
     38 [ 13]  output: wheel step (one notch per press)
      1 [  1]  output: system function dct (OJD systemKey/systemAction lacks it)
      1 [  0]  setting: one-stick driving (drive)
Blocking feature -> rows blocked:
   380  output: modifier key alone (OJD keyboard destination needs a key)
    70  output: wheel step (one notch per press)
     1  output: system function dct (OJD systemKey/systemAction lacks it)
rows with a mou/whe speed: {'mou': 1456, 'whe': 284}
presets with at least one mou output: 360
presets with at least one whe output: 130
presets with repeatCount rows: 6
presets with hold/double/toggle rows: 2
presets with btn 13 or a needs row: 1
presets with subtitle, tips, or notes (text OJD has no field for): 456
```

Reading the totals:

- All 456 presets are accounted for: 117 map without loss, 339 have at least one blocker.
- Of 8513 rows, 8062 (94.7%) map; 451 do not (380 modifier-only, 70 wheel step, 1 dictation).
- If the preset-level settings are left out (the importer drops the cursor guard and the app launch), 218 map. The 101 presets between 117 and 218 are blocked only by `confineCursor`, `appPath`, `launchURL`, or `drive`.
- The row blockers are two features. Modifier-only output blocks 217 presets and wheel step blocks 38. Support for a modifier-only key destination in OJD would raise the bindings-only total the most; the script can be rerun with that rule changed.
- `appPath` is the largest sole blocker (84). Its scope part is solvable on the user's Mac by reading the bundle identifier from the named app; the launch on activation is not.

## What the MIT notice requires

The license text of `LICENSE` at `958bdd97`, quoted in full:

```text
MIT License

Copyright (c) 2026 Ryleigh Newman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

What follows is a reading of that text, not legal advice.

- The one condition is the sentence "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software." The notice is the line `Copyright (c) 2026 Ryleigh Newman` plus the permission text and the warranty disclaimer.
- An importer that bundles the preset files, or ships profiles converted from them, copies or derives from the Software. Inferred: it must carry the notice with them. The place the repository already uses is `THIRD_PARTY_NOTICES.md`, which holds an MIT notice per third party; a ship of converted profiles also needs the notice where the profiles are, for example in the data folder or the importer's About text, so that a copy of the profiles alone still carries it.
- Observed: MIT permits sublicensing. OJD's own MPL-2.0 terms apply to OJD's files, but the MIT notice and the warranty disclaimer stay with the portions taken from InputConfig. Inferred: the converted profiles stay under the MIT terms; the MPL-2.0 license cannot remove them.
- An importer that reads preset files the user exports from InputConfig, and ships none of its data, copies nothing and needs no notice. Observed: the library is compiled into the InputConfig app as a Swift string; no export file of it exists in the repository. Inferred: only a bundled conversion is practical, so the notice applies.
- The MIT license covers the code and data of the repository. It does not give rights to the names of the games and apps in the presets or to their trademarks. Not checked beyond the license text.
- OJD today copies no code and no preset file from InputConfig, so it adds no notice. A bundled importer reverses that, and `THIRD_PARTY_NOTICES.md` would change in the same commit.

## Verdict

- Inferred: a mechanical import that loses nothing covers 117 of 456 presets (26%). The preset-level settings cost most of the rest.
- Inferred: two OJD changes would raise the count most: a keyboard destination for a modifier key alone (blocks 217 presets), and a profile-level app launch or a way to drop it (blocks 136 with `appPath`). Neither change is made here.
- Not measured: the 46 built-in presets, the calibration of `mou` and `whe` speeds, the Y direction convention, and the `hold` and `double` timing.
