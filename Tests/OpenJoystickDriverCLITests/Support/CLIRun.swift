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
    return Self(
      code: code,
      standardOutput: capture.standardOutput,
      standardError: capture.standardError
    )
  }

  func json() throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(standardOutput.utf8))
    return try #require(object as? [String: Any])
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
    case ["setting", "set"]: ["launch-at-login", "true"]
    case ["controller", "show"], ["controller", "watch"], ["controller", "capture"],
      ["controller", "rumble"], ["controller", "suspend"], ["controller", "resume"],
      ["controller", "disconnect"], ["virtual", "reset"]:
      ["045E:028E"]
    case ["controller", "light"]: ["045E:028E", "--color", "FF0000"]
    case ["controller", "player"]: ["045E:028E", "1"]
    case ["virtual", "set"]: ["hid-generic", "045E:028E"]
    case ["record", "show"], ["record", "remove"]: ["045E:028E"]
    case ["record", "validate"], ["record", "install"]: ["-"]
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
