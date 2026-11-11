## ADDED Requirements

### Requirement: One Term Names One Concept

`wiki/Glossary.md` SHALL define each term the app, the command line's human output, and the wiki show to a user, with one term for each concept and the list of words that term replaces. The English strings and the wiki MUST use only the glossary's term for a concept.

#### Scenario: Replaced word in a string

- **WHEN** an English string holds a word the glossary lists as replaced
- **THEN** the repository check fails and names the string's key and the word

#### Scenario: Term in the wiki

- **WHEN** a wiki page uses a term of the glossary for the first time
- **THEN** the term links to its glossary entry

### Requirement: Profile Means a Remapping Profile

The word "profile" SHALL name only a remapping profile in every string and wiki page.

#### Scenario: Virtual gamepad choice

- **WHEN** the user reads the control that chooses the kind of virtual gamepad
- **THEN** its title and its options hold no "profile" and no "persona"

### Requirement: A Virtual Gamepad Kind Is Named by What Reads It

The app SHALL name each kind of virtual gamepad by the apps that read it, and MUST NOT show its raw identifier in Simple.

#### Scenario: Options of the control

- **WHEN** the user opens the control that chooses the kind
- **THEN** each option names the games or apps it is for, and no option shows `SDLCompatible`, `GameControllerCompatible`, or `Generic` as its title

### Requirement: Who Serves a Controller Reads the Same Everywhere

The window, the menu bar item, and the wiki SHALL use the same two phrases for a controller macOS serves and a controller OJD serves, and `wiki/Glossary.md` MUST tie each phrase to the value the command line prints.

#### Scenario: Pad left to macOS

- **WHEN** macOS serves a pad
- **THEN** the controller detail, the menu bar item, and the wiki use one phrase for it
- **AND** the glossary entry for that phrase names the value `System` of `ojd controller show`

### Requirement: The Driver Extension Has One Name

Every string and wiki page SHALL call OJD's driver extension by one name.

#### Scenario: Banner and Settings

- **WHEN** the user reads the banner, the Access area, and the wiki page about Xbox controllers
- **THEN** each uses the same name for the extension

### Requirement: Connection and Mode Are Separate Terms

OJD SHALL use "connection" for the way a controller reaches the Mac (cable, receiver, Bluetooth) and "mode" for a state the controller's own switch or button combination selects.

#### Scenario: Controller with a mode switch

- **WHEN** the detail of a controller shows both facts
- **THEN** one row is titled with the term for the connection and another with the term for the mode

### Requirement: Every Language Carries the Terms

Each language OJD ships SHALL translate each glossary term one way, by the rules in `LOCALIZATION.md`.

#### Scenario: Term in two strings

- **WHEN** two strings of one language hold the same glossary term
- **THEN** both use the same translation
