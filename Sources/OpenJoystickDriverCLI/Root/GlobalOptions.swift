import ArgumentParser
import Foundation

/// The flags every `ojd` command accepts, before or after the subcommand.
///
/// The root, every group, and every leaf command declare this group; the parser gives a flag's
/// value to each declaration, so a leaf sees flags written anywhere on the command line.
struct GlobalOptions: ParsableArguments {
  /// Whether a subcommand's declaration shows these options, which only the root help lists.
  /// Completion scripts include only shown options, so they show while one is generated.
  @TaskLocal
  static var subcommandVisibility = ArgumentVisibility.hidden

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
    if let timeout, !Self.isTimeout(timeout) {
      throw ValidationError(
        CLILocalized.text("cli.error.timeout_value")
      )
    }
    _ = try EnvironmentFallback(ProcessInfo.processInfo.environment)
  }

  var context: CLIContext { context(environment: ProcessInfo.processInfo.environment) }

  /// The context these flags give, with `environment` filling in unset flags; a flag beats its
  /// variable. ``validate()`` has already rejected an invalid variable.
  func context(environment: [String: String]) -> CLIContext {
    let fallback = (try? EnvironmentFallback(environment)) ?? EnvironmentFallback()
    return CLIContext(
      format: json ? .json : plain ? .plain : .human,
      quiet: quiet,
      noColor: noColor || fallback.color == .never,
      forceColor: !noColor && fallback.color == .always,
      noInput: noInput || fallback.noInput,
      timeout: timeout ?? fallback.timeout
    )
  }

  static func isTimeout(_ seconds: Double) -> Bool { seconds.isFinite && seconds > 0 }

  /// Runs `body` with these options as the task's `CLIContext`.
  func run(_ body: () async throws -> Void) async throws {
    try await CLIContext.$current.withValue(context) { try await body() }
  }
}

/// The `OJD_NO_INPUT`, `OJD_TIMEOUT`, and `OJD_COLOR` variables that stand in for unset flags.
/// An empty variable is unset.
struct EnvironmentFallback {
  enum Color: String {
    case auto
    case always
    case never
  }

  var noInput = false
  var timeout: Double?
  var color: Color?

  init() {}

  init(_ environment: [String: String]) throws {
    noInput = !["", "0"].contains(environment["OJD_NO_INPUT"] ?? "")
    if let value = environment["OJD_TIMEOUT"], !value.isEmpty {
      guard let seconds = Double(value), GlobalOptions.isTimeout(seconds) else {
        throw ValidationError(CLILocalized.text("cli.error.env_timeout"))
      }
      timeout = seconds
    }
    if let value = environment["OJD_COLOR"], !value.isEmpty {
      guard let color = Color(rawValue: value) else {
        throw ValidationError(CLILocalized.text("cli.error.env_color"))
      }
      self.color = color
    }
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
  /// `OJD_COLOR=always`: color even off a terminal, with `NO_COLOR` set, or with `TERM=dumb`.
  var forceColor = false
  var noInput = false
  var timeout: Double?

  var requestTimeout: Double { timeout ?? Self.defaultRequestTimeout }

  var waitTimeout: Double { timeout ?? Self.defaultWaitTimeout }
}
