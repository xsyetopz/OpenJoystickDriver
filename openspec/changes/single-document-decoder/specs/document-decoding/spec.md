# Spec Delta

## Purpose

How OJD reads Controller, ControllerPatch and VirtualDevice files, so that a file a user writes gets the same verdict from every command that reads it.

## ADDED Requirements

### Requirement: REQ-1 One verdict for a controller file

Every command and loader that reads a Controller or ControllerPatch file, including `ojd diagnose record`, MUST refuse with E5007 `invalidControllerRecord` text that is not plain UTF-8, text that is not one JSON object, and an object that names a member twice.

#### Scenario: Record with a member named twice is probed

- **WHEN** the user runs `ojd diagnose record` on a Controller file that names `productID` twice
- **THEN** the command fails with E5007
- **AND** `OJDRepositoryTool validate controllers` refuses the same file with E5007

#### Scenario: Record with a byte order mark is installed

- **WHEN** the user runs `ojd record install` on a Controller file that starts with a UTF-8 byte order mark
- **THEN** the command fails with E5007 and writes no file

### Requirement: REQ-2 User records and patches without source changes

A user MUST be able to add a controller and change a bundled controller without changing OJD's source or bundle. To add a controller, they place a Controller file named `vvvv-pppp.json` in `Controllers/` or in a mod package. To change a bundled controller, they place a ControllerPatch file there. A Controller file for a model the bundle already holds MUST be refused with E5007, and the error MUST say to use a patch.

#### Scenario: User adds a controller

- **WHEN** the user places a valid Controller file for a model the bundle lacks in `Controllers/`
- **THEN** OJD serves that model from the file

#### Scenario: User patches a bundled controller

- **WHEN** the user places a ControllerPatch file that changes a bundled model's `name`
- **THEN** OJD serves the bundled record with the patched `name`

#### Scenario: User copies a bundled record

- **WHEN** the user places a Controller file for a bundled model in `Controllers/`
- **THEN** the file is refused with E5007 and a message that says to use a patch

### Requirement: REQ-3 Strict virtual-device files

A VirtualDevice file MUST be refused with E5001 `unsupportedAPIVersion` when its `apiVersion` or `kind` is not the supported one. It MUST be refused with E5007 when it is not one JSON object, holds a member the schema does not name, or holds a value of the wrong type.

#### Scenario: Unknown member in a virtual-device file

- **WHEN** a file in `VirtualDevices/` holds a member `colour`
- **THEN** the file is refused with E5007

#### Scenario: Wrong kind in a virtual-device file

- **WHEN** a file in `VirtualDevices/` has `kind: Controller`
- **THEN** the file is refused with E5001
