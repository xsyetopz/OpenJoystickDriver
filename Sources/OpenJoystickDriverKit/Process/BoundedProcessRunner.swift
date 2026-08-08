import Darwin
import Foundation

/// Captured result from a child process whose runtime and output are bounded.
public struct BoundedProcessResult: Equatable, Sendable {
  public let terminationStatus: Int32
  public let output: String
  public let timedOut: Bool
  public let outputWasTruncated: Bool

  public init(terminationStatus: Int32, output: String, timedOut: Bool, outputWasTruncated: Bool) {
    self.terminationStatus = terminationStatus
    self.output = output
    self.timedOut = timedOut
    self.outputWasTruncated = outputWasTruncated
  }
}

/// Runs short system tools without allowing a stuck child or full pipe to hang OJD.
public enum BoundedProcessRunner {
  public static let defaultTimeoutSeconds: TimeInterval = 10
  public static let defaultMaximumOutputBytes = 1_048_576

  public static func run(
    executableURL: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
    maximumOutputBytes: Int = defaultMaximumOutputBytes
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
          Darwin.read(readDescriptor, bytes.baseAddress, bytes.count)
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
    var timedOut = terminationFinished.wait(timeout: .now() + timeout) == .timedOut
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

private final class ProcessOutputCapture: @unchecked Sendable {
  private let lock = NSLock()
  private let maximumBytes: Int
  private var data = Data()
  private var wasTruncated = false

  init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

  func append(_ chunk: Data) {
    lock.withLock {
      let remaining = max(0, maximumBytes - data.count)
      if remaining > 0 { data.append(chunk.prefix(remaining)) }
      if chunk.count > remaining { wasTruncated = true }
    }
  }

  func snapshot() -> (data: Data, wasTruncated: Bool) { lock.withLock { (data, wasTruncated) } }
}
