import Darwin
import Foundation

/// Runs one script in a helper process and ends the process at a time limit.
///
/// JavaScriptCore has no public way to stop a script, and a process can be ended.
enum GenerateRunner {
  /// What the helper did.
  struct Outcome: Equatable, Sendable {
    /// What the helper wrote on standard output.
    let output: Data
    /// Whether the time limit ended the helper.
    let timedOut: Bool
    /// The exit status of the helper, or the signal that ended it.
    let status: Int32
  }

  /// The environment variable that makes the executable run as the helper.
  static let environmentKey = "OJD_GENERATE_HELPER"

  /// Starts `executable` as the helper for `script` and waits for it, at most `timeout` seconds.
  ///
  /// - Throws: The error of starting the process.
  static func run(executable: URL, script: URL, timeout: TimeInterval) async throws -> Outcome {
    let process = Process()
    process.executableURL = executable
    process.arguments = [script.path]
    process.environment = ProcessInfo.processInfo.environment.merging([environmentKey: "1"]) {
      _,
      new in new
    }
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    // `waitUntilExit` waits on a run loop that a test host may never run.
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    try process.run()
    // The reader sees the end of the output only when no process holds the write end.
    try? pipe.fileHandleForWriting.close()
    let processID = process.processIdentifier
    let expired = Expired()
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler {
      expired.set()
      kill(processID, SIGKILL)
    }
    timer.resume()
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        // Reading to the end also drains the pipe, so a large result cannot block the helper.
        let output = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        exited.wait()
        timer.cancel()
        continuation.resume(
          returning: Outcome(
            output: output,
            timedOut: expired.value,
            status: process.terminationStatus
          )
        )
      }
    }
  }

  /// A flag that the timer sets on one queue and the reader reads on another.
  private final class Expired: @unchecked Sendable {
    private let lock = NSLock()
    private var expired = false

    func set() {
      lock.lock()
      expired = true
      lock.unlock()
    }

    var value: Bool {
      lock.lock()
      defer { lock.unlock() }
      return expired
    }
  }
}
