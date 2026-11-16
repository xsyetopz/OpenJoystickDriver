## ADDED Requirements

### Requirement: A Description Is One Fragment

Each `description` in a schema file SHALL be one sentence fragment of at most 120 characters that ends with a period and says what the value is.

#### Scenario: Two sentences

- **WHEN** a description holds two sentences
- **THEN** the schema style test fails and names the schema file and the property path

#### Scenario: Fragment that states the value

- **WHEN** a description reads "The USB vendor identifier."
- **THEN** the schema style test accepts it

### Requirement: A Description Names No Implementation

A `description` SHALL NOT name a Swift type, a source file or path, a command, an error code, a validator, or what OJD does with the value at run time.

#### Scenario: Swift type in a description

- **WHEN** a description names a Swift type or a path under `Sources/`
- **THEN** the schema style test fails and names the property path

#### Scenario: Validator talk

- **WHEN** a description says what a schema cannot state or what a validator checks
- **THEN** the schema style test fails

### Requirement: A Limit Is a Keyword

A limit that JSON Schema can state SHALL be a schema keyword and MUST NOT be repeated in the description. A limit JSON Schema cannot state MUST be in the wiki reference and MUST have a case under `SchemaRejections/`.

#### Scenario: Range in prose

- **WHEN** a description states a numeric range for a property
- **THEN** the range is in `minimum` and `maximum` and the description does not repeat it

#### Scenario: Cross-field rule

- **WHEN** a rule spans two properties and no keyword can state it
- **THEN** the wiki reference states the rule and a rejection case with `"schema": false` covers it

### Requirement: Schemas Hold No Comments

A schema file SHALL hold no `$comment`.

#### Scenario: Comment in a schema

- **WHEN** a schema file holds a `$comment` key
- **THEN** the schema style test fails and names the file

### Requirement: Documents Hold No Prose-Only Properties

A schema SHALL define no property whose only content is text for a human reader. The crosswalk `notes` property and the protocol description `rationale` property MUST be absent from the schemas and from every bundled document.

#### Scenario: Stale crosswalk with notes

- **WHEN** a crosswalk document holds `notes`
- **THEN** the reader refuses it as an unknown property

#### Scenario: Migration drops the properties

- **WHEN** `ojd migrate` converts a `v1alpha2` document that holds `notes` or `rationale`
- **THEN** the converted document has neither

### Requirement: Report Text Fields Carry Findings Only

A text field in a command report SHALL exist only where a command writes a finding about the run into it.

#### Scenario: Field with no producer

- **WHEN** no command writes a value into a report text field
- **THEN** the field is absent from the report schema

### Requirement: Removed Facts Move to the Wiki

A fact removed from a description that still holds SHALL be stated in the wiki reference for that document kind.

#### Scenario: Runtime rule removed from a description

- **WHEN** a description lost a sentence about how OJD applies a tuning value
- **THEN** `wiki/Controller-Records.md` states that rule

### Requirement: A Test Enforces the Style

The repository check SHALL run a test that applies these rules to every schema file.

#### Scenario: Full check

- **WHEN** `just check-schemas` runs
- **THEN** the schema style test runs over all 16 schema files and passes
