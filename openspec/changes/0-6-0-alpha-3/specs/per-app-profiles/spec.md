## ADDED Requirements

### Requirement: The User Picks an App From a List

The profile creation sheet and the profile editor SHALL offer the running apps and the installed apps to choose from, each with its icon and name. The user MUST NOT need to type an app identifier.

#### Scenario: Running app

- **WHEN** the user opens the app chooser while a game runs
- **THEN** the chooser lists the game with its icon and name, and choosing it stores the game's bundle identifier in the profile

#### Scenario: App that is not listed

- **WHEN** the user chooses "Other..."
- **THEN** an open panel starts in the Applications folder and accepts an app

#### Scenario: App that was removed

- **WHEN** a profile names an app that is not installed
- **THEN** the editor shows the identifier and says that the app is not installed

### Requirement: A Profile Applies to Several Apps

A profile whose `applicationScope` has the type `Application` SHALL hold `appIDs`, a list of one or more bundle identifiers, and MUST be in force while any of them is the app in front. The property `appID` leaves the schema.

#### Scenario: Two apps

- **WHEN** a profile lists two apps and the second is in front
- **THEN** that profile is in force for its controller

#### Scenario: Document with the old property

- **WHEN** a reader opens a profile that holds `appID`
- **THEN** the reader refuses it as an unknown property

#### Scenario: Migration

- **WHEN** `ojd migrate` converts a `v1alpha2` profile with one `appID`
- **THEN** the converted profile holds `appIDs` with that one identifier

#### Scenario: Command line

- **WHEN** the user passes `--app` twice to a profile command that accepts it
- **THEN** the profile holds both identifiers

### Requirement: The Interface Shows the Profile in Force and Why

The menu bar item and the controller detail SHALL show the profile in force for each controller. When the app in front selected it, they MUST name that app.

#### Scenario: Profile selected by an app

- **WHEN** a profile for the app in front is in force
- **THEN** the controller's row in the menu shows the profile's name, and the controller detail names the app that selected it

#### Scenario: Other app comes to the front

- **WHEN** the user switches to an app with no profile of its own
- **THEN** both show the controller's general profile the next time they are drawn
