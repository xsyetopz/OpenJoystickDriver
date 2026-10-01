import ArgumentParser
import Foundation
import Testing

@testable import OpenJoystickDriverCLI

struct CommandTreeTests {
  @Test
  func treeHasTheRedesignedCommands() {
    let paths = CLICommandTree.paths()
    #expect(paths.contains(["status"]))
    #expect(paths.contains(["service", "start"]))
    #expect(paths.contains(["service", "stop"]))
    #expect(paths.contains(["service", "wait"]))
    #expect(paths.contains(["permission", "list"]))
    #expect(paths.contains(["permission", "request"]))
    #expect(paths.contains(["extension", "status"]))
    #expect(paths.contains(["extension", "activate"]))
    #expect(paths.contains(["extension", "deactivate"]))
    #expect(paths.contains(["setting", "list"]))
    #expect(paths.contains(["setting", "get"]))
    #expect(paths.contains(["setting", "set"]))
    #expect(paths.contains(["log", "show"]))
    #expect(paths.contains(["log", "path"]))
    #expect(paths.contains(["diagnose"]))
    #expect(paths.contains(["update", "check"]))
    for verb in [
      "list", "show", "watch", "capture", "rumble", "light", "player", "suspend", "resume",
      "disconnect", "calibrate", "pair", "unpair",
    ] { #expect(paths.contains(["controller", verb]), "\(verb)") }
    for verb in [
      "list", "show", "create", "duplicate", "rename", "delete", "activate", "deactivate", "import",
      "export", "edit",
    ] { #expect(paths.contains(["profile", verb]), "\(verb)") }
    for verb in ["list", "set", "clear"] { #expect(paths.contains(["binding", verb]), "\(verb)") }
    for verb in ["show", "set", "reset"] { #expect(paths.contains(["virtual", verb]), "\(verb)") }
    for verb in ["draft", "list", "show", "validate", "install", "remove"] {
      #expect(paths.contains(["record", verb]), "\(verb)")
    }
  }

  @Test(arguments: [[]] + CLICommandTree.paths())
  func helpPrintsUsageOnStandardOutputAndExitsZero(path: [String]) async {
    for flag in ["--help", "-h"] {
      let result = await CLIRun.run(path + [flag])
      #expect(result.code == 0, "\(path) \(flag)")
      #expect(result.standardOutput.contains("USAGE: ojd"), "\(path) \(flag)")
      #expect(result.standardError.isEmpty, "\(path) \(flag)")
    }
  }

  @Test(arguments: CLICommandTree.leafPaths)
  func globalOptionsReachTheLeafBeforeAndAfterTheSubcommand(path: [String]) throws {
    let flags = ["--json", "--quiet", "--no-color", "--no-input", "--timeout", "2.5"]
    let leaf = path + CLICommandTree.sampleOperands(for: path)
    for arguments in [flags + leaf, leaf + flags] {
      let command = try OJDCommand.parseAsRoot(arguments)
      let global = try #require(CLICommandTree.globalOptions(of: command), "\(arguments)")
      let context = global.context
      #expect(context.format == .json, "\(arguments)")
      #expect(context.quiet && context.noColor && context.noInput, "\(arguments)")
      #expect(context.timeout == 2.5, "\(arguments)")
    }
  }

  @Test(arguments: [
    ["status", "--frobnicate"], ["--json", "--plain", "status"], ["status", "--timeout", "0"],
    ["status", "--timeout", "nan"], ["status", "extra"],
    // Removed with no alias.
    ["map"], ["app", "status"], ["permissions"], ["test"], ["--headless"], ["controller", "state"],
    ["controller", "packets"], ["controller", "trace"], ["controller", "color"],
    ["controller", "brightness"], ["controller", "disconnect-wireless"], ["controller", "output"],
    ["controller", "virtual"], ["controller", "plan"], ["diagnose", "catalog"],
    ["record", "show", "zz"], ["record", "show", "045E"], ["map", "list"], ["mapping"],
    ["binding", "clear", "p"], ["binding", "clear", "p", "button:south", "--all"],
    ["binding", "set", "p", "nonsense", "key:space"],
    ["binding", "set", "p", "button:south", "key:space", "--turbo-rate", "10"],
    ["binding", "set", "p", "button:south", "key:space", "--deadzone", "0.2"],
    ["profile", "import", "/nonexistent/profile.json"],
  ])
  func usageErrorsExitSixtyFourOnStandardErrorOnly(arguments: [String]) async {
    let result = await CLIRun.run(arguments)
    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("ojd: "))
  }

  @Test
  func versionPrintsOnStandardOutput() async {
    let result = await CLIRun.run(["--version"])
    #expect(result.code == 0)
    #expect(!result.standardOutput.isEmpty)
    #expect(result.standardError.isEmpty)
  }
}
