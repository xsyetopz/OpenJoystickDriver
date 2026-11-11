## ADDED Requirements

### Requirement: A Build That Fixes a Reported Issue Is Public

A build the maintainer gives to testers SHALL be a pre-release on GitHub Releases with a signed, notarized disk image. The issue it answers MUST hold a link to that pre-release.

#### Scenario: Fix for a reported controller

- **WHEN** the maintainer has a build for a reporter to test
- **THEN** GitHub Releases holds a pre-release with that build's disk image
- **AND** the draft reply for the issue holds the link to it

#### Scenario: Reader of an issue

- **WHEN** a second user with the same controller reads the issue
- **THEN** the user can download the same build without asking for it

### Requirement: The Update Check Finds a Tester Build

OJD SHALL offer a tester build through its update check to a user who has "Include prerelease updates" on, and MUST order a tester build between the release before it and the release it leads to.

#### Scenario: Prerelease updates on

- **WHEN** "Include prerelease updates" is on and a tester build is later than the installed build
- **THEN** the update check offers it

#### Scenario: Release after a tester build

- **WHEN** the user runs a tester build of 0.6.0-alpha.3 and 0.6.0-alpha.3 is published
- **THEN** the update check offers 0.6.0-alpha.3

### Requirement: The Wiki Says How to Get a Tester Build

`wiki/Updating-and-Uninstalling.md` SHALL say where tester builds are published and which setting makes the update check find them.

#### Scenario: Reader who wants a fix early

- **WHEN** a reader follows the page
- **THEN** the reader reaches the pre-release list and the setting
