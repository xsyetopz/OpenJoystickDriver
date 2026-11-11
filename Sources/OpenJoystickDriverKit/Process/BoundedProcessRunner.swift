import Darwin
public import Foundation

/// Captured result from a child process whose runtime and output are bounded.
public struct BoundedProcessResult: Equatable, Sendable {
  /// The exit status of the child; -1 when it still ran after the runner tried to stop it.
  public let terminationStatus: Int32
  /// The output of the child, standard output and standard error together, as UTF-8 text.
  public let output: String
  /// Whether the child outlived the timeout.
  public let timedOut: Bool
  /// Whether the output exceeded the maximum and was cut.
  public let outputWasTruncated: Bool

  /// Creates a result from its values.
  public init(terminationStatus: Int32, output: String, timedOut: Bool, outputWasTruncated: Bool) {
    self.terminationStatus = terminationStatus
    self.output = output
    self.timedOut = timedOut
    self.outputWasTruncated = outputWasTruncated
  }
}

/// Runs short system tools without allowing a stuck child or full pipe to hang OJD.
public enum BoundedProcessRunner {
  /// The seconds a child may run.
  public static let defaultTimeoutSeconds: TimeInterval = 10
  /// The most output bytes that the runner keeps.
  public static let defaultMaximumOutputBytes = 1_048_576

  /// Runs the tool at `executableURL` and waits for it to exit, up to `timeoutSeconds`.
  ///
  /// The runner terminates a child that outlives the timeout, then kills it when it still runs a
  /// second later. It keeps at most `maximumOutputBytes` bytes of output.
  ///
  /// - Throws: The error of `Process.run()` when the tool cannot start.
  public static func run(
    executableURL: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
    maximumOutputBytes: Int = defaultMaximumOutputBytes
  ) throws -> BoundedProcessResult {
    try run(
      executableURL: executableURL,
      arguments: arguments,
      environment: environment,
      timeoutSeconds: timeoutSeconds,
      maximumOutputBytes: maximumOutputBytes
    ) { $0.wait(timeout: .now() + $1) }
  }

  /// `waitForExit` waits on the termination signal for the given seconds; tests replace it to
  /// observe the deadline a child is given.
  static func run(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]?,
    timeoutSeconds: TimeInterval,
    maximumOutputBytes: Int,
    waitForExit: (DispatchSemaphore, TimeInterval) -> DispatchTimeoutResult
  ) throws -> BoundedProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    if let environment { process.environment = environment }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let terminationFinished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminationFinished.signal() }

    do { try process.run() } catch {
      process.terminationHandler = nil
      pipe.fileHandleForReading.closeFile()
      pipe.fileHandleForWriting.closeFile()
      throw error
    }

    let capture = ProcessOutputCapture(maximumBytes: max(0, maximumOutputBytes))
    let readerFinished = DispatchSemaphore(value: 0)
    let readHandle = pipe.fileHandleForReading
    let readDescriptor = readHandle.fileDescriptor
    Thread.detachNewThread {
      defer { readerFinished.signal() }
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        let byteCount = buffer.withUnsafeMutableBytes { bytes in
          unsafe Darwin.read(readDescriptor, bytes.baseAddress, bytes.count)
        }
        if byteCount > 0 {
          capture.append(Data(buffer.prefix(byteCount)))
        } else if byteCount == -1, errno == EINTR {
          continue
        } else {
          return
        }
      }
    }
    pipe.fileHandleForWriting.closeFile()

    let timeout = max(0, timeoutSeconds)
    var timedOut = waitForExit(terminationFinished, timeout) == .timedOut
    if timedOut {
      process.terminate()
      if terminationFinished.wait(timeout: .now() + 1) == .timedOut {
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
        _ = terminationFinished.wait(timeout: .now() + 1)
      }
    }

    if readerFinished.wait(timeout: .now() + 1) == .timedOut {
      readHandle.closeFile()
      _ = readerFinished.wait(timeout: .now() + 1)
    }

    let snapshot = capture.snapshot()
    let status = process.isRunning ? Int32(-1) : process.terminationStatus
    if status == -1 { timedOut = true }
    process.terminationHandler = nil

    return BoundedProcessResult(
      terminationStatus: status,
      output: String(bytes: snapshot.data, encoding: .utf8) ?? "",
      timedOut: timedOut,
      outputWasTruncated: snapshot.wasTruncated
    )
  }
}

/// Collects a child's output up to a byte limit.
private final class ProcessOutputCapture: Sendable {
  /// The most bytes to keep.
  private let maximumBytes: Int
  /// The kept bytes and whether more arrived than the limit.
  private let output = Locked((data: Data(), wasTruncated: false))

  /// Creates a capture that keeps at most `maximumBytes` bytes.
  init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

  /// Adds `chunk` up to the limit and records when it dropped bytes.
  func append(_ chunk: Data) {
    output.withLock { output in
      let remaining = max(0, maximumBytes - output.data.count)
      if remaining > 0 { output.data.append(chunk.prefix(remaining)) }
      if chunk.count > remaining { output.wasTruncated = true }
    }
  }

  /// The kept bytes and whether bytes were dropped.
  func snapshot() -> (data: Data, wasTruncated: Bool) { output.withLock { $0 } }
}
