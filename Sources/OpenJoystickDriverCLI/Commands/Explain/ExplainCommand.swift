import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The `ojd explain` command: prints the area and the meaning of an error code, and the exit code
/// of a command-line code or the wire value of a remapping code.
///
/// It works offline.
struct ExplainCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "explain",
    abstract: CLILocalized.text(
      "cli.explain.group.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.explain.group.discussion"
    )
  )

  /// The error code, such as `E2004`, in any letter case.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.explain.group.code"),
      valueName: "code"
    )
  )
  var code: String

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// The `--json` result.
  private struct Result: Encodable {
    /// The error code.
    let code: String
    /// The error domain; it is not encoded.
    let domain: String
    /// The name of the area of the domain.
    let area: String
    /// What the code means.
    let explanation: String
    /// The exit code of a command-line code.
    let exitCode: Int32?
    /// The wire value of a remapping code.
    let wire: String?

    /// The keys of the result.
    private enum CodingKeys: String, CodingKey {
      /// The result fields, named as in the JSON.
      case code, area, explanation, exitCode, wire
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let result = try Self.result(for: code)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.code, result.domain,
            result.exitCode.map(String.init) ?? result.wire ?? "",
          ]
        ])
      case .human:
        CLIOutput.stdout(result.code)
        CLIOutput.stdout(
          CLILocalized.format("cli.explain.group.area", result.area)
        )
        if let exitCode = result.exitCode {
          CLIOutput.stdout(
            CLILocalized.format("cli.explain.group.exitCode", String(exitCode))
          )
        }
        if let wire = result.wire {
          CLIOutput.stdout(CLILocalized.format("cli.explain.group.wire", wire))
        }
        CLIOutput.stdout()
        CLIOutput.stdout(result.explanation)
      }
    }
  }

  /// The explanation of `code`.
  ///
  /// - Throws: ``CLIFailure`` with the usage code when `code` is not an error code.
  private static func result(for code: String) throws -> Result {
    guard let id = ErrorCode(typed: code) else {
      throw CLIFailure.usage(CLILocalized.format("cli.explain.group.unknown", code))
    }
    let facts = id.facts
    return Result(
      code: facts.code,
      domain: facts.domain,
      area: facts.area,
      explanation: facts.explanation,
      exitCode: facts.exitCode,
      wire: facts.wire
    )
  }
}
