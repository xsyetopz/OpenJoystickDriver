import Testing

@testable import OpenJoystickDriverCLI

/// `CLIRun.run` checks every `--json` document the tests print against these definitions.
struct CLIOutputSchemaTests {
  @Test
  func jsonLineWithoutEnvelopePrintsOneSortedLineWithoutAPIVersionOrKind() async throws {
    let capture = CLIOutputCapture()
    try await CLIOutput.$capture.withValue(capture) {
      try CLIOutput.jsonLineWithoutEnvelope(["type": "added", "object": "pad"])
    }
    #expect(capture.standardOutput == "{\"object\":\"pad\",\"type\":\"added\"}\n")
  }

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
  func outputKindsComeFromTheKindTable() {
    #expect(CLI.outputKind(of: ControllerShowCommand.self) == "Controller")
    #expect(CLI.outputKind(of: AccessWebEnableCommand.self) == "WebAccess")
    #expect(CLI.outputKind(of: StatusCommand.self) == "SystemStatus")
    #expect(CLI.outputKind(of: BindingClearCommand.self) == "Status")
    #expect(CLI.outputKind(of: ProfileCreateCommand.self) == "Profile")
  }

  @Test
  func outputThatBreaksItsDefinitionIsReported() throws {
    let envelope = #""apiVersion":"openjoystickdriver.io/v1beta1","kind":"LogLocation""#
    let logPath = ["log", "path"]
    #expect(try CLIOutputSchema.issues(in: #"{\#(envelope),"path":"/a"}"#, path: logPath).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{\#(envelope),"path":1}"#, path: logPath).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{\#(envelope)}"#, path: logPath).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{"path":"/a"}"#, path: logPath).isEmpty)
    #expect(
      try !CLIOutputSchema.issues(
        in: #"{"apiVersion":"openjoystickdriver.io/v1beta1","kind":"LogShow","path":"/a"}"#,
        path: logPath
      ).isEmpty
    )
    #expect(
      try !CLIOutputSchema.issues(in: #"{\#(envelope),"path":"/a","extra":true}"#, path: logPath)
        .isEmpty
    )
  }

  @Test
  func eachLineOfAStreamIsChecked() throws {
    let good =
      #"{"apiVersion":"openjoystickdriver.io/v1beta1","kind":"USBPacket","#
      + #""direction":"rx","hex":"01 02","length":2,"captureTime":"1970-01-01T00:00:01.500Z"}"#
    #expect(
      try CLIOutputSchema.issues(in: good + "\n" + good, path: ["controller", "capture"]).isEmpty
    )
    #expect(
      try !CLIOutputSchema.issues(in: good + "\n{}", path: ["controller", "capture"]).isEmpty
    )
  }
}
