## ADDED Requirements

### Requirement: Noncommercial License File

The repository SHALL hold the PolyForm Noncommercial License 1.0.0, verbatim, in `LICENSE`, followed by a `Required Notice:` line that names the copyright holder.

#### Scenario: License Text Matches the Published Text

- **WHEN** the license check compares `LICENSE` without its `Required Notice:` line against the pinned PolyForm Noncommercial 1.0.0 text
- **THEN** the two are identical
- **AND** the check fails and names the first differing line when they are not

### Requirement: Earlier Releases Keep MIT

Releases up to and including 0.6.0-alpha.1 SHALL stay under the MIT License, and the README SHALL say so.

#### Scenario: README Names Both Licenses

- **WHEN** a reader opens the README's License section
- **THEN** it names PolyForm Noncommercial 1.0.0 for releases from 0.6.0-alpha.2 on, MIT for releases up to 0.6.0-alpha.1, and `COMMERCIAL.md`

### Requirement: Commercial License Path

The repository SHALL hold `COMMERCIAL.md`. It states that commercial use needs a separate written license from the maintainer, names the contact for one, and states that a sponsorship alone grants no commercial license.

#### Scenario: Commercial User Finds the Contact

- **WHEN** a reader follows the link to `COMMERCIAL.md` from the README
- **THEN** the file names the contact for a commercial license

### Requirement: Contributor License Agreement

A pull request SHALL pass the CLA check only when its author has signed `CLA.md` or is on the check's allow list. The failure message SHALL tell the author how to sign.

#### Scenario: Unsigned Author

- **WHEN** an author who has not signed opens a pull request
- **THEN** the CLA check fails
- **AND** its comment quotes the sentence to post to sign

#### Scenario: Signed Author

- **WHEN** an author who has signed opens a pull request
- **THEN** the CLA check passes

### Requirement: Third-Party Code Sources

Code included in OpenJoystickDriver SHALL come only from sources under MIT, BSD, zlib, CC0 or Apache-2.0, each with its notice in `THIRD_PARTY_NOTICES.md`. A file under `Sources`, `Tests`, `Tools`, `Resources` or `Scripts` SHALL NOT carry a license header or SPDX identifier of the GPL family.

#### Scenario: GPL Header Is Rejected

- **WHEN** a Swift file under `Sources` contains `SPDX-License-Identifier: GPL-2.0-or-later`
- **THEN** `just check` fails and names the file and the line

#### Scenario: Documentation May Cite GPL Sources

- **WHEN** a file under `docs/` names a GPL source as a fact reference
- **THEN** the license-header check does not report it
