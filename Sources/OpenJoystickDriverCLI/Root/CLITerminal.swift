import Darwin
import Foundation
import OpenJoystickDriverKit

/// Terminal facts that decide whether `ojd` may use color or prompt.
enum CLITerminal {
  /// A standard stream that `ojd` writes text to.
  enum Stream {
    /// Standard output.
    case standardOutput
    /// Standard error.
    case standardError

    /// The file descriptor of the stream.
    var descriptor: Int32 {
      switch self {
      case .standardOutput: STDOUT_FILENO
      case .standardError: STDERR_FILENO
      }
    }
  }

  /// An ANSI foreground color that `ojd` uses for status text.
  enum Color: String {
    /// Green, the SGR code 32.
    case green = "32"
    /// Yellow, the SGR code 33.
    case yellow = "33"
    /// Red, the SGR code 31.
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
  /// otherwise fails with a confirmation error that names `--force`.
  ///
  /// - Parameters:
  ///   - question: The question to ask.
  ///   - force: Skips the question.
  ///   - needsForce: Replaces the message of that error.
  /// - Throws: ``CLIFailure`` with `confirmationRequired` when no question can be asked, or
  ///   `aborted` when the answer is not `y` or `yes`.
  static func confirm(_ question: String, force: Bool, needsForce: String? = nil) throws {
    if force { return }
    guard canPrompt() else {
      throw CLIFailure(
        .confirmationRequired,
        needsForce
          ?? CLILocalized.text(
            "cli.shared.error.confirmNeedsForce"
          )
      )
    }
    CLIOutput.stderr(question + " [y/N] ", terminator: "")
    let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    guard answer == "y" || answer == "yes" else {
      throw CLIFailure(
        .aborted,
        CLILocalized.text("cli.shared.error.confirmDeclined")
      )
    }
  }

  /// `text` wrapped in the ANSI sequence of `color` when color is allowed on `stream`, and `text`
  /// unchanged otherwise.
  static func colored(_ text: String, _ color: Color, on stream: Stream) -> String {
    guard usesColor(on: stream) else { return text }
    return "\u{1B}[\(color.rawValue)m\(text)\u{1B}[0m"
  }
}
