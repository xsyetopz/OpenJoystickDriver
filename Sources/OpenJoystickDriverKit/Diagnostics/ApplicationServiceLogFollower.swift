import Darwin
import Foundation

/// One line a followed log stream produced.
public struct ApplicationServiceLogLine: Equatable, Sendable {
  /// The log the line came from.
  public let stream: ApplicationServiceLogStream
  /// The line without its newline.
  public let text: String

  /// Creates a line from its stream and text.
  public init(stream: ApplicationServiceLogStream, text: String) {
    self.stream = stream
    self.text = text
  }
}

/// Polls a log file for appended lines.
public enum ApplicationServiceLogFollower {
  /// The pause between two reads of the log file, in nanoseconds.
  static let pollNanoseconds: UInt64 = 200_000_000

  /// The lines appended to the log of `stream` after `offset` bytes, until the task that iterates
  /// the stream is cancelled.
  ///
  /// Bytes that are not UTF-8 show as replacement characters.
  public static func lines(
    of stream: ApplicationServiceLogStream,
    from offset: UInt64
  ) -> AsyncStream<ApplicationServiceLogLine> {
    lines(of: stream, at: ApplicationServiceLogService.url(for: stream), from: offset)
  }

  /// Follows the log file at `url`; the public overload passes the file of `stream`.
  static func lines(
    of stream: ApplicationServiceLogStream,
    at url: URL,
    from offset: UInt64
  ) -> AsyncStream<ApplicationServiceLogLine> {
    AsyncStream { continuation in
      let initialIdentity = fileIdentity(url)
      let task = Task {
        var position = offset
        var identity = initialIdentity
        var pending = Data()
        while !Task.isCancelled {
          if let chunk = readAppended(url, position: &position, identity: &identity) {
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
              let line = pending[pending.startIndex..<newline]
              // Lossy on purpose: a line with invalid bytes still shows.
              // swiftlint:disable:next optional_data_string_conversion
              let text = String(decoding: Array(line), as: UTF8.self)
              continuation.yield(ApplicationServiceLogLine(stream: stream, text: text))
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

  /// The inode of the file at `url`, which changes when a new file replaces it.
  private static func fileIdentity(_ url: URL) -> UInt64? {
    var info = stat()
    guard unsafe stat(url.path, &info) == 0 else { return nil }
    return UInt64(info.st_ino)
  }

  /// Reads what `url` gained after `position` and moves `position` to the end.
  ///
  /// A file that shrank or was replaced by another file belongs to a later session, so it is read
  /// from the start.
  private static func readAppended(
    _ url: URL,
    position: inout UInt64,
    identity: inout UInt64?
  ) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { handle.closeFile() }
    var info = stat()
    guard unsafe fstat(handle.fileDescriptor, &info) == 0 else { return nil }
    let current = UInt64(info.st_ino)
    if let known = identity, known != current { position = 0 }
    identity = current
    let size = handle.seekToEndOfFile()
    if size < position { position = 0 }
    guard size > position else { return nil }
    handle.seek(toFileOffset: position)
    let data = handle.readData(ofLength: Int(size - position))
    position += UInt64(data.count)
    return data
  }
}
