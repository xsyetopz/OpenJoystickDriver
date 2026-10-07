import ArgumentParser
import Foundation
import Testing

@testable import OpenJoystickDriverCLI

/// One in-process `ojd` invocation: its exit code and what it wrote on each stream.
struct CLIRun {
  let code: Int32
  let standardOutput: String
  let standardError: String

  static func run(_ arguments: [String]) async -> Self {
    let capture = CLIOutputCapture()
    let code = await CLIOutput.$capture.withValue(capture) {
      await CLI.execute(arguments: arguments)
    }
    let run = Self(
      code: code,
      standardOutput: capture.standardOutput,
      standardError: capture.standardError
    )
    run.expectValidJSON(arguments)
    return run
  }

  /// Checks every `--json` document and every exported profile against its schema.
  private func expectValidJSON(_ arguments: [String]) {
    let path = CLICommandTree.commandPath(in: arguments)
    if path == ["profile", "export"], code == 0,
      !arguments.contains(where: ["-o", "--output", "-h", "--help"].contains)
    {
      do {
        let issues = try CLIOutputSchema.profileIssues(in: standardOutput)
        #expect(issues.isEmpty, "ojd \(arguments.joined(separator: " ")): \(issues)")
      } catch {
        Issue.record(error, "ojd \(arguments.joined(separator: " "))")
      }
      return
    }
    guard arguments.contains("--json"), !CLIOutputSchema.exempt.contains(path),
      !standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    do {
      let issues = try CLIOutputSchema.issues(in: standardOutput, path: path)
      #expect(issues.isEmpty, "ojd \(arguments.joined(separator: " ")): \(issues)")
    } catch {
      Issue.record(error, "ojd \(arguments.joined(separator: " "))")
    }
  }

  func json() throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(standardOutput.utf8))
    return try #require(object as? [String: Any])
  }

  /// The `details` of a `Status` document, after checking that it reports success.
  func details() throws -> [String: Any] {
    let status = try json()
    #expect(status["kind"] as? String == "Status")
    #expect(status["status"] as? String == "Success")
    return try #require(status["details"] as? [String: Any])
  }
}

enum CLICommandTree {
  /// Every command path below the root, such as `["service", "wait"]`.
  static func paths(
    of command: any ParsableCommand.Type = OJDCommand.self,
    prefix: [String] = []
  ) -> [[String]] {
    command.configuration.subcommands.flatMap { subcommand -> [[String]] in
      let path = prefix + [subcommand.configuration.commandName ?? ""]
      return [path] + paths(of: subcommand, prefix: path)
    }
  }

  static var leafPaths: [[String]] { paths().filter { subcommands(at: $0).isEmpty } }

  /// The command path at the start of `arguments`, such as `["profile", "list"]`.
  static func commandPath(in arguments: [String]) -> [String] {
    var path: [String] = []
    for argument in arguments {
      guard subcommands(at: path).contains(where: { $0.configuration.commandName == argument })
      else { break }
      path.append(argument)
    }
    return path
  }

  static func subcommands(at path: [String]) -> [any ParsableCommand.Type] {
    var command: any ParsableCommand.Type = OJDCommand.self
    for name in path {
      guard
        let next = command.configuration.subcommands.first(where: {
          $0.configuration.commandName == name
        })
      else { return [] }
      command = next
    }
    return command.configuration.subcommands
  }

  /// Valid operands for leaf commands that require them, so a parse test can reach the leaf.
  static func sampleOperands(for path: [String]) -> [String] {
    switch path {
    case ["setting", "get"]: ["launch-at-login"]
    case ["explain"]: ["E2004"]
    case ["setting", "set"]: ["launch-at-login", "true"]
    case ["controller", "show"], ["controller", "watch"], ["controller", "capture"],
      ["controller", "rumble"], ["controller", "suspend"], ["controller", "resume"],
      ["controller", "disconnect"], ["virtual", "reset"]:
      ["045E:028E"]
    case ["controller", "light"]: ["045E:028E", "--color", "FF0000"]
    case ["controller", "player"]: ["045E:028E", "1"]
    case ["virtual", "set"]: ["hid-generic", "045E:028E"]
    case ["virtual", "feed"]: ["--as", "hid-generic"]
    case ["record", "draft"], ["record", "show"], ["record", "remove"]: ["045E:028E"]
    case ["record", "test"]: ["045E:028E", "--packets", "-", "--expect", "-"]
    case ["record", "validate"], ["record", "install"], ["profile", "import"],
      ["profile", "validate"]:
      ["-"]
    case ["controller", "calibrate"]: ["045E:028E", "start"]
    case ["controller", "pair"]: ["057E:2006", "057E:2007", "--profile", "Pair"]
    case ["controller", "unpair"]: ["057E:2006"]
    case ["profile", "create"]: ["Pad", "--controller", "045E:028E"]
    case ["profile", "duplicate"], ["profile", "rename"]: ["Pad", "Copy"]
    case ["profile", "show"], ["profile", "delete"], ["profile", "activate"],
      ["profile", "deactivate"], ["profile", "export"], ["profile", "edit"], ["binding", "list"]:
      ["Pad"]
    case ["profile", "get"]: ["Pad", "name"]
    case ["profile", "set"]: ["Pad", "name", "Main"]
    case ["binding", "set"]: ["Pad", "button:south", "key:space"]
    case ["binding", "clear"]: ["Pad", "--all"]
    case ["log", "export"]: ["ojd.log"]
    case ["access", "grant"], ["access", "revoke"]: ["0123abcd"]
    default: []
    }
  }

  /// The global options a parsed command received.
  static func globalOptions(of command: any ParsableCommand) -> GlobalOptions? {
    Mirror(reflecting: command).children.first { $0.label == "_global" }.flatMap {
      ($0.value as? OptionGroup<GlobalOptions>)?.wrappedValue
    }
  }
}

func temporarySocketPath() -> String { "/tmp/com.openjoystickdriver.test.\(UUID().uuidString).rpc" }
