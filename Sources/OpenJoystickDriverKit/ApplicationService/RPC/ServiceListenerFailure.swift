import Darwin
public import Foundation

/// Why the service's request listener stopped.
///
/// The service writes it beside the RPC socket when the accept loop ends on a fatal error,
/// because the socket cannot carry the reason once it is gone; the file is
/// `service-listener-failure.schema.json`. `ojd` reads it when the service cannot be reached, and
/// reports the failure only while the process that wrote it runs. A successful listener start and
/// an orderly stop delete the file.
public struct ServiceListenerFailure: Equatable, Sendable {
  /// The `kind` of the file.
  public static let kind = "ServiceListenerFailure"
  /// The largest file that is read; a valid file is a few hundred bytes.
  static let maximumBytes = 4096
  /// The format of the time in the file: ISO 8601 in UTC, whole seconds.
  private static let timeFormat = Date.ISO8601FormatStyle()

  /// The code that explains to the user what stopped; every record carries this one.
  public var code: ErrorCode { .requestListenerStopped }
  /// The error number of the failed `accept` or `poll` call.
  public let errorNumber: Int32
  /// When the listener stopped, in whole seconds.
  public let time: Date
  /// The process that wrote the record.
  public let process: ProcessIdentity

  /// Creates a record; `time` is rounded down to whole seconds.
  public init(errorNumber: Int32, time: Date, process: ProcessIdentity) {
    self.errorNumber = errorNumber
    self.process = process
    self.time = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded(.down))
  }

  /// The file that records a listener failure of the server on `socketPath`.
  public static func path(forSocket socketPath: String) -> String { socketPath + ".failure.json" }

  /// What the file beside `socketPath` holds.
  public enum Reading: Equatable, Sendable {
    /// There is no file: the listener did not fail, or a start since deleted the record.
    case absent
    /// The process that wrote the record runs: its request listener is stopped now.
    case stopped(ServiceListenerFailure)
    /// The process that wrote the record is gone, so the service is not running; the record says
    /// why its last listener stopped.
    case earlier(ServiceListenerFailure)
    /// The file exists and cannot be used.
    case unreadable(Problem)
  }

  /// Why the file beside the socket cannot be used.
  public struct Problem: Error, Equatable, Sendable, LocalizedError {
    /// The file that cannot be used.
    public let path: String
    /// Why the file cannot be used.
    public let detail: String

    /// Creates a problem for the file `path`.
    public init(path: String, detail: String) {
      self.path = path
      self.detail = detail
    }

    /// The text of the code, then the file and the reason.
    public var explanation: String {
      "\(ErrorCode.damagedListenerFailureRecord.localizedExplanation) (\(path): \(detail))"
    }

    /// The code, then ``explanation``.
    public var errorDescription: String? {
      "\(ErrorCode.damagedListenerFailureRecord.rawValue): \(explanation)"
    }
  }

  /// The line that tells the user why the service cannot be reached: the code with its text, the
  /// error number and the time.
  public var localizedSummary: String {
    Localization().formatted(
      "status.listenerFailure.detail",
      arguments: [
        code.rawValue, code.localizedExplanation, String(errorNumber),
        time.formatted(Self.timeFormat),
      ]
    )
  }

  /// The line for a service that is not running and whose last listener stopped for this reason.
  public var localizedEarlierSummary: String {
    Localization().formatted("status.listenerFailure.earlier", arguments: [localizedSummary])
  }

  /// A process told apart from a later process that gets the same identifier: the identifier and
  /// the time the process started.
  public struct ProcessIdentity: Equatable, Sendable {
    /// The process identifier.
    public let identifier: Int32
    /// The seconds part of the process start time.
    public let startSeconds: UInt64
    /// The microseconds part of the process start time.
    public let startMicroseconds: UInt64

    /// Creates an identity from its values.
    public init(identifier: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
      self.identifier = identifier
      self.startSeconds = startSeconds
      self.startMicroseconds = startMicroseconds
    }

    /// The process that runs this code.
    public static var current: Self {
      guard case .running(let identity) = lookup(getpid()) else {
        preconditionFailure("The system does not describe the running process")
      }
      return identity
    }

    /// What the system says about a process identifier.
    public enum Lookup: Equatable, Sendable {
      /// The process runs; the value identifies it.
      case running(ProcessIdentity)
      /// No process has the identifier (`ESRCH`).
      case noSuchProcess
      /// The process belongs to another user (`EPERM`), so it is not the service that wrote a
      /// record this user owns.
      case belongsToAnotherUser
      /// The system refused the question for another reason (the error number). Readers report
      /// it instead of guessing whether the process runs.
      case unknown(Int32)

      /// The outcome of a lookup that failed with `errorNumber`.
      static func failed(with errorNumber: Int32) -> Self {
        switch errorNumber {
        case ESRCH: .noSuchProcess
        case EPERM: .belongsToAnotherUser
        default: .unknown(errorNumber)
        }
      }
    }

    /// Asks the system about the process `identifier`.
    public static func lookup(_ identifier: Int32) -> Lookup {
      var information = proc_bsdinfo()
      let size = Int32(MemoryLayout<proc_bsdinfo>.size)
      guard unsafe proc_pidinfo(identifier, PROC_PIDTBSDINFO, 0, &information, size) == size else {
        return .failed(with: errno)
      }
      return .running(
        Self(
          identifier: identifier,
          startSeconds: information.pbi_start_tvsec,
          startMicroseconds: information.pbi_start_tvusec
        )
      )
    }

  }

  /// Writes the file beside `socketPath` in one atomic replacement.
  public func write(socketPath: String) throws {
    try JSONEncoder.sorted.encode(self).write(
      to: URL(fileURLWithPath: Self.path(forSocket: socketPath)),
      options: .atomic
    )
  }

  /// Why the file beside the socket could not be deleted.
  public struct ClearError: Error, Equatable, Sendable, LocalizedError {
    /// The file that could not be deleted.
    public let path: String
    /// The error number of the failed `unlink`.
    public let errorNumber: Int32

    /// The description of the error for the user.
    public var errorDescription: String? {
      let reason = unsafe String(cString: strerror(errorNumber))
      return "unlink of \(path) failed: \(reason) (errno \(errorNumber))"
    }
  }

  /// Deletes the file beside `socketPath`; a missing file is already cleared.
  public static func clear(socketPath: String) throws {
    let path = path(forSocket: socketPath)
    guard unsafe unlink(path) != 0, errno != ENOENT else { return }
    throw ClearError(path: path, errorNumber: errno)
  }

  /// Reads the file beside the service's own socket.
  public static func readDefault() -> Reading {
    read(socketPath: LocalServiceRPCTransport.defaultSocketPath)
  }

  /// Reads the file beside `socketPath`.
  ///
  /// A file that is not a regular file, belongs to another user, is too large, or does not decode
  /// strictly is a problem, never an absent file.
  public static func read(socketPath: String) -> Reading {
    read(socketPath: socketPath, effectiveUser: geteuid(), lookup: ProcessIdentity.lookup)
  }

  /// Reads the file beside `socketPath` for the user `effectiveUser`, asking `lookup` about the
  /// writing process.
  ///
  /// The files of `effectiveUser` are the only ones it trusts. The record is current only while a
  /// process with the writer's identifier and start time runs; a process of another user, or none,
  /// is not the writer, and a lookup that fails for another reason is a problem, not a guess.
  static func read(
    socketPath: String,
    effectiveUser: uid_t,
    lookup: (Int32) -> ProcessIdentity.Lookup
  ) -> Reading {
    let path = path(forSocket: socketPath)
    let descriptor = unsafe open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      if errno == ENOENT { return .absent }
      return unsafe .unreadable(Problem(path: path, detail: String(cString: strerror(errno))))
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    var information = stat()
    guard unsafe fstat(descriptor, &information) == 0 else {
      return unsafe .unreadable(Problem(path: path, detail: String(cString: strerror(errno))))
    }
    guard information.st_mode & S_IFMT == S_IFREG else {
      return .unreadable(
        Problem(path: path, detail: Localization().string("status.listenerFailure.notRegularFile"))
      )
    }
    guard information.st_uid == effectiveUser else {
      return .unreadable(
        Problem(path: path, detail: Localization().string("status.listenerFailure.otherUser"))
      )
    }
    guard information.st_size <= maximumBytes else {
      return .unreadable(
        Problem(path: path, detail: Localization().string("status.listenerFailure.tooLarge"))
      )
    }
    do {
      let data = try handle.readToEnd() ?? Data()
      let failure = try JSONDecoder().decode(Self.self, from: data)
      switch lookup(failure.process.identifier) {
      case .running(let identity):
        return identity == failure.process ? .stopped(failure) : .earlier(failure)
      case .noSuchProcess, .belongsToAnotherUser: return .earlier(failure)
      case .unknown(let code):
        return unsafe .unreadable(
          Problem(
            path: path,
            detail: Localization().formatted(
              "status.listenerFailure.processCheckFailed",
              arguments: [String(cString: strerror(code)), String(code)]
            )
          )
        )
      }
    } catch let problem as DocumentHeaderProblem {
      return .unreadable(Problem(path: path, detail: problem.message))
    } catch let error as DecodingError {
      return .unreadable(Problem(path: path, detail: error.detail))
    } catch {
      return .unreadable(Problem(path: path, detail: error.localizedDescription))
    }
  }
}

extension ServiceListenerFailure: Codable {
  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The `apiVersion` key.
    case apiVersion
    /// The `kind` key.
    case kind
    /// The `code` key.
    case code
    /// The `errno` key.
    case errno
    /// The `time` key.
    case time
    /// The `pid` key.
    case pid
    /// The `pidStartSeconds` key.
    case pidStartSeconds
    /// The `pidStartMicroseconds` key.
    case pidStartMicroseconds
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let problem = OpenJoystickDriverAPI.headerProblem(
      apiVersion: try container.decodeIfPresent(String.self, forKey: .apiVersion),
      kind: try container.decodeIfPresent(String.self, forKey: .kind),
      expected: Self.kind
    ) {
      throw problem
    }
    let code = try container.decode(String.self, forKey: .code)
    guard code == ErrorCode.requestListenerStopped.rawValue else {
      throw DecodingError.dataCorruptedError(
        forKey: .code,
        in: container,
        debugDescription: "code \(code) is not \(ErrorCode.requestListenerStopped.rawValue)"
      )
    }
    let text = try container.decode(String.self, forKey: .time)
    guard let time = try? Date(text, strategy: Self.timeFormat) else {
      throw DecodingError.dataCorruptedError(
        forKey: .time,
        in: container,
        debugDescription: "time \(text) is not an ISO 8601 date and time in UTC"
      )
    }
    self.init(
      errorNumber: try container.decode(Int32.self, forKey: .errno),
      time: time,
      process: ProcessIdentity(
        identifier: try container.decode(Int32.self, forKey: .pid),
        startSeconds: try container.decode(UInt64.self, forKey: .pidStartSeconds),
        startMicroseconds: try container.decode(UInt64.self, forKey: .pidStartMicroseconds)
      )
    )
  }

  /// Encodes the value into `encoder`.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(OpenJoystickDriverAPI.version, forKey: .apiVersion)
    try container.encode(Self.kind, forKey: .kind)
    try container.encode(code.rawValue, forKey: .code)
    try container.encode(errorNumber, forKey: .errno)
    try container.encode(time.formatted(Self.timeFormat), forKey: .time)
    try container.encode(process.identifier, forKey: .pid)
    try container.encode(process.startSeconds, forKey: .pidStartSeconds)
    try container.encode(process.startMicroseconds, forKey: .pidStartMicroseconds)
  }
}

extension JSONEncoder {
  /// An encoder that prints sorted keys and does not escape slashes.
  static var sorted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

extension DecodingError {
  /// The reason with the field it concerns, in one line.
  var detail: String {
    let context: Context
    switch self {
    case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found),
      .dataCorrupted(let found):
      context = found
    @unknown default: return localizedDescription
    }
    let field = context.codingPath.map(\.stringValue).joined(separator: ".")
    if case .keyNotFound(let key, _) = self { return "missing field \(key.stringValue)" }
    return field.isEmpty ? context.debugDescription : "\(field): \(context.debugDescription)"
  }
}
