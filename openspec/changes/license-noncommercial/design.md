## Context

- `LICENSE` is MIT, "Copyright (c) 2026 Krystian J.". The README's License section reads "[MIT](LICENSE) © 2026 Krystian J." (`README.md:116`), and its badge reads the license from GitHub (`README.md:14`).
- `.github/FUNDING.yml` names GitHub Sponsors (`github: xsyetopz`). `README.md:112` says sponsorship pays for the controllers and Macs that tests run on.
- `THIRD_PARTY_NOTICES.md` holds GamepadMotionHelpers (MIT, adapted in `MotionProjection.swift`) and LiveKitWebRTC (MIT, plus WebRTC's BSD-3-Clause), linked only by `Tools/WebRTCBridge/`.
- Outside contributors, from `git log` (one commit each, all under MIT):
  - Danilo Wanner, `3c6736d29`: 8 files, +101 −13.
  - Elijah Davis, `1588387c1`: 7 files, +79 −39.
  - Dave Snijder, `2f9f0d016`: 2 files, +7 −1.
  - Michael Melaku, `e93cc33d4`: 1 file, +1 −1.
  - Bastien Didier, named in `26635634e`.
- `Tests/OpenJoystickDriverKitTests/Protocol/Drivers/Generic/RecordedHIDDescriptors.swift:3` holds four HID report descriptors "recorded by xpadneo (`docs/descriptors`, GPL-3.0)". `ZRzBrakeLeftLayoutTests` and `XboxBluetoothDescriptorLayoutTests` use them. This is the only GPL text under `Sources`, `Tests`, `Tools`, `Resources` and `Scripts` outside localization files.
- `iborrowcheckbtw`, `Krystian J.` and `xsyetopz` are the maintainer. AI tools appear only as co-author trailers.
- The catalog is generated from SDL's `controller_list.h` (zlib) and from the ID tables of Linux `xpad.c` (GPL-2.0-or-later), which `ControllerSources.lock.json` pins (`docs/development/compatibility-sources.md:11`).
- The maintainer's decision (2026-10-25): PolyForm Noncommercial 1.0.0 for the app, a separate commercial license, a CLA for new contributions, and a sponsorship request in the README. Code may come only from MIT, BSD, zlib, CC0 or Apache sources, and GPL, AGPL or unlicensed repositories give facts only. Releases up to 0.6.0-alpha.1 stay MIT.

## Goals / Non-goals

**Goals:** one license file that states the terms of every build from 0.6.0-alpha.2 on. A written way to buy commercial rights. Contributions that the maintainer can license both ways. A check that keeps GPL code out.

**Non-Goals:** the commercial contract, a license key or any check inside the app, and relicensing of published releases.

## Decisions

### D1. PolyForm Noncommercial 1.0.0, Verbatim

`LICENSE` is the text from <https://polyformproject.org/licenses/noncommercial/1.0.0/>, fetched at implementation time and not retyped. Then comes the line `Required Notice: Copyright (c) 2026 Krystian J. (https://github.com/xsyetopz/OpenJoystickDriver)`. GitHub shows the license as "Other", so the README badge is a static badge reading "PolyForm Noncommercial".

Alternatives:

- BSL 1.1 converts to open source after a date, which the maintainer did not ask for.
- CC BY-NC is not written for software.
- The Commons Clause on top of MIT is ambiguous about "selling".

### D2. Commercial Use through `COMMERCIAL.md`

The maintainer is one person. `COMMERCIAL.md` says, in plain words:

- That noncommercial use, forks and shared changes are free with no need to ask, as long as the license and its `Required Notice:` line travel with each copy.
- What counts as commercial: PolyForm's own definitions decide, and the file only points to them.
- That a commercial license is a separate written agreement with the maintainer, asked for through the contact named there. The maintainer chooses the contact (task 1.2).
- That GitHub Sponsors is welcome from commercial users, but a sponsorship alone grants no commercial license.

### D3. CLA, Checked in CI

`CLA.md` grants the maintainer a perpetual, worldwide, royalty-free license to each contribution, with the right to sublicense it under any terms, the commercial license included. It also has the contributor confirm that they have the right to submit the contribution. The contributor keeps their copyright. The CLA text is drafted from the Apache Individual CLA, which may be reused, and the maintainer accepts it (task 1.1).

The check is the `contributor-assistant/github-action` workflow. It records each signature as a PR comment, in a file on a separate branch of this repository, so no outside service holds the list. It runs on `pull_request_target` with the least permissions it needs. Bots and the maintainer are on its allow list. A PR fails the check until its author signs, and the failure says what to do.

Alternative: the DCO confirms origin but grants no right to license commercially, so it does not fit.

### D4. the MIT Contributions of Outside Contributors

MIT lets anyone sublicense the code under other terms, as long as the MIT notice stays. Each of the five outside contributors is asked to sign the CLA for their earlier commit (task 4.1). For each one who does not sign, `THIRD_PARTY_NOTICES.md` names the commit and keeps the MIT text with that contributor's name. Their code stays in OJD under that notice. This is the project's reading (task 1.1).

### D5. Facts from GPL Sources

- The catalog generator reads vendor and product IDs and protocol family names from `xpad.c`. It copies no code.
- Drivers are written from protocol facts, never from GPL code.
- A generated ID table holds IDs and names, which are facts, so it ships under PolyForm (task 1.1).
- The four xpadneo descriptors in `RecordedHIDDescriptors.swift` are replaced with descriptors that OJD testers capture from their own controllers (task 4.4).

### D6. a Check against GPL Headers

`Scripts/Quality/check_license_headers.py` scans `Sources`, `Tests`, `Tools`, `Resources` and `Scripts` for an SPDX identifier or license text of the GPL family (`GPL`, `LGPL`, `AGPL`, "GNU General Public License"). It fails with the path and line of each hit. `just check` runs it. The script reads files only and re-implements no Swift logic. Documentation under `docs/` may name GPL sources, as `compatibility-sources.md` does, so `docs/` is not scanned.

### D7. Where the License Is Shown

- The README's License section.
- `LICENSE`.
- The app's About panel through `NSHumanReadableCopyright`: "© 2026 Krystian J. PolyForm Noncommercial 1.0.0." The line holds only a name, a license name and a version, so it is not localized.
- `ojd --version` prints the version only and stays as it is.

## Risks / Trade-Offs

- **Contributors leave.** A CLA is a barrier. The CI failure message and the CONTRIBUTING section state the reason in two sentences.
- **Packaging.** Homebrew core and some distributions refuse non-OSI licenses. OJD ships its own DMG, so no current channel is affected.
- **Legal uncertainty.** D4 and D5 are the project's readings, with no legal review (task 1.1).
- **Forks of 0.6.0-alpha.1 stay MIT.** This is accepted: those releases keep their license.

## Open Questions

1. The contact for commercial licenses: an email, or a GitHub Sponsors tier (task 1.2).
