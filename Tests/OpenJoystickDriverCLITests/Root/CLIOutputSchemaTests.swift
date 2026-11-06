import Testing

@testable import OpenJoystickDriverCLI

/// `CLIRun.run` checks every `--json` document the tests print against these definitions.
struct CLIOutputSchemaTests {
  @Test
  func jsonLineWithoutEnvelopePrintsOneSortedLineWithoutAPIVersionOrKind() throws {
    let capture = CLIOutputCapture()
    try CLIOutput.$capture.withValue(capture) {
      try CLIOutput.jsonLineWithoutEnvelope(["type": "added", "object": "pad"])
    }
    #expect(capture.standardOutput == "{\"object\":\"pad\",\"type\":\"added\"}\n")
  }

  @Test
  func plainRowsKeepEachFieldOnOneLine() {
    let capture = CLIOutputCapture()
    CLIOutput.$capture.withValue(capture) {
      CLIOutput.plain([
        ["a\tb", "line one\nline two", "x\r\ny\rz", "u\u{85}v\u{2028}w\u{2029}x\u{0B}y\u{0C}z"],
        ["next"],
      ])
    }
    #expect(capture.standardOutput == "a b\tline one line two\tx  y z\tu v w x y z\nnext\n")
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
    let envelope = #""apiVersion":"openjoystickdriver/v1alpha2","kind":"LogLocation""#
    let logPath = ["log", "path"]
    #expect(try CLIOutputSchema.issues(in: #"{\#(envelope),"path":"/a"}"#, path: logPath).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{\#(envelope),"path":1}"#, path: logPath).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{\#(envelope)}"#, path: logPath).isEmpty)
    #expect(try !CLIOutputSchema.issues(in: #"{"path":"/a"}"#, path: logPath).isEmpty)
    #expect(
      try !CLIOutputSchema.issues(
        in: #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"LogShow","path":"/a"}"#,
        path: logPath
      ).isEmpty
    )
    #expect(
      try !CLIOutputSchema.issues(in: #"{\#(envelope),"path":"/a","extra":true}"#, path: logPath)
        .isEmpty
    )
  }

  @Test(arguments: ["USBPacket", "JoyConPair", "rawReport"])
  func aStreamLineOfAnUnknownKindIsRefused(kind: String) throws {
    let line =
      #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"\#(kind)","#
      + #""direction":"Rx","hex":"01 02","length":2,"captureTime":"1970-01-01T00:00:01.500Z"}"#
    #expect(try !CLIOutputSchema.issues(in: line, path: ["controller", "capture"]).isEmpty)
  }

  @Test
  func theCurrentPairAndSessionDocumentsPass() throws {
    let pair =
      #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"ControllerPair","gyro":"Left","#
      + #""left":"a","profile":"p","right":"b","session":"01234567-89AB-CDEF-0123-456789ABCDEF"}"#
    #expect(try CLIOutputSchema.issues(in: pair, path: ["controller", "pair"]).isEmpty)
    let session =
      #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"ControllerSession","#
      + #""changed":false,"controller":"c","session":"Suspended"}"#
    #expect(try CLIOutputSchema.issues(in: session, path: ["controller", "suspend"]).isEmpty)
  }

  @Test(arguments: ["JoyConPair", "controllerPair", "RawReport"])
  func aPairDocumentOfAnUnknownKindIsRefused(kind: String) throws {
    let document =
      #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"\#(kind)","gyro":"Left","#
      + #""left":"a","profile":"p","right":"b","session":"01234567-89AB-CDEF-0123-456789ABCDEF"}"#
    #expect(try !CLIOutputSchema.issues(in: document, path: ["controller", "pair"]).isEmpty)
  }

  @Test(arguments: ["active", "suspended", "disconnected"])
  func aSessionOfAnUnknownSpellingIsRefused(session: String) throws {
    let document =
      #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"ControllerSession","#
      + #""changed":false,"controller":"c","session":"\#(session)"}"#
    #expect(
      try !CLIOutputSchema.issues(in: document, path: ["controller", "suspend"]).isEmpty
    )
  }

  @Test
  func eachLineOfAStreamIsChecked() throws {
    let good =
      #"{"apiVersion":"openjoystickdriver/v1alpha2","kind":"RawReport","#
      + #""direction":"Rx","hex":"01 02","length":2,"captureTime":"1970-01-01T00:00:01.500Z"}"#
    #expect(
      try CLIOutputSchema.issues(in: good + "\n" + good, path: ["controller", "capture"]).isEmpty
    )
    #expect(
      try !CLIOutputSchema.issues(in: good + "\n{}", path: ["controller", "capture"]).isEmpty
    )
  }
}
