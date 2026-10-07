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

  /// The `apiVersion` of every `--json` document and stream line.
  static let apiVersion = OpenJoystickDriverAPI.version

  /// The `kind` of the running command's `--json` output; see ``CLI/outputKinds``.
  @TaskLocal
  static var kind = ""

  /// Prints `value` as sorted, pretty-printed JSON on stdout, with `apiVersion` and `kind`.
  ///
  /// `kind` replaces the running command's kind for a command whose output kind depends on its
  /// options.
  static func json(_ value: some Encodable, kind: String? = nil) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(CLIDocument(kind: kind ?? self.kind, value: value))
    stdout(String(bytes: data, encoding: .utf8) ?? "")
  }

  /// Prints `value` as one line of sorted JSON on stdout, with `apiVersion` and `kind`, for a
  /// `--json` stream.
  static func jsonLine(_ value: some Encodable, kind: String? = nil) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(CLIDocument(kind: kind ?? self.kind, value: value))
    stdout(String(bytes: data, encoding: .utf8) ?? "")
  }

  /// Prints `value` as one line of sorted JSON on stdout, without `apiVersion` and `kind`, such as
  /// a watch line `{type, object}`.
  static func jsonLineWithoutEnvelope(_ value: some Encodable) throws {
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

/// The `--json` result of a list command, as a Kubernetes list: the listed `items`, and the data
/// about the list in `metadata`.
struct CLIList<Item: Encodable, Metadata: Encodable>: Encodable {
  let metadata: Metadata
  let items: [Item]
}

/// The `metadata` of a list that has no data besides its items.
struct CLINoMetadata: Encodable {}

extension CLIList where Metadata == CLINoMetadata {
  init(items: [Item]) { self.init(metadata: CLINoMetadata(), items: items) }
}

/// A `--json` document: the keys of `value`, an object, with `apiVersion` and `kind` added.
private struct CLIDocument<Value: Encodable>: Encodable {
  let kind: String
  let value: Value

  private enum CodingKeys: String, CodingKey {
    case apiVersion
    case kind
  }

  func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(CLIOutput.apiVersion, forKey: .apiVersion)
    try container.encode(kind, forKey: .kind)
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
