import Testing

@testable import OpenJoystickDriverCLI

/// `CLIRun.run` checks every `--json` document the tests print against these definitions.
struct CLIOutputSchemaTests {
  @Test
  func everyCommandHasOneOutputDefinition() {
    let names = CLICommandTree.leafPaths.filter { !CLIOutputSchema.exempt.contains($0) }
      .map(CLIOutputSchema.definitionName(for:))
    let definitions = Set(CLIOutputSchema.definitions.keys)
    #expect(Set(names).count == names.count)
    let missing = Set(names).subtracting(definitions)
    let unused = definitions.subtracting(names).filter { !$0.hasPrefix("shared") }
    #expect(missing.isEmpty, "commands without a definition: \(missing.sorted())")
    #expect(unused.isEmpty, "definitions of no command: \(unused.sorted())")
  }

  @Test
  func exemptCommandsExist() {
    #expect(CLIOutputSchema.exempt.isSubset(of: Set(CLICommandTree.leafPaths)))
  }

  @Test
  func definitionNamesAreLowerCamelCasePaths() {
    #expect(CLIOutputSchema.definitionName(for: ["controller", "show"]) == "controllerShow")
    #expect(CLIOutputSchema.definitionName(for: ["log", "path"]) == "logPath")
    #expect(CLIOutputSchema.definitionName(for: ["status"]) == "status")
  }

  @Test
  func outputThatBreaksItsDefinitionIsReported() throws {
    #expect(try CLIOutputSchema.issues(in: #"{"path":"/tmp/a"}"#, path: ["log", "path"]).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{"path":1}"#, path: ["log", "path"]).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{}"#, path: ["log", "path"]).isEmpty)
    #expect(
      try !CLIOutputSchema.issues(in: #"{"path":"/a","extra":true}"#, path: ["log", "path"])
        .isEmpty
    )
  }

  @Test
  func eachLineOfAStreamIsChecked() throws {
    let good = #"{"direction":"rx","hex":"01 02","length":2,"timestamp":1.5}"#
    #expect(
      try CLIOutputSchema.issues(in: good + "\n" + good, path: ["controller", "capture"]).isEmpty
    )
    #expect(
      try !CLIOutputSchema.issues(in: good + "\n{}", path: ["controller", "capture"]).isEmpty
    )
  }
}
