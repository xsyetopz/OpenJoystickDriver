import Foundation

public enum DaemonLogStream: String, CaseIterable, Codable, Sendable {
  case standardOutput
  case standardError
}

public struct DaemonLogSnapshot: Codable, Equatable, Sendable {
  public let stream: DaemonLogStream
  public let path: String
  public let exists: Bool
  public let fileSizeBytes: UInt64
  public let lines: [String]
  public let truncated: Bool

  public init(
    stream: DaemonLogStream,
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

public enum DaemonLogService {
  public static let defaultMaximumLines = 100
  public static let defaultMaximumBytes = 262_144
  public static let sharingWarning =
    "Daemon logs may contain device names, identifiers, or diagnostic paths. Review before sharing."

  public static func url(for stream: DaemonLogStream) -> URL {
    let suffix = stream == .standardOutput ? "out" : "err"
    return URL(fileURLWithPath: "/tmp/com.openjoystickdriver.daemon.\(suffix)")
  }

  public static func tail(
    stream: DaemonLogStream,
    maximumLines: Int = defaultMaximumLines,
    maximumBytes: Int = defaultMaximumBytes
  ) throws -> DaemonLogSnapshot {
    try tail(
      url: url(for: stream),
      stream: stream,
      maximumLines: maximumLines,
      maximumBytes: maximumBytes
    )
  }

  static func tail(
    url: URL,
    stream: DaemonLogStream,
    maximumLines: Int,
    maximumBytes: Int
  ) throws -> DaemonLogSnapshot {
    guard maximumLines > 0 else {
      throw DaemonLogError("maximumLines must be greater than zero.")
    }
    guard maximumBytes > 0 else {
      throw DaemonLogError("maximumBytes must be greater than zero.")
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
      return DaemonLogSnapshot(
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
    return DaemonLogSnapshot(
      stream: stream,
      path: url.path,
      exists: true,
      fileSizeBytes: fileSize,
      lines: selectedLines,
      truncated: offset > 0 || selectedLines.count < allLines.count
    )
  }
}

private struct DaemonLogError: LocalizedError, Sendable {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}
