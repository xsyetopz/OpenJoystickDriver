import Darwin
import Foundation
import OpenJoystickDriverKit

/// One line a followed log stream produced.
struct LogLine: Equatable, Sendable {
  let stream: ApplicationServiceLogStream
  let text: String
}

/// Where `ojd log` reads logs, pages them, and asks about the terminal.
///
/// Tests replace it through `LogCommand.environment`, so they never read the real logs,
/// spawn a pager, or depend on how the test runner was started.
struct LogEnvironment: Sendable {
  /// The folder that holds the service log files.
  var directory: @Sendable () -> URL
  /// The last `maximumLines` lines of one log file.
  var tail: @Sendable (ApplicationServiceLogStream, Int) throws -> ApplicationServiceLogSnapshot
  /// The lines appended to one log file after `offset` bytes, until the task is cancelled.
  var follow: @Sendable (ApplicationServiceLogStream, UInt64) -> AsyncStream<LogLine>
  /// Shows `text` through the pager command `command`.
  var page: @Sendable (_ command: String, _ text: String) throws -> Void
  /// Whether stdout is a terminal.
  var isTerminal: @Sendable () -> Bool

  static let system = Self(
    directory: {
      ApplicationServiceLogService.url(for: .standardOutput).deletingLastPathComponent()
    },
    tail: { stream, lines in
      try ApplicationServiceLogService.tail(stream: stream, maximumLines: lines)
    },
    follow: { stream, offset in LogFollower.lines(of: stream, from: offset) },
    page: { command, text in try SystemPager.show(text, command: command) },
    isTerminal: { isatty(STDOUT_FILENO) == 1 }
  )
}

/// Polls a log file for appended lines.
enum LogFollower {
  static let pollNanoseconds: UInt64 = 200_000_000

  static func lines(
    of stream: ApplicationServiceLogStream,
    from offset: UInt64
  ) -> AsyncStream<LogLine> {
    AsyncStream { continuation in
      let task = Task {
        let url = ApplicationServiceLogService.url(for: stream)
        var position = offset
        var pending = Data()
        while !Task.isCancelled {
          if let chunk = readAppended(url, position: &position) {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
              let line = pending[pending.startIndex..<newline]
              continuation.yield(
                LogLine(stream: stream, text: String(bytes: line, encoding: .utf8) ?? "")
              )
              pending.removeSubrange(pending.startIndex...newline)
            }
          }
          try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// Reads what `url` gained after `position` and moves `position` to the end; a file that shrank
  /// was replaced by a new session, so it is read from the start.
  private static func readAppended(_ url: URL, position: inout UInt64) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { handle.closeFile() }
    let size = handle.seekToEndOfFile()
    if size < position { position = 0 }
    guard size > position else { return nil }
    handle.seek(toFileOffset: position)
    let data = handle.readData(ofLength: Int(size - position))
    position += UInt64(data.count)
    return data
  }
}

/// Pipes text to a pager process through the shell, like `git` does with `$PAGER`.
enum SystemPager {
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
