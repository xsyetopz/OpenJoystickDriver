import Darwin
import Foundation

/// The two log files of the service process.
public enum ApplicationServiceLogStream: String, CaseIterable, Codable, Sendable {
  /// The log of standard output, `OpenJoystickDriver.out.log`.
  case standardOutput = "StandardOutput"
  /// The log of standard error, `OpenJoystickDriver.err.log`.
  case standardError = "StandardError"
}

/// The tail of one log file with the facts that tell a short result from a missing file.
public struct ApplicationServiceLogSnapshot: Codable, Equatable, Sendable {
  /// The log the lines come from.
  public let stream: ApplicationServiceLogStream
  /// The path of the log file.
  public let path: String
  /// Whether the log file exists.
  public let exists: Bool
  /// The size of the whole file in bytes; 0 when it does not exist.
  public let fileSizeBytes: UInt64
  /// The last lines of the file, oldest first.
  public let lines: [String]
  /// Whether the file holds more than `lines` shows.
  public let truncated: Bool

  /// Creates a snapshot from its values.
  public init(
    stream: ApplicationServiceLogStream,
    path: String,
    exists: Bool,
    fileSizeBytes: UInt64,
    lines: [String],
    truncated: Bool
  ) {
    self.stream = stream
    self.path = path
    self.exists = exists
    self.fileSizeBytes = fileSizeBytes
    self.lines = lines
    self.truncated = truncated
  }
}

/// Reads, follows and exports the log files of the service process.
public enum ApplicationServiceLogService {
  /// The line count of ``tail(stream:maximumLines:maximumBytes:)`` unless the caller sets one.
  public static let defaultMaximumLines = 100
  /// The most bytes ``tail(stream:maximumLines:maximumBytes:)`` reads, counted from the end of the
  /// file, unless the caller sets one.
  public static let defaultMaximumBytes = 262_144
  /// The accepted range of a requested line count.
  public static let linesRange = 1...10_000
  /// The line count of `ojd log export` and of the Save Activity Log menu item.
  public static let defaultExportLines = 2_000
  /// The note to read before sharing a log.
  public static var sharingWarning: String { Localization().string("cli.log.group.sharingWarning") }

  /// The folder that holds the log files, which `ojd log path` prints.
  public static var directory: URL {
    url(for: .standardOutput).deletingLastPathComponent()
  }

  /// The log file of `stream` in the `.logs` location of `dataDirectory`.
  public static func url(
    for stream: ApplicationServiceLogStream,
    dataDirectory: any DataDirectory = MacOSDataDirectory()
  ) -> URL {
    let suffix = stream == .standardOutput ? "out" : "err"
    return dataDirectory.fileURL("OpenJoystickDriver.\(suffix).log", in: .logs)
  }

  /// Redirects the host process streams to fresh, user-private files for this session.
  ///
  /// Headless commands deliberately do not call this function so their output remains
  /// attached to the invoking terminal. A second app process fails here before it empties the
  /// logs of the running one.
  public static func beginCurrentSessionCapture() throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    // The descriptor stays open, so this process holds the lock until it ends.
    _ = try claimSessionLogs(in: directory)
    for (stream, target) in [
      (ApplicationServiceLogStream.standardOutput, STDOUT_FILENO),
      (ApplicationServiceLogStream.standardError, STDERR_FILENO),
    ] {
      let path = url(for: stream).path
      let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR)
      guard descriptor >= 0 else {
        throw ApplicationServiceLogError("Could not open \(path): errno \(errno).")
      }
      guard dup2(descriptor, target) >= 0 else {
        let code = errno
        Darwin.close(descriptor)
        throw ApplicationServiceLogError("Could not redirect \(path): errno \(code).")
      }
      Darwin.close(descriptor)
    }
    setvbuf(stdout, nil, _IOLBF, 0)
    setvbuf(stderr, nil, _IOLBF, 0)
  }

  /// Takes the lock that makes this process the one writer of the session logs in `directory` and
  /// returns its descriptor; closing the descriptor releases the lock.
  ///
  /// Throws while another process holds it.
  static func claimSessionLogs(in directory: URL) throws -> Int32 {
    let path = directory.appendingPathComponent("OpenJoystickDriver.log.lock").path
    let lock = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard lock >= 0 else {
      throw ApplicationServiceLogError("Could not open \(path): errno \(errno).")
    }
    while flock(lock, LOCK_EX | LOCK_NB) != 0 {
      let code = errno
      guard code == EINTR else {
        Darwin.close(lock)
        throw ApplicationServiceLogError(
          code == EWOULDBLOCK
            ? "Another OpenJoystickDriver process writes the logs in \(directory.path)."
            : "Could not lock \(path): errno \(code)."
        )
      }
    }
    return lock
  }

  /// The last lines of the log of `stream`.
  ///
  /// It reads at most `maximumBytes` from the end of the file and drops the line that the cut
  /// splits, then keeps the last `maximumLines` lines.
  ///
  /// - Throws: An error when `maximumLines` or `maximumBytes` is not positive, or when the file
  ///   exists and cannot be read.
  public static func tail(
    stream: ApplicationServiceLogStream,
    maximumLines: Int = defaultMaximumLines,
    maximumBytes: Int = defaultMaximumBytes
  ) throws -> ApplicationServiceLogSnapshot {
    try tail(
      url: url(for: stream),
      stream: stream,
      maximumLines: maximumLines,
      maximumBytes: maximumBytes
    )
  }

  /// The tail of the log file at `url`; the public overload passes the file of `stream`.
  ///
  /// - Throws: An error when `maximumLines` or `maximumBytes` is not positive, or when the file
  ///   exists and cannot be read.
  static func tail(
    url: URL,
    stream: ApplicationServiceLogStream,
    maximumLines: Int,
    maximumBytes: Int
  ) throws -> ApplicationServiceLogSnapshot {
    guard maximumLines > 0 else {
      throw ApplicationServiceLogError("maximumLines must be greater than zero.")
    }
    guard maximumBytes > 0 else {
      throw ApplicationServiceLogError("maximumBytes must be greater than zero.")
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      return ApplicationServiceLogSnapshot(
        stream: stream,
        path: url.path,
        exists: false,
        fileSizeBytes: 0,
        lines: [],
        truncated: false
      )
    }

    let handle = try FileHandle(forReadingFrom: url)
    defer { handle.closeFile() }
    let fileSize = handle.seekToEndOfFile()
    let retainedBytes = min(fileSize, UInt64(maximumBytes))
    let offset = fileSize - retainedBytes
    handle.seek(toFileOffset: offset)
    let data = handle.readDataToEndOfFile()
    var text = String(bytes: data, encoding: .utf8) ?? ""

    if offset > 0 {
      if let firstNewline = text.firstIndex(of: "\n") {
        text.removeSubrange(...firstNewline)
      } else {
        text = ""
      }
    }

    let allLines = text.split(whereSeparator: \.isNewline).map(String.init)
    let selectedLines = Array(allLines.suffix(maximumLines))
    return ApplicationServiceLogSnapshot(
      stream: stream,
      path: url.path,
      exists: true,
      fileSizeBytes: fileSize,
      lines: selectedLines,
      truncated: offset > 0 || selectedLines.count < allLines.count
    )
  }

  /// The text `ojd log show` prints on a terminal and `ojd log export` writes: one heading per
  /// stream, a note for a missing, empty or shortened log, then its lines.
  public static func humanText(_ snapshots: [ApplicationServiceLogSnapshot]) -> String {
    let localization = Localization()
    var text = ""
    for snapshot in snapshots {
      text += "== \(CommandLineName.kebab(snapshot.stream.rawValue)): \(snapshot.path) ==\n"
      if !snapshot.exists {
        text += localization.string("cli.log.show.missing") + "\n"
      } else if snapshot.lines.isEmpty {
        text += localization.string("cli.log.show.empty") + "\n"
      }
      if snapshot.truncated {
        text += localization.string("cli.log.show.truncated") + "\n"
      }
      for line in snapshot.lines { text += line + "\n" }
    }
    return text
  }

  /// The file content of `ojd log export`: ``humanText(_:)`` with `home` written as `~`.
  public static func exportText(
    _ snapshots: [ApplicationServiceLogSnapshot],
    home: String
  ) -> String {
    HomeFolder.redacting(humanText(snapshots), home: home)
  }
}

/// The failure of a log operation, with a message for the user.
private struct ApplicationServiceLogError: LocalizedError, Sendable {
  /// The message that `errorDescription` returns.
  let message: String

  /// Creates an error with `message`.
  init(_ message: String) { self.message = message }

  /// The description of the error for the user.
  var errorDescription: String? { message }
}
