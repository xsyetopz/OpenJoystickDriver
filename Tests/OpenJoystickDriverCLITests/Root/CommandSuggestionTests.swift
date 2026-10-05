import Testing

@testable import OpenJoystickDriverCLI

struct CommandSuggestionTests {
  @Test(arguments: [
    (["stauts"], "stauts", "ojd status"),
    (["controler", "list"], "controler", "ojd controller"),
    (["controller", "lst"], "lst", "ojd controller list"),
    (["--json", "--timeout", "3", "profle", "list"], "profle", "ojd profile"),
  ])
  func aMistypedCommandSuggestsTheNearestName(
    arguments: [String],
    typed: String,
    suggestion: String
  ) {
    #expect(
      CommandSuggestion.match(arguments: arguments)
        == CommandSuggestion.Match(typed: typed, suggestion: suggestion)
    )
  }

  @Test(arguments: [["bogus"], ["controller", "bogus"]])
  func anUnknownCommandWithoutANearNameHasNoSuggestion(arguments: [String]) {
    #expect(
      CommandSuggestion.match(arguments: arguments)
        == CommandSuggestion.Match(typed: "bogus", suggestion: nil)
    )
  }

  @Test(arguments: [
    ["controller", "show", "stauts"],
    ["help", "stauts"],
    ["--", "stauts"],
    ["status", "--bogus"],
  ])
  func noMatchOutsideTheCommandNames(arguments: [String]) {
    #expect(CommandSuggestion.match(arguments: arguments) == nil)
  }

  @Test
  func aSwapOfAdjacentLettersCostsOne() {
    #expect(CommandSuggestion.editDistance("stauts", "status") == 1)
    #expect(CommandSuggestion.editDistance("", "log") == 3)
  }

  @Test
  func aMistypedCommandExitsWithUsageAndRunsNothing() async {
    let result = await CLIRun.run(["stauts"])

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2002]: "))
    #expect(result.standardError.contains("stauts"))
    #expect(result.standardError.contains("ojd status"))
  }

  @Test
  func anUnknownCommandWithoutASuggestionHasTheUnknownCommandCode() async {
    let result = await CLIRun.run(["frobnicate"])

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2002]: "))
    #expect(result.standardError.contains("frobnicate"))
  }
}
