import Darwin
import Foundation
import OpenJoystickDriverKit

/// Where `ojd log` reads logs, pages them, and asks about the terminal.
///
/// Tests replace it through ``LogCommand/environment``, so they never read the real logs,
/// spawn a pager, or depend on how the test runner was started.
struct LogEnvironment: Sendable {
  /// The folder that holds the service log files.
  var directory: @Sendable () -> URL
  /// The last `maximumLines` lines of one log file.
  var tail: @Sendable (ApplicationServiceLogStream, Int) throws -> ApplicationServiceLogSnapshot
  /// The lines appended to one log file after `offset` bytes, until the task is cancelled.
  var follow:
    @Sendable (ApplicationServiceLogStream, UInt64) -> AsyncStream<ApplicationServiceLogLine>
  /// Shows `text` through the pager command `command`.
  var page: @Sendable (_ command: String, _ text: String) throws -> Void
  /// Whether stdout is a terminal.
  var isTerminal: @Sendable () -> Bool

  /// The environment that reads the real log files and starts the real pager.
  static let system = Self(
    directory: { ApplicationServiceLogService.directory },
    tail: { stream, lines in
      try ApplicationServiceLogService.tail(stream: stream, maximumLines: lines)
    },
    follow: { stream, offset in ApplicationServiceLogFollower.lines(of: stream, from: offset) },
    page: { command, text in try SystemPager.show(text, command: command) },
    isTerminal: { isatty(STDOUT_FILENO) == 1 }
  )
}

/// Pipes text to a pager process through the shell, like `git` does with `$PAGER`.
enum SystemPager {
  /// Shows `text` through the pager `command`.
  ///
  /// - Throws: What starting the pager process throws.
  static func show(_ text: String, command: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let input = Pipe()
    process.standardInput = input
    try process.run()
    // The reader may quit before the end; ignore the broken pipe instead of dying from it.
    let previous = signal(SIGPIPE, SIG_IGN)
    defer { signal(SIGPIPE, previous) }
    try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    try? input.fileHandleForWriting.close()
    process.waitUntilExit()
  }
}
