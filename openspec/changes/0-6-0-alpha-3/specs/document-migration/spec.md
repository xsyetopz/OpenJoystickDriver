## ADDED Requirements

### Requirement: One Run Reaches the Current Version

`ojd migrate` SHALL convert a `v1alpha1` or `v1alpha2` JSON document into a `v1alpha3` property list in one run.

#### Scenario: Stored alpha.1 access grants

- **WHEN** the user folder holds `AccessGrants.json` with `openjoystickdriver/v1alpha1` and the user runs `ojd migrate`
- **THEN** the folder holds `AccessGrants.plist` with `openjoystickdriver/v1alpha3`
- **AND** the Access area loads it

#### Scenario: Second run

- **WHEN** the user runs `ojd migrate` again
- **THEN** every file is reported `current` and no file changes

### Requirement: Every Store Is Scanned

`ojd migrate` SHALL scan every place OJD keeps user documents: the root files, `ActiveProfiles`, `Profiles/`, `Controllers/`, `VirtualDevices/`, `Personas/`, and `Packages/`.

#### Scenario: Stale persona

- **WHEN** `Personas/` holds a `v1alpha2` document
- **THEN** `ojd migrate` converts it

#### Scenario: Stale package

- **WHEN** an installed package holds `v1alpha2` documents
- **THEN** `ojd migrate` converts the manifest and each document in the package

### Requirement: A Folder Outside the Stores Can Be Migrated

`ojd migrate <folder>` SHALL convert the documents in the folder the user names, with the same steps and verdicts.

#### Scenario: Record from a pull request

- **WHEN** the user runs `ojd migrate` on a folder that holds one `v1alpha1` record as JSON
- **THEN** the folder holds that record as a `v1alpha3` property list

### Requirement: Every File Gets a Verdict

`ojd migrate` SHALL report each scanned file as `migrated`, `current`, `failed`, or `foreign`, and MUST give a reason for each `failed` file. With `--json` the same verdicts MUST appear in the output.

#### Scenario: File with no version

- **WHEN** a store holds a JSON file with no `apiVersion`
- **THEN** the run reports it `failed` with a reason and does not skip it

#### Scenario: File that is not an OJD document

- **WHEN** a store holds a file OJD does not own, such as `.DS_Store`
- **THEN** the run reports it `foreign` and leaves it

#### Scenario: Failed files set the exit status

- **WHEN** at least one file is `failed`
- **THEN** `ojd migrate` exits with a failure status after it has processed every other file

### Requirement: Unconvertible Documents Stay Unchanged

`ojd migrate` SHALL leave a document it cannot convert byte for byte as it was.

#### Scenario: Document from 0.5

- **WHEN** a store holds a 0.5 record that has `$schema` and no `apiVersion`
- **THEN** the run reports it `failed`, says which release wrote it, and does not change the file

### Requirement: The Original Is Kept

`ojd migrate` SHALL move the original of each converted file into `Migrated/` under its relative path before the store holds the converted file, and MUST NOT overwrite an earlier backup.

#### Scenario: Restore

- **WHEN** the user copies a file back from `Migrated/` and installs the release that wrote it
- **THEN** that release reads the file

#### Scenario: Backup name is taken

- **WHEN** `Migrated/` already holds a file with the same relative path
- **THEN** the run keeps both files

### Requirement: Dry Run Writes Nothing

`ojd migrate --dry-run` SHALL print the verdict each file would get and MUST NOT create, move, or change any file.

#### Scenario: Dry run on stale files

- **WHEN** the user runs `ojd migrate --dry-run` with stale files present
- **THEN** the output lists each file as it would end and the folder is unchanged

### Requirement: Migration Runs at Service Start

The service SHALL run the migration on the user stores before any reader opens them, and MUST log each verdict.

#### Scenario: First start after the update

- **WHEN** the user installs 0.6.0-alpha.3 over stored `v1alpha2` documents and starts OJD
- **THEN** every area of the app loads with no `E5001`
- **AND** the originals are in `Migrated/`

#### Scenario: A file fails at start

- **WHEN** one stored file cannot be converted at service start
- **THEN** the service starts, the other documents load, and the area that owns the file names it with the reason

### Requirement: Stale JSON in a Store Is Reported

OJD SHALL report a `.json` document that appears in a store after start as stale, and MUST NOT ignore it or load it.

#### Scenario: User drops in an alpha.2 record

- **WHEN** the user copies a `v1alpha2` JSON record into `Controllers/`
- **THEN** the Controllers area names the file as stale and offers Migrate

### Requirement: The App Offers Migration Wherever E5001 Shows

Every screen that reports `E5001` SHALL offer a Migrate action. A request the service refuses for a stale document MUST reach the app with the code `E5001`, not with the code of a general request failure. A screen that offers to delete the stale document MUST offer Migrate first.

#### Scenario: Access area with a stale grants file

- **WHEN** the service refuses an access request because the access grants file has an unsupported `apiVersion`
- **THEN** the Access area shows `E5001`, not `E2006`, and offers Migrate

#### Scenario: Profiles area

- **WHEN** a profile fails to load with `E5001`
- **THEN** the Profiles area says the profile is from an earlier version and offers Migrate before Delete

#### Scenario: Migrate succeeds

- **WHEN** the user clicks Migrate and the file converts
- **THEN** the screen reloads and shows the document
