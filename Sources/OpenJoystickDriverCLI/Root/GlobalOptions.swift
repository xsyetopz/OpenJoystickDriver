import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// The flags every `ojd` command accepts, before or after the subcommand.
///
/// The root, every group, and every leaf command declare this group; the parser gives a flag's
/// value to each declaration, so a leaf sees flags written anywhere on the command line.
struct GlobalOptions: ParsableArguments {
  /// Whether a subcommand's declaration shows these options, which only the root help lists.
  ///
  /// Completion scripts include only shown options, so they show while one is generated.
  @TaskLocal
  static var subcommandVisibility = ArgumentVisibility.hidden

  /// `--json`: print JSON on standard output.
  @Flag(help: ArgumentHelp(CLILocalized.text("cli.shared.option.json")))
  var json = false

  /// `--plain`: print one tab-separated record per line on standard output.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.plain")
    )
  )
  var plain = false

  /// `-q`, `--quiet`: do not print success messages on standard error.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.quiet")
    )
  )
  var quiet = false

  /// `--no-color`: do not color text.
  @Flag(help: ArgumentHelp(CLILocalized.text("cli.shared.option.noColor")))
  var noColor = false

  /// `--no-input`: never ask a question.
  @Flag(
    help: ArgumentHelp(
      CLILocalized.text("cli.shared.option.noInput")
    )
  )
  var noInput = false

  /// The help of `--timeout`, formatted once because the parser builds this group many times per
  /// parse.
  ///
  /// It uses no locale, so the defaults read as `--timeout` parses them ("0.5", not "0,5").
  private static let timeoutHelp = unsafe String(
    format: CLILocalized.text("cli.shared.option.timeout"),
    ServiceTimeouts.request,
    ServiceTimeouts.wait
  )

  /// `--timeout`: the seconds to wait for a request or a wait, instead of the defaults.
  @Option(help: ArgumentHelp(timeoutHelp, valueName: "seconds"))
  var timeout: Double?

  /// Refuses `--json` together with `--plain`, a `--timeout` that is not a positive number, and an
  /// invalid `OJD_*` variable.
  ///
  /// - Throws: `ValidationError` with the localized reason.
  func validate() throws {
    if json, plain {
      throw ValidationError(
        CLILocalized.text("cli.shared.error.jsonPlain")
      )
    }
    if let timeout, !isPositiveSeconds(timeout) {
      throw ValidationError(
        CLILocalized.text("cli.shared.error.timeoutValue")
      )
    }
    _ = try EnvironmentOptions(ProcessInfo.processInfo.environment)
  }

  /// The context these flags give, with `environment` filling in unset flags; a flag beats its
  /// variable.
  ///
  /// - Throws: The same `ValidationError` as ``validate()`` for an invalid variable.
  func context(environment: [String: String]) throws -> CLIContext {
    let variables = try EnvironmentOptions(environment)
    return CLIContext(
      format: json ? .json : plain ? .plain : .human,
      quiet: quiet,
      noColor: noColor || variables.color == .never,
      forceColor: !noColor && variables.color == .always,
      noInput: noInput || variables.noInput,
      timeout: timeout ?? variables.timeout
    )
  }

  /// Runs `body` with these options as the task's ``CLIContext``.
  ///
  /// - Throws: What `body` throws, or `ValidationError` for an invalid variable.
  func run(_ body: () async throws -> Void) async throws {
    let resolved = try context(environment: ProcessInfo.processInfo.environment)
    try await CLIContext.$current.withValue(resolved) { try await body() }
  }
}

/// The `OJD_NO_INPUT`, `OJD_TIMEOUT`, and `OJD_COLOR` variables that stand in for unset flags.
///
/// An empty variable is unset.
struct EnvironmentOptions {
  /// The value of `OJD_COLOR`.
  enum Color: String {
    /// Color follows the terminal.
    case auto
    /// Color is on regardless of the terminal.
    case always
    /// Color is off.
    case never
  }

  /// Whether `OJD_NO_INPUT` is true.
  var noInput = false
  /// The seconds of `OJD_TIMEOUT`, or nil when it is unset.
  var timeout: Double?
  /// The value of `OJD_COLOR`, or nil when it is unset.
  var color: Color?

  /// Reads the variables from `environment`.
  ///
  /// - Throws: `ValidationError` when a variable has a value that it does not accept.
  init(_ environment: [String: String]) throws {
    switch (environment["OJD_NO_INPUT"] ?? "").lowercased() {
    case "", "0", "false", "no": noInput = false
    case "1", "true", "yes": noInput = true
    default: throw ValidationError(CLILocalized.text("cli.shared.error.envNoInput"))
    }
    if let value = environment["OJD_TIMEOUT"], !value.isEmpty {
      guard let seconds = Double(value), isPositiveSeconds(seconds) else {
        throw ValidationError(CLILocalized.text("cli.shared.error.envTimeout"))
      }
      timeout = seconds
    }
    if let value = environment["OJD_COLOR"], !value.isEmpty {
      guard let parsed = Color(rawValue: value) else {
        throw ValidationError(CLILocalized.text("cli.shared.error.envColor"))
      }
      self.color = parsed
    }
  }
}

/// The resolved global options for the running command.
struct CLIContext: Sendable {
  /// The output format of the command.
  enum Format: Sendable {
    /// Text for people.
    case human
    /// A JSON document or stream.
    case json
    /// Tab-separated records.
    case plain
  }

  /// The context of the running command.
  @TaskLocal
  static var current = Self()

  /// The output format.
  var format: Format = .human
  /// Whether `--quiet` is set.
  var quiet = false
  /// Whether color is off.
  var noColor = false
  /// `OJD_COLOR=always`: color even off a terminal, with `NO_COLOR` set, or with `TERM=dumb`.
  var forceColor = false
  /// Whether questions are off.
  var noInput = false
  /// The `--timeout` seconds, or nil to use the defaults.
  var timeout: Double?

  /// The seconds to wait for one service request.
  var requestTimeout: Double { timeout ?? ServiceTimeouts.request }

  /// The seconds to wait for a service to reach a state.
  var waitTimeout: Double { timeout ?? ServiceTimeouts.wait }
}
