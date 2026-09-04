import Testing

@testable import OpenJoystickDriver

struct CLIGrammarTests {
  @Test(arguments: [
    ("status", CLIInvocation.status([])), ("status --json", CLIInvocation.status(["--json"])),
    ("controller list", CLIInvocation.controllerList),
    ("controller state --json", CLIInvocation.controllerInput(["state", "--json"])),
    ("controller packets --limit 10", CLIInvocation.controllerInput(["packets", "--limit", "10"])),
    (
      "controller trace --seconds 30 --json-lines",
      CLIInvocation.controllerInput(["trace", "--seconds", "30", "--json-lines"])
    ),
    (
      "controller watch --device device-1",
      CLIInvocation.controllerInput(["watch", "--device", "device-1"])
    ), ("controller output plan 1 2", CLIInvocation.controllerOutput(["plan", "1", "2"])),
    ("map list --json", CLIInvocation.mapping(["list", "--json"])),
    ("app status", CLIInvocation.appStatus([])),
    ("app ready", CLIInvocation.appReady),
    ("app login enable", CLIInvocation.appLogin(enable: true)),
    ("extension enable", CLIInvocation.extension(.enable)),
    ("permissions open input", CLIInvocation.permissions(["open", "input"])),
    ("compat show", CLIInvocation.compatibility(.show)),
    ("compat set sdl2-3", CLIInvocation.compatibility(.set("sdl2-3"))),
    ("test 10", CLIInvocation.selfTest(["10"])), ("diagnose", CLIInvocation.diagnose(.summary)),
    ("diagnose catalog --json", CLIInvocation.diagnose(.gameControllerCatalog(["--json"]))),
    (
      "diagnose report --output report.json",
      CLIInvocation.diagnose(.report(["--output", "report.json"]))
    ), ("update check --json", CLIInvocation.updateCheck(["--json"]))
  ]) func parsesApprovedGrammar(raw: String, expected: CLIInvocation) throws {
    let arguments = raw.split(separator: " ").map(String.init)
    #expect(try CLIGrammar(arguments: arguments).invocation == expected)
  }

  #if DEBUG
    @Test func debugGrammarRecognizesPassiveCommand() throws {
      let invocation = try CLIGrammar(arguments: [
        "diagnose", "usb-passive", "--vid", "3537", "--pid", "1010"
      ]).invocation
      #expect(invocation == .diagnose(.usbPassive(["--vid", "3537", "--pid", "1010"])))
    }
  #endif

  @Test(arguments: [
    [], ["run"], ["list"], ["input"], ["logs"], ["updates"], ["report"], ["physical-output"],
    ["compatibility"], ["selftest"], ["sysext"], ["install"], ["uninstall"], ["start"], ["restart"],
    ["reset-settings"]
  ]) func rejectsRemovedTopLevelSpellings(arguments: [String]) {
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: arguments) }
  }

  @Test func rejectsMissingAndUnexpectedNestedCommands() {
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["controller"]) }
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["app", "login"]) }
    #expect(throws: CLIParseError.self) {
      try CLIGrammar(arguments: ["extension", "status", "now"])
    }
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["compat", "set"]) }
  }

  @Test func rejectsObsoletePublicSpellingsAtGrammarLevel() {
    for arguments in [
      ["controller", "input"], ["mapping", "list"], ["compatibility", "get"],
      ["extension", "activate"], ["extension", "deactivate"], ["permissions", "open-settings"],
      ["diagnose", "self-test"], ["diagnose", "gamecontroller-catalog"], ["diagnose", "summary"],
      ["app", "start"], ["app", "restart"]
    ] { #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: arguments) } }
  }

  @Test func standardHelpAndVersionFlagsRemainExplicit() throws {
    #expect(try CLIGrammar(arguments: ["--help"]).invocation == .help)
    #expect(try CLIGrammar(arguments: ["-v"]).invocation == .version)
  }

  @Test func extractsTheGlobalServiceTimeoutBeforeTheCommand() throws {
    let grammar = try CLIGrammar(arguments: ["--timeout", "2.5", "status"])
    #expect(grammar.invocation == .status([]))
    #expect(grammar.serviceTimeoutSeconds == 2.5)
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["--timeout", "0", "status"]) }
  }
}
