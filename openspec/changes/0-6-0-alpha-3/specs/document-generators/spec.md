## ADDED Requirements

### Requirement: A Script Generates Documents

`ojd generate <script>` SHALL evaluate one JavaScript file with JavaScriptCore, call its `generate` function, and write each document the function returns as a property list. The function MUST return one document or a list of documents.

#### Scenario: One record

- **WHEN** a script's `generate` returns one record object and the user runs `ojd generate pad.js --output Controllers`
- **THEN** `Controllers` holds that record as a `.plist` file named by the store's naming rule

#### Scenario: Family of records

- **WHEN** `generate` returns a list of five records
- **THEN** the command writes five files

#### Scenario: No output folder

- **WHEN** the user runs `ojd generate pad.js` with no `--output`
- **THEN** the command prints the documents and writes no file

### Requirement: Generated Documents Pass the Same Checks

`ojd generate` SHALL check each returned document with the same decoder and rules as a hand-written file, and MUST write no file when any document fails.

#### Scenario: Invalid document

- **WHEN** one of three returned documents breaks a schema rule
- **THEN** the command names the document, the key path, and the rule, writes none of the three, and exits with a failure status

#### Scenario: Null in the result

- **WHEN** a returned document holds `null`
- **THEN** the command refuses it and names the key path

### Requirement: Number Types Survive Generation

`ojd generate` SHALL write an integer the script returns as an integer and a fractional number as a real.

#### Scenario: Hexadecimal literal

- **WHEN** a script returns `vendorID: 0x2DC8`
- **THEN** the written file holds `<integer>11720</integer>` for `vendorID`

### Requirement: A Script Has a Time Limit

`ojd generate` SHALL run the script in a helper process and MUST end it when it exceeds the time limit, which is 5 seconds unless the user sets `--timeout`.

#### Scenario: Endless loop

- **WHEN** a script never returns
- **THEN** the command ends the helper at the limit, reports a timeout, writes no file, and exits with a failure status

### Requirement: A Script Reaches Nothing Outside Itself

The script context SHALL offer no file, network, process, or timer API.

#### Scenario: Script asks for the network

- **WHEN** a script calls `fetch`
- **THEN** the script fails with a reference error and the command reports it with the line number

### Requirement: Script Errors Are Reported

`ojd generate` SHALL report a script's syntax error or thrown exception with its message and line number.

#### Scenario: TypeScript syntax

- **WHEN** the file holds a type annotation
- **THEN** the command reports the syntax error with its line and writes no file

#### Scenario: Missing function

- **WHEN** the file defines no `generate` function
- **THEN** the command says so and exits with a failure status

### Requirement: Generation Does Not Overwrite Edited Files

`ojd generate` SHALL NOT replace an existing file whose content differs from the generated document unless the user passes `--replace`.

#### Scenario: Edited output

- **WHEN** the output folder holds a file with the same name and different content
- **THEN** the command names the file, writes nothing, and exits with a failure status

#### Scenario: Unchanged output

- **WHEN** the output folder holds a file equal to the generated document
- **THEN** the command reports it as unchanged and succeeds

### Requirement: Only the Generate Command Runs Scripts

The service, the app, and package loading SHALL NOT evaluate a script. A package MUST be read as documents only.

#### Scenario: Script inside a package

- **WHEN** a package folder holds a `.js` file
- **THEN** OJD loads the package's documents and never evaluates the file

### Requirement: Scripting Is Documented

The wiki SHALL document the generator script interface with a complete example, and `wiki/Automating-OpenJoystickDriver.md` MUST show how to drive OJD from AppleScript, JavaScript for Automation, and Shortcuts.

#### Scenario: Example script

- **WHEN** a reader runs the wiki's example script through `ojd generate`
- **THEN** the command writes a document OJD loads

#### Scenario: AppleScript example

- **WHEN** a reader runs the wiki's AppleScript example
- **THEN** it returns the connected controllers
