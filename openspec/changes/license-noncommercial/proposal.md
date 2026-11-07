## Why

OpenJoystickDriver is MIT, so a company can ship it, or sell a product built on it, without paying for the controllers and Macs that test it. The maintainer decided on 2026-10-25 that noncommercial use stays free for anybody, and that commercial users buy a license. The README asks commercial users to sponsor the project, which pays for hardware verification.

## What Changes

- **BREAKING (license):** `LICENSE` holds the PolyForm Noncommercial License 1.0.0, verbatim from polyformproject.org, with a `Required Notice:` line for the maintainer. This applies from 0.6.0-alpha.2. Releases up to and including 0.6.0-alpha.1 stay MIT, and their tags are not changed.
- `COMMERCIAL.md` says that commercial use needs a separate written license from the maintainer, how to ask for one, and that sponsorship is welcome but does not grant one.
- `CLA.md` holds a contributor license agreement. It grants the maintainer the right to license each contribution under both the noncommercial and the commercial terms. A pull request from a contributor who has not signed fails a CI check.
- `CONTRIBUTING.md` gains a License section: the CLA, and the source rule for third-party code.
- `README.md`: the License section names PolyForm Noncommercial 1.0.0 and `COMMERCIAL.md`, and states that releases up to 0.6.0-alpha.1 are MIT. The sponsorship paragraph asks commercial users to sponsor. The badge text no longer reads "MIT".
- `THIRD_PARTY_NOTICES.md` keeps every MIT, BSD, zlib, CC0 and Apache notice of code that OJD includes. It gains an entry for the MIT contributions of outside contributors who do not sign the CLA (design D4).
- Source rule: OJD includes code only from MIT, BSD, zlib, CC0 or Apache-2.0 sources, each with its notice in `THIRD_PARTY_NOTICES.md` in the same commit. GPL, LGPL, AGPL and unlicensed sources give facts only, and OJD's code for those facts is written independently. A check script rejects a source file that carries a GPL license header.
- `CHANGELOG.md` `[Unreleased]` gets a `### Changed` entry for the license.

## Capabilities

### New Capabilities

- `project-licensing`: which license covers each release, how commercial use is licensed, what contributors agree to, and which third-party sources code may come from.

### Modified Capabilities

None.

## Impact

- Files: `LICENSE`, `COMMERCIAL.md`, `CLA.md`, `CONTRIBUTING.md`, `README.md`, `THIRD_PARTY_NOTICES.md`, `CHANGELOG.md`, `.github/workflows/` (the CLA check), `.github/pull_request_template.md`, `Scripts/Quality/` (the license-header check) and `justfile`.
- The app: the About panel's copyright line (`NSHumanReadableCopyright`, which no Info.plist sets yet) names the license.
- Contributors: five outside contributors have one commit each under MIT (design D4).
- The other alpha.2 changes (`wii-remote`, `sdl-gamecontrollerdb-import`, `remapper-actions`, `xbox360-xusb-fixes`, `steam-controller-fixes`, `switch2-protocol-check`, `8bitdo-coverage`, `flydigi-vendor-protocol`) already follow the source rule.
- Legal review: none. The project is community-run, and the maintainer decides `COMMERCIAL.md`, `CLA.md` and design D3, D4 and D5 (task 1.1).

## Out of Scope

- The commercial license contract itself: the maintainer writes it. `COMMERCIAL.md` only says how to ask for one.
- Licensing of user-made mods: a mod is the author's own data, and this change does not license it.
- Changing the license of published releases.
