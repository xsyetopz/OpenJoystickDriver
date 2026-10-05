import ArgumentParser
import Foundation
import OpenJoystickDriverKit

struct ExplainCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "explain",
    abstract: CLILocalized.text(
      "cli.explain.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.explain.discussion"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.explain.code"),
      valueName: "code"
    )
  )
  var code: String

  @OptionGroup
  var global: GlobalOptions

  private struct Result: Encodable {
    let code: String
    let area: String
    let explanation: String
    let exitCode: Int32?
    let wire: String?
  }

  func run() async throws {
    try await global.run {
      guard let id = ErrorCode(rawValue: code.uppercased()) else {
        throw CLIFailure.usage(
          CLILocalized.format(
            "cli.explain.unknown",
            code
          )
        )
      }
      let result = Self.result(for: id)
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.code, id.domain.rawValue,
            result.exitCode.map(String.init) ?? result.wire ?? "",
          ]
        ])
      case .human:
        CLIOutput.stdout(result.code)
        CLIOutput.stdout(
          CLILocalized.format("cli.explain.area", result.area)
        )
        if let exitCode = result.exitCode {
          CLIOutput.stdout(
            CLILocalized.format("cli.explain.exit_code", String(exitCode))
          )
        }
        if let wire = result.wire {
          CLIOutput.stdout(CLILocalized.format("cli.explain.wire", wire))
        }
        CLIOutput.stdout()
        CLIOutput.stdout(result.explanation)
      }
    }
  }

  private static func result(for id: ErrorCode) -> Result {
    let area =
      switch id.domain {
      case .endpoint: CLILocalized.text("cli.explain.area.endpoint")
      case .commandLine: CLILocalized.text("cli.explain.area.cli")
      case .remapping: CLILocalized.text("cli.explain.area.remapping")
      }
    return Result(
      code: id.rawValue,
      area: area,
      explanation: id.localizedExplanation,
      exitCode: id.domain == .commandLine ? CLIExitCode(for: id).rawValue : nil,
      wire: id.domain == .remapping
        ? ApplicationServiceRemappingRPCError.Code.allCases.first { $0.errorCode == id }?.rawValue
        : nil
    )
  }
}
