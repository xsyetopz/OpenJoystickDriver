import ArgumentParser
import Foundation

/// The flags every `ojd` command accepts, before or after the subcommand.
///
/// The root, every group, and every leaf command declare this group; the parser gives a flag's
/// value to each declaration, so a leaf sees flags written anywhere on the command line.
struct GlobalOptions: ParsableArguments {
  @Flag(help: ArgumentHelp(CLILocalized.text("cli.option.json")))
  var json = false

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.option.plain")
    )
  )
  var plain = false

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.option.quiet")
    )
  )
  var quiet = false

  @Flag(help: ArgumentHelp(CLILocalized.text("cli.option.no_color")))
  var noColor = false

  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.option.no_input")
    )
  )
  var noInput = false

  @Option(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.option.timeout"
      ),
      valueName: "seconds"
    )
  )
  var timeout: Double?

  func validate() throws {
    if json, plain {
      throw ValidationError(
        CLILocalized.text("cli.error.json_plain")
      )
    }
    if let timeout, !(timeout.isFinite && timeout > 0) {
      throw ValidationError(
        CLILocalized.text("cli.error.timeout_value")
      )
    }
  }

  var context: CLIContext {
    CLIContext(
      format: json ? .json : plain ? .plain : .human,
      quiet: quiet,
      noColor: noColor,
      noInput: noInput,
      timeout: timeout
    )
  }

  /// Runs `body` with these options as the task's `CLIContext`.
  func run(_ body: () async throws -> Void) async throws {
    try await CLIContext.$current.withValue(context) { try await body() }
  }
}

/// The resolved global options for the running command.
struct CLIContext: Sendable {
  enum Format: Sendable {
    case human
    case json
    case plain
  }

  static let defaultRequestTimeout: Double = 0.5
  static let defaultWaitTimeout: Double = 5

  @TaskLocal
  static var current = Self()

  var format: Format = .human
  var quiet = false
  var noColor = false
  var noInput = false
  var timeout: Double?

  var requestTimeout: Double { timeout ?? Self.defaultRequestTimeout }

  var waitTimeout: Double { timeout ?? Self.defaultWaitTimeout }
}
