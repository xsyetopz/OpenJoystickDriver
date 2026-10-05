import Darwin
import Dispatch
import Foundation
import OpenJoystickDriverKit

enum CLIOutput {
  static func stdout(_ message: String = "", terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardOutput)
  }

  static func stderr(_ message: String = "", terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardError)
  }

  /// Prints a success message on stderr unless `--quiet` is set.
  static func success(_ message: String) {
    guard !CLIContext.current.quiet else { return }
    stderr(message)
  }

  /// Prints `value` as sorted, pretty-printed JSON on stdout.
  static func json(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    stdout(String(bytes: data, encoding: .utf8) ?? "")
  }

  /// Prints `value` as one line of sorted JSON on stdout, for a `--json` stream.
  static func jsonLine(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    stdout(String(bytes: data, encoding: .utf8) ?? "")
  }

  /// Prints one tab-separated record per row on stdout, for `--plain`.
  static func plain(_ rows: [[String]]) {
    for row in rows {
      stdout(row.map { $0.replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t"))
    }
  }

  /// Collects output instead of writing it, for tests.
  @TaskLocal
  static var capture: CLIOutputCapture?

  private static func write(_ message: String, terminator: String, to handle: FileHandle) {
    let text = message + terminator
    if let capture {
      capture.append(text, toStandardError: handle === FileHandle.standardError)
      return
    }
    handle.write(Data(text.utf8))
  }
}

final class CLIOutputCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var standardOutputText = ""
  private var standardErrorText = ""

  var standardOutput: String { lock.withLock { standardOutputText } }

  var standardError: String { lock.withLock { standardErrorText } }

  func append(_ text: String, toStandardError: Bool) {
    lock.withLock {
      if toStandardError { standardErrorText += text } else { standardOutputText += text }
    }
  }
}

private let cliShutdownCleanup = Locked<(@Sendable () async -> Void)?>(nil)
private let cliShutdownSources = Locked<[DispatchSourceSignal]>([])

func installCLIShutdownHandlers() {
  guard cliShutdownSources.withLock({ $0.isEmpty }) else { return }
  for signalNumber in [SIGINT, SIGTERM] {
    let source = DispatchSource.makeSignalSource(
      signal: signalNumber,
      queue: DispatchQueue.global(qos: .userInitiated)
    )
    source.setEventHandler {
      Task {
        let cleanup = cliShutdownCleanup.withLock { $0 }
        await cleanup?()
        fflush(stdout)
        fflush(stderr)
        exit(128 + signalNumber)
      }
    }
    source.resume()
    signal(signalNumber, SIG_IGN)
    cliShutdownSources.withLock { $0.append(source) }
  }
}

func withCLIShutdownCleanup<T>(
  _ cleanup: @escaping @Sendable () async -> Void,
  _ body: () async throws -> T
) async rethrows -> T {
  let previous = cliShutdownCleanup.withLock { current in
    defer { current = cleanup }
    return current
  }
  defer { cliShutdownCleanup.withLock { $0 = previous } }
  return try await body()
}
