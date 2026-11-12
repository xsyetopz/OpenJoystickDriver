# Terminology survey

Input to task 14.1 of `openspec/changes/0-6-0-alpha-3`: which terms the app, the command line, and the wiki use for each concept of the table in design D22. It settles nothing. The maintainer settles the table first; `wiki/Glossary.md` and every string stay as they are until then.

## How the counts are made

One script produces every number below:

```sh
swift build --product OpenJoystickDriver
Scripts/Quality/terminology_survey.sh [WORKDIR]   # default WORKDIR .build/terminology
```

The script writes three tab-separated inputs to `WORKDIR` and then counts each term in each. Rerunning it prints this table again, byte for byte (two runs compared with `cmp`). Each `ojd ... --help` call takes about 9 s, so the 112 help pages take several minutes.

| Source | Input file | Built by | Counted lines |
| --- | --- | --- | --- |
| Strings | `strings.tsv` | `find Sources -path '*/en-US.lproj/*' \( -name '*.strings' -o -name '*.stringsdict' \)`; for `.strings`, the value of each `"key" = "value";` line, for `.stringsdict`, each `<string>` line (2619 lines) | one value |
| Help | `help.tsv` | `OJD_RUN_REPOSITORY_CLI=1 .build/debug/ojd [sub...] --help`, recursing through each `SUBCOMMANDS:` entry: 112 pages, 2137 lines | one help line |
| Wiki | `wiki.tsv` | every line of `wiki/*.md`, including `AGENTS.md`, `_Sidebar.md`, `_Footer.md`, code blocks and tables (5521 lines) | one line, plus the number of pages in parentheses |

Reading the numbers:

- Only one module holds an `en-US.lproj`: `OpenJoystickDriverKit`. Every GUI and CLI string lives there (`LOCALIZATION.md`).
- A count is the number of lines whose text matches the regex, case-insensitive. A line with two matches counts once. Keys are not searched, only values, help prose, and wiki text.
- Terms overlap. "profile" includes "remapping profile"; "driver (any)" includes "Xbox USB driver"; "persona" appears under concepts 2 and 3 because D22 lists it for both. A count is not a share of a concept.
- Help text for most commands is built from `cli.*` and `platform.macos.cli.*` values, so a help line often repeats a string.- `Strings` counts the `.stringsdict` plural values too, so a figure can exceed the one in D22, which counted `.strings` values only (for example "Xbox USB driver": 12 here, 7 in D22).
- The wiki figures include command examples, so `SDLCompatible` and `GameControllerCompatible` count the identifiers, not a phrase.
- Example locations are the first two matching lines of each source: `Localizable.strings:N` or `Localizable.stringsdict:N` in `Sources/OpenJoystickDriverKit/Resources/en-US.lproj/`, the help page's command, and `Page.md:N` in `wiki/`. `-` marks no match.
- The `Regex` column is the exact Perl pattern; `\b` is a word boundary.

To count one term by hand, after the script ran (replace the regex):

```sh
perl -ne 'chomp; my ($l,$t)=split /\t/,$_,2; print "$l\n" if $t =~ /\bpersonas?\b/i' .build/terminology/strings.tsv | wc -l
```

## Counts

| Concept | Term | Regex | Strings | Help lines | Wiki lines (pages) | Strings example | Help example | Wiki example |
| --- | --- | --- | ---: | ---: | ---: | --- | --- | --- |
| 1 Profile | profile | `\bprofiles?\b` | 231 | 151 | 473 (28) | Localizable.strings:70, Localizable.strings:76 | ojd, ojd | Automating-OpenJoystickDriver.md:3, Automating-OpenJoystickDriver.md:29 |
| 1 Profile | remapping profile | `remapping profiles?` | 10 | 6 | 15 (10) | Localizable.strings:1569, Localizable.strings:3127 | ojd, ojd profile | Automating-OpenJoystickDriver.md:342, Automating-OpenJoystickDriver.md:343 |
| 1 Profile | mapping | `\bmappings?\b` | 14 | 9 | 28 (7) | Localizable.strings:520, Localizable.strings:522 | ojd profile set, ojd virtual | Command-Reference.md:38, Command-Reference.md:88 |
| 1 Profile | preset | `\bpresets?\b` | 0 | 0 | 0 (0) | - | - | - |
| 2 Virtual gamepad | virtual gamepad | `virtual gamepads?` | 46 | 22 | 58 (13) | Localizable.strings:190, Localizable.strings:280 | ojd, ojd controller | Automating-OpenJoystickDriver.md:3, Automating-OpenJoystickDriver.md:52 |
| 2 Virtual gamepad | virtual device | `virtual devices?` | 6 | 1 | 12 (6) | Localizable.strings:334, Localizable.strings:2959 | ojd migrate | Building-from-Source.md:26, Building-from-Source.md:71 |
| 2 Virtual gamepad | virtual controller | `virtual controllers?` | 2 | 0 | 46 (17) | Localizable.strings:2359, Localizable.strings:4914 | - | Automating-OpenJoystickDriver.md:310, Automating-OpenJoystickDriver.md:312 |
| 2 Virtual gamepad | virtual HID | `virtual HID` | 7 | 0 | 5 (3) | Localizable.strings:300, Localizable.strings:308 | - | Playing-Games.md:47, Troubleshooting.md:102 |
| 2 Virtual gamepad | persona | `\bpersonas?\b` | 12 | 0 | 15 (7) | Localizable.strings:2663, Localizable.strings:2987 | - | Automating-OpenJoystickDriver.md:31, Automating-OpenJoystickDriver.md:214 |
| 2 Virtual gamepad | virtual joystick | `virtual joysticks?` | 0 | 0 | 0 (0) | - | - | - |
| 3 Virtual gamepad kind | kind | `\bkinds?\b` | 12 | 0 | 68 (11) | Localizable.strings:3467, Localizable.strings:3469 | - | Automating-OpenJoystickDriver.md:29, Automating-OpenJoystickDriver.md:49 |
| 3 Virtual gamepad kind | persona | `\bpersonas?\b` | 12 | 0 | 15 (7) | Localizable.strings:2663, Localizable.strings:2987 | - | Automating-OpenJoystickDriver.md:31, Automating-OpenJoystickDriver.md:214 |
| 3 Virtual gamepad kind | SDLCompatible | `SDLCompatible` | 0 | 0 | 27 (9) | - | - | Automating-OpenJoystickDriver.md:214, Command-Reference.md:239 |
| 3 Virtual gamepad kind | GameControllerCompatible | `GameControllerCompatible` | 0 | 0 | 12 (6) | - | - | Automating-OpenJoystickDriver.md:214, Command-Reference.md:239 |
| 3 Virtual gamepad kind | Generic (HID gamepad) | `\bGeneric\b` | 3 | 3 | 45 (13) | Localizable.strings:1008, Localizable.strings:1010 | ojd virtual set, ojd virtual feed | Automating-OpenJoystickDriver.md:214, Automating-OpenJoystickDriver.md:215 |
| 3 Virtual gamepad kind | SDL-compatible (spaced) | `SDL[- ]compatible` | 0 | 3 | 6 (2) | - | ojd virtual set, ojd virtual feed | Automating-OpenJoystickDriver.md:31, Automating-OpenJoystickDriver.md:280 |
| 3 Virtual gamepad kind | For Steam and SDL games | `for steam and sdl` | 0 | 0 | 0 (0) | - | - | - |
| 3 Virtual gamepad kind | For Apple Game Controller games | `for apple game controller` | 0 | 0 | 0 (0) | - | - | - |
| 3 Virtual gamepad kind | backend | `\bbackends?\b` | 0 | 2 | 5 (2) | - | ojd virtual launch, ojd virtual launch | Command-Reference.md:50, Command-Reference.md:236 |
| 4 Who reads the controller | Served by | `served by` | 5 | 0 | 2 (2) | Localizable.strings:268, Localizable.strings:1352 | - | Controller-Records.md:82, Using-the-App.md:143 |
| 4 Who reads the controller | Handled by | `handled by` | 0 | 0 | 0 (0) | - | - | - |
| 4 Who reads the controller | Left to macOS | `left to macos` | 1 | 0 | 2 (1) | Localizable.strings:2007 | - | Playing-Games.md:38, Playing-Games.md:89 |
| 4 Who reads the controller | macOS (native) | `macos \(native\)` | 2 | 0 | 1 (1) | Localizable.strings:270, Localizable.strings:2695 | - | Using-the-App.md:145 |
| 4 Who reads the controller | OpenJoystickDriver (virtual) | `openjoystickdriver \(virtual\)` | 1 | 0 | 1 (1) | Localizable.strings:272 | - | Using-the-App.md:145 |
| 4 Who reads the controller | native | `\bnative(ly)?\b` | 8 | 2 | 13 (6) | Localizable.strings:266, Localizable.strings:270 | ojd controller claim, ojd controller release | Command-Reference.md:88, Command-Reference.md:94 |
| 4 Who reads the controller | owner / ownership | `\bowner(ship)?\b` | 4 | 2 | 2 (2) | Localizable.strings:2633, Localizable.strings:2655 | ojd controller, ojd controller show | Command-Reference.md:88, Remapping-Profiles.md:67 |
| 5 DriverKit extension | Xbox USB driver | `xbox usb driver` | 12 | 0 | 22 (11) | Localizable.strings:1328, Localizable.strings:1332 | - | Building-from-Source.md:89, Connecting-Controllers.md:3 |
| 5 DriverKit extension | Driver Extension | `driver extensions?` | 7 | 0 | 28 (14) | Localizable.strings:282, Localizable.strings:1356 | - | Building-from-Source.md:17, Building-from-Source.md:58 |
| 5 DriverKit extension | system extension | `system extensions?` | 4 | 1 | 11 (8) | Localizable.strings:1000, Localizable.strings:1002 | ojd | Building-from-Source.md:58, Building-from-Source.md:70 |
| 5 DriverKit extension | transport extension | `transport[- ]extensions?` | 4 | 6 | 12 (3) | Localizable.strings:2173, Localizable.strings:2183 | ojd, ojd transport-extension | Command-Reference.md:18, Command-Reference.md:94 |
| 5 DriverKit extension | DriverKit | `driverkit` | 1 | 2 | 8 (5) | Localizable.strings:2263 | ojd, ojd transport-extension | Automating-OpenJoystickDriver.md:9, Building-from-Source.md:17 |
| 5 DriverKit extension | dext | `\bdexts?\b` | 1 | 0 | 1 (1) | Localizable.strings:2273 | - | Building-from-Source.md:73 |
| 5 DriverKit extension | USB driver (any) | `usb drivers?` | 12 | 0 | 23 (12) | Localizable.strings:1328, Localizable.strings:1332 | - | Building-from-Source.md:89, Command-Reference.md:265 |
| 5 DriverKit extension | driver (any) | `\bdrivers?\b` | 31 | 3 | 81 (20) | Localizable.strings:282, Localizable.strings:874 | ojd, ojd config | Automating-OpenJoystickDriver.md:212, Automating-OpenJoystickDriver.md:330 |
| 6 How a controller reaches the Mac | connection | `\bconnections?\b` | 18 | 7 | 44 (11) | Localizable.strings:1066, Localizable.strings:1380 | ojd controller disconnect, ojd record test | Automating-OpenJoystickDriver.md:9, Automating-OpenJoystickDriver.md:75 |
| 6 How a controller reaches the Mac | transport | `\btransports?\b` | 12 | 6 | 31 (9) | Localizable.strings:2173, Localizable.strings:2183 | ojd, ojd transport-extension | Building-from-Source.md:17, Building-from-Source.md:18 |
| 6 How a controller reaches the Mac | Wireless Link | `wireless link` | 2 | 0 | 2 (1) | Localizable.strings:4459, Localizable.strings:4571 | - | Using-the-App.md:62, Using-the-App.md:109 |
| 6 How a controller reaches the Mac | wireless | `\bwireless\b` | 4 | 0 | 14 (7) | Localizable.strings:214, Localizable.strings:1896 | - | Connecting-Controllers.md:24, Connecting-Controllers.md:32 |
| 6 How a controller reaches the Mac | receiver / dongle | `\b(receivers?\|dongles?)\b` | 4 | 0 | 33 (11) | Localizable.strings:210, Localizable.strings:214 | - | Command-Reference.md:88, Connecting-Controllers.md:3 |
| 6 How a controller reaches the Mac | cable / wired | `\b(cables?\|wired)\b` | 4 | 0 | 13 (4) | Localizable.strings:188, Localizable.strings:234 | - | Connecting-Controllers.md:20, Connecting-Controllers.md:24 |
| 6 How a controller reaches the Mac | bus | `\bbus\b` | 0 | 0 | 1 (1) | - | - | Controller-Records.md:590 |
| 7 What the controller's own switch selects | mode | `\bmodes?\b` | 21 | 0 | 94 (14) | Localizable.strings:202, Localizable.strings:204 | - | Bindings-and-Actions.md:223, Bindings-and-Actions.md:286 |
| 7 What the controller's own switch selects | protocol | `\bprotocols?\b` | 29 | 17 | 66 (14) | Localizable.strings:166, Localizable.strings:170 | ojd, ojd protocol | Automating-OpenJoystickDriver.md:31, Command-Line.md:95 |
| 7 What the controller's own switch selects | switch | `\bswitch(es)?\b` | 7 | 0 | 42 (13) | Localizable.strings:740, Localizable.strings:1012 | - | Automating-OpenJoystickDriver.md:166, Bindings-and-Actions.md:9 |

## Concepts with more than one term in use

A term counts as in use when a source has a nonzero count that names the concept (not the generic words "driver", "native", "kind", "switch", "owner").

- 1 Profile: one term ("profile"; "remapping profile" is the same word with a modifier). "mapping" (14 strings) and "preset" (0) were searched as rivals; whether "mapping" names the same concept is the maintainer's reading.
- 2 Virtual gamepad: five terms in strings: "virtual gamepad" (46), "virtual HID" (7), "virtual device" (6), "persona" (12), "virtual controller" (2). The wiki adds "virtual controller" (46 lines, 17 pages); the help uses "virtual gamepad" (22) and one "virtual device".
- 3 Virtual gamepad kind: "persona" (12 strings, 15 wiki lines), the identifiers `SDLCompatible` and `GameControllerCompatible` (wiki only, 27 and 12 lines), "SDL-compatible" (help 3, wiki 6), "Generic". The proposed option labels ("For Steam and SDL games", "For Apple Game Controller games") occur nowhere yet.
- 4 Who reads the controller: "Served by" (5 strings, 2 wiki lines), "Left to macOS" (1), "macOS (native)" (2), "OpenJoystickDriver (virtual)" (1). "Handled by" occurs nowhere. The help does not contain "Served by".
- 5 DriverKit extension: "Xbox USB driver" (12 strings, 22 wiki lines), "Driver Extension" (7, 28), "system extension" (4, 11; help 1), "transport extension" (4 strings, 6 help lines, 12 wiki lines; also a command name), "DriverKit" (1 string, 2 help, 8 wiki), "dext" (1, 1).
- 6 How a controller reaches the Mac: "connection" (18 strings, 7 help, 44 wiki), "transport" (12, 6, 31), "Wireless Link" (2, 0, 2).
- 7 What the controller's own switch selects: "mode" (21 strings, 94 wiki lines) and "protocol" (29 strings, 17 help lines, 66 wiki lines). Whether "protocol" here means the controller's mode or the wire protocol needs a read of the lines; the counts do not tell.

Counted on 2026-11-12 at commit `791b9d34a`.
