import Darwin
import Dispatch
import Foundation
import OpenJoystickDriverKit

/// The writers for everything `ojd` prints: human text, raw values, `--json` documents and
/// `--plain` records.
enum CLIOutput {
  /// Prints human text on stdout, with each path under the home folder written as `~`.
  static func stdout(_ message: String = "", terminator: String = "\n") {
    write(HomeFolder.redacting(message), terminator: terminator, to: FileHandle.standardOutput)
  }

  /// Prints human text on stderr, with each path under the home folder written as `~`.
  static func stderr(_ message: String = "", terminator: String = "\n") {
    write(HomeFolder.redacting(message), terminator: terminator, to: FileHandle.standardError)
  }

  /// Prints `message` on stdout unchanged: a value a script reads, such as a path that a shell
  /// substitution uses, where `~` would not expand.
  static func raw(_ message: String, terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardOutput)
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

  /// Prints `value` as a JSON document on stdout, with `apiVersion` and `kind`, laid out by
  /// ``OrderedJSON/formatted()`` like the bundled record files.
  ///
  /// The members of the envelope and of a Swift value are sorted by name. An embedded
  /// ``OrderedJSON`` keeps its member order and the text of its numbers.
  ///
  /// - Parameters:
  ///   - value: The value to print.
  ///   - kind: Replaces the running command's kind for a command whose output kind depends on its
  ///     options.
  /// - Throws: The failure of ``OrderedJSONEncoder`` to encode `value`.
  static func json(_ value: some Encodable, kind: String? = nil) throws {
    let document = try OrderedJSONEncoder().encode(
      CLIDocument(kind: kind ?? self.kind, value: value)
    )
    raw(document.formatted(), terminator: "")
  }

  /// Prints `value` as one line of JSON on stdout, with `apiVersion` and `kind`, for a `--json`
  /// stream.
  ///
  /// Members are sorted by name.
  static func jsonLine(_ value: some Encodable, kind: String? = nil) throws {
    let document = try OrderedJSONEncoder().encode(
      CLIDocument(kind: kind ?? self.kind, value: value)
    )
    raw(document.compact())
  }

  /// Prints `value` as one line of JSON on stdout, without `apiVersion` and `kind`, such as a watch
  /// line `{type, object}`.
  ///
  /// Members are sorted by name.
  static func jsonLineWithoutEnvelope(_ value: some Encodable) throws {
    raw(try OrderedJSONEncoder().encode(value).compact())
  }

  /// Prints one tab-separated record per row on stdout, for `--plain`.
  ///
  /// A tab or a newline character (line feed, carriage return, NEL, line and paragraph separators)
  /// inside a field becomes a space, so a field never splits a row or a record.
  static func plain(_ rows: [[String]]) {
    for row in rows {
      let fields = row.map { field in
        String(
          String.UnicodeScalarView(
            field.unicodeScalars.map { scalar in
              scalar == "\t" || Character(scalar).isNewline ? " " : scalar
            }
          )
        )
      }
      raw(fields.joined(separator: "\t"))
    }
  }

  /// Collects output instead of writing it, for tests.
  @TaskLocal
  static var capture: CLIOutputCapture?

  /// Writes `message` and `terminator` to `handle`, or to ``capture`` when it is set.
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
  /// The data about the list.
  let metadata: Metadata
  /// The listed objects.
  let items: [Item]
}

/// The `metadata` of a list that has no data besides its items.
struct CLINoMetadata: Encodable {}

extension CLIList where Metadata == CLINoMetadata {
  /// Creates a list that has only `items`.
  init(items: [Item]) { self.init(metadata: CLINoMetadata(), items: items) }
}

/// A `--json` document: the keys of `value`, an object, with `apiVersion` and `kind` added.
private struct CLIDocument<Value: Encodable>: Encodable {
  /// The `kind` of the document.
  let kind: String
  /// The object whose keys the document holds.
  let value: Value

  /// The keys that the envelope adds to `value`.
  private enum CodingKeys: String, CodingKey {
    /// The `apiVersion` key.
    case apiVersion
    /// The `kind` key.
    case kind
  }

  /// Encodes the value with the `apiVersion` and `kind` keys added.
  func encode(to encoder: any Encoder) throws {
    try value.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(CLIOutput.apiVersion, forKey: .apiVersion)
    try container.encode(kind, forKey: .kind)
  }
}

/// Output that ``CLIOutput`` collected instead of writing, safe to append to from any task.
final class CLIOutputCapture: @unchecked Sendable {
  /// Guards the two text buffers.
  private let lock = NSLock()
  /// The collected standard output text.
  private var standardOutputText = ""
  /// The collected standard error text.
  private var standardErrorText = ""

  /// Everything written to standard output so far.
  var standardOutput: String { lock.withLock { standardOutputText } }

  /// Everything written to standard error so far.
  var standardError: String { lock.withLock { standardErrorText } }

  /// Adds `text` to standard error when `toStandardError` is true, and to standard output
  /// otherwise.
  func append(_ text: String, toStandardError: Bool) {
    lock.withLock {
      if toStandardError { standardErrorText += text } else { standardOutputText += text }
    }
  }
}

/// The cleanup that runs when `ojd` receives SIGINT or SIGTERM, or nil when none is set.
private let cliShutdownCleanup = Locked<(@Sendable () async -> Void)?>(nil)
/// The dispatch sources that watch for SIGINT and SIGTERM.
private let cliShutdownSources = Locked<[any DispatchSourceSignal]>([])

/// Makes SIGINT and SIGTERM run the current cleanup, flush the output and exit with 128 plus the
/// signal number.
///
/// Does nothing once installed.
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
        unsafe fflush(stdout)
        unsafe fflush(stderr)
        exit(128 + signalNumber)
      }
    }
    source.resume()
    signal(signalNumber, SIG_IGN)
    cliShutdownSources.withLock { $0.append(source) }
  }
}

/// Runs `body` with `cleanup` as the signal cleanup, and restores the previous cleanup afterwards.
///
/// - Parameters:
///   - cleanup: Runs before the process exits on SIGINT or SIGTERM while `body` runs.
///   - body: The work that runs with `cleanup` in place.
/// - Returns: The result of `body`.
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
