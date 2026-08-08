import Darwin
import Foundation

public enum ApplicationServiceLogStream: String, CaseIterable, Codable, Sendable {
  case standardOutput
  case standardError
}

public struct ApplicationServiceLogSnapshot: Codable, Equatable, Sendable {
  public let stream: ApplicationServiceLogStream
  public let path: String
  public let exists: Bool
  public let fileSizeBytes: UInt64
  public let lines: [String]
  public let truncated: Bool

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

public enum ApplicationServiceLogService {
  public static let defaultMaximumLines = 100
  public static let defaultMaximumBytes = 262_144
  public static let sharingWarning =
    "Application service logs may contain device names, identifiers, or diagnostic paths. "
    + "Review before sharing."

  public static func url(for stream: ApplicationServiceLogStream) -> URL {
    let suffix = stream == .standardOutput ? "out" : "err"
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Logs/OpenJoystickDriver",
      isDirectory: true
    ).appendingPathComponent("OpenJoystickDriver.\(suffix).log", isDirectory: false)
  }

  /// Redirects the host process streams to fresh, user-private files for this session.
  ///
  /// Headless commands deliberately do not call this function so their output remains
  /// attached to the invoking terminal.
  public static func beginCurrentSessionCapture() throws {
    let directory = url(for: .standardOutput).deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
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
}

private struct ApplicationServiceLogError: LocalizedError, Sendable {
  let message: String

  init(_ message: String) { self.message = message }

  var errorDescription: String? { message }
}
