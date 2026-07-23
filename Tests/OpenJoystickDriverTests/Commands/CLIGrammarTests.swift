import Testing

@testable import OpenJoystickDriver

struct CLIGrammarTests {
  @Test(arguments: [
    ("status", CLIInvocation.status([])),
    ("status --json", CLIInvocation.status(["--json"])),
    ("controller list", CLIInvocation.controllerList),
    ("controller input --json", CLIInvocation.controllerInput(["state", "--json"])),
    ("controller packets --limit 10", CLIInvocation.controllerInput(["packets", "--limit", "10"])),
    (
      "controller watch --device device-1",
      CLIInvocation.controllerInput(["watch", "--device", "device-1"])
    ),
    ("controller output plan 1 2", CLIInvocation.controllerOutput(["plan", "1", "2"])),
    ("mapping list --json", CLIInvocation.mapping(["list", "--json"])),
    ("app status", CLIInvocation.appStatus([])),
    ("app login enable", CLIInvocation.appLogin(enable: true)),
    ("extension activate", CLIInvocation.extension(.activate)),
    ("permissions request", CLIInvocation.permissions(["request"])),
    ("compatibility set sdl2-3", CLIInvocation.compatibility(.set("sdl2-3"))),
    ("diagnose self-test 10", CLIInvocation.diagnose(.selfTest(["10"]))),
    (
      "diagnose report --output report.json",
      CLIInvocation.diagnose(.report(["--output", "report.json"]))
    ),
    ("update check --json", CLIInvocation.updateCheck(["--json"])),
  ]) func parsesApprovedGrammar(raw: String, expected: CLIInvocation) throws {
    let arguments = raw.split(separator: " ").map(String.init)
    #expect(try CLIGrammar(arguments: arguments).invocation == expected)
  }

  @Test(arguments: [
    [], ["run"], ["list"], ["input"], ["logs"], ["updates"], ["report"],
    ["physical-output"], ["compat"], ["selftest"], ["sysext"], ["install"],
    ["uninstall"], ["start"], ["restart"], ["reset-settings"],
  ]) func rejectsRemovedTopLevelSpellings(arguments: [String]) {
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: arguments) }
  }

  @Test func rejectsMissingAndUnexpectedNestedCommands() {
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["controller"]) }
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["app", "login"]) }
    #expect(throws: CLIParseError.self) {
      try CLIGrammar(arguments: ["extension", "status", "now"])
    }
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["compatibility", "set"]) }
  }

  @Test func standardHelpAndVersionFlagsRemainExplicit() throws {
    #expect(try CLIGrammar(arguments: ["--help"]).invocation == .help)
    #expect(try CLIGrammar(arguments: ["-v"]).invocation == .version)
  }

  @Test func extractsTheGlobalServiceTimeoutBeforeTheCommand() throws {
    let grammar = try CLIGrammar(arguments: ["--timeout", "2.5", "status"])
    #expect(grammar.invocation == .status([]))
    #expect(grammar.serviceTimeoutSeconds == 2.5)
    #expect(throws: CLIParseError.self) {
      try CLIGrammar(arguments: ["--timeout", "0", "status"])
    }
  }
}
