import Darwin
import Foundation

/// Terminal facts that decide whether `ojd` may use color or prompt.
enum CLITerminal {
  enum Stream {
    case standardOutput
    case standardError

    var descriptor: Int32 {
      switch self {
      case .standardOutput: STDOUT_FILENO
      case .standardError: STDERR_FILENO
      }
    }
  }

  enum Color: String {
    case green = "32"
    case yellow = "33"
    case red = "31"
  }

  /// Whether text written to `stream` may carry ANSI color.
  ///
  /// Color needs a terminal, and is off with `--no-color`, `NO_COLOR` set, or `TERM=dumb`.
  /// `OJD_COLOR=always` turns it on regardless, except under `--no-color`.
  static func usesColor(
    on stream: Stream,
    context: CLIContext = .current,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isTerminal: (Int32) -> Bool = { isatty($0) == 1 }
  ) -> Bool {
    guard !context.noColor, CLIOutput.capture == nil else { return false }
    if context.forceColor { return true }
    guard environment["NO_COLOR"] == nil, environment["TERM"] != "dumb" else { return false }
    return isTerminal(stream.descriptor)
  }

  /// Whether `ojd` may ask a question: stdin is a terminal and `--no-input` is not set.
  static func canPrompt(context: CLIContext = .current) -> Bool {
    !context.noInput && isatty(STDIN_FILENO) == 1
  }

  /// Confirms a destructive action: passes with `force`, asks `question` on a terminal, and
  /// otherwise fails with a confirmation error that names `--force`;
  /// `needsForce` replaces its message.
  static func confirm(_ question: String, force: Bool, needsForce: String? = nil) throws {
    if force { return }
    guard canPrompt() else {
      throw CLIFailure(
        .confirmationRequired,
        needsForce
          ?? CLILocalized.text(
            "cli.error.confirm_needs_force"
          )
      )
    }
    CLIOutput.stderr(question + " [y/N] ", terminator: "")
    let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    guard answer == "y" || answer == "yes" else {
      throw CLIFailure(
        .aborted,
        CLILocalized.text("cli.error.confirm_declined")
      )
    }
  }

  static func colored(_ text: String, _ color: Color, on stream: Stream) -> String {
    guard usesColor(on: stream) else { return text }
    return "\u{1B}[\(color.rawValue)m\(text)\u{1B}[0m"
  }
}
