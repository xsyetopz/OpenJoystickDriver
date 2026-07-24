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

  static func warning(_ message: String) {
    stderr("WARNING: \(message)")
  }

  static func error(_ message: String) {
    stderr("ERROR: \(message)")
  }

  static func diagnostic(_ message: String = "", terminator: String = "\n") {
    stderr(message, terminator: terminator)
  }

  private static func write(
    _ message: String,
    terminator: String,
    to handle: FileHandle
  ) {
    handle.write(Data((message + terminator).utf8))
  }
}

private final class CLIShutdownState: @unchecked Sendable {
  private let lock = NSLock()
  private var cleanup: (@Sendable () -> Void)?

  func replaceCleanup(_ cleanup: (@Sendable () -> Void)?) -> (@Sendable () -> Void)? {
    lock.withLock {
      let previous = self.cleanup
      self.cleanup = cleanup
      return previous
    }
  }

  func runCleanup() {
    let action = lock.withLock { cleanup }
    action?()
  }
}

private let cliShutdownState = CLIShutdownState()
private let cliShutdownSourceStore = NSLockProtectedSignalSourceStore()

private final class NSLockProtectedSignalSourceStore: @unchecked Sendable {
  private let lock = NSLock()
  private var sources: [DispatchSourceSignal] = []

  var hasSources: Bool {
    lock.withLock { !sources.isEmpty }
  }

  func append(_ source: DispatchSourceSignal) {
    lock.withLock { sources.append(source) }
  }
}

func installCLIShutdownHandlers() {
  guard !cliShutdownSourceStore.hasSources else { return }
  for signalNumber in [SIGINT, SIGTERM] {
    let source = DispatchSource.makeSignalSource(
      signal: signalNumber,
      queue: DispatchQueue.global(qos: .userInitiated)
    )
    source.setEventHandler {
      cliShutdownState.runCleanup()
      fflush(stdout)
      fflush(stderr)
      exit(128 + signalNumber)
    }
    source.resume()
    signal(signalNumber, SIG_IGN)
    cliShutdownSourceStore.append(source)
  }
}

func withCLIShutdownCleanup<T>(
  _ cleanup: @escaping @Sendable () -> Void,
  _ body: () throws -> T
) rethrows -> T {
  let previous = cliShutdownState.replaceCleanup(cleanup)
  defer { _ = cliShutdownState.replaceCleanup(previous) }
  return try body()
}

/// Timeout for local service calls from CLI - keeps commands
/// responsive when application service is not running.
enum CLIExecutionContext {
  nonisolated(unsafe) static var serviceCallTimeoutSeconds: Double = 0.5
}

var applicationServiceCallTimeoutSeconds: Double {
  CLIExecutionContext.serviceCallTimeoutSeconds
}

/// Blocks current thread until `block` completes.
///
/// Safe for CLI use only - never call from main actor or async context.
func runSync(_ block: @Sendable @escaping () async -> Void) {
  let semaphore = DispatchSemaphore(value: 0)
  Task {
    await block()
    semaphore.signal()
  }
  semaphore.wait()
}

/// Blocks current thread until `block` completes, returning its value.
///
/// Safe for CLI use only - never call from main actor or async context.
func runSyncResult<T: Sendable>(_ block: @Sendable @escaping () async -> T) -> T {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var result: T?
  Task {
    result = await block()
    semaphore.signal()
  }
  semaphore.wait()
  guard let value = result else {
    fatalError("runSyncResult: block completed without setting result")
  }
  return value
}

/// Blocks current thread until `block` completes or the timeout expires.
///
/// Returns nil on timeout. Safe for CLI status probes that must not hang when
/// the application service connection is invalidated without a reply.
func runSyncResult<T: Sendable>(
  timeout seconds: Double,
  _ block: @Sendable @escaping () async -> T
) -> T? {
  let semaphore = DispatchSemaphore(value: 0)
  nonisolated(unsafe) var result: T?
  Task {
    result = await block()
    semaphore.signal()
  }
  guard semaphore.wait(timeout: .now() + seconds) == .success else { return nil }
  return result
}

func runSyncOptionalResult<T: Sendable>(
  timeout seconds: Double,
  _ block: @Sendable @escaping () async -> T?
) -> T? {
  guard let result = runSyncResult(timeout: seconds, block) else { return nil }
  return result
}

/// Ensures the CLI is executed from an app bundle installed under `/Applications`.
///
/// Login registration requires the signed installed bundle.
func requireApplicationsBundleOrExit() {
  let path = Bundle.main.bundlePath
  guard path.hasPrefix("/Applications/") else {
    CLIOutput.error("This command must be run from the /Applications-installed app bundle.")
    CLIOutput.diagnostic("Current bundle: \(path)")
    CLIOutput.diagnostic(
      "  Fix: run: " +
        "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver " +
        "--headless <command>"
    )
    exit(1)
  }
}

/// Ensures the app bundle is validly signed.
///
/// This catches the common dev failure mode where a `.dext` is copied into the app bundle
/// after signing, which breaks the signature and causes application service registration to fail.
func requireValidBundleSignatureOrExit(action: String) {
  let appPath = Bundle.main.bundlePath
  let result: BoundedProcessResult
  do {
    result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
      arguments: ["--verify", "--deep", "--strict", "--verbose=2", appPath],
      timeoutSeconds: 15,
      maximumOutputBytes: 262_144
    )
  } catch {
    CLIOutput.error(
      "\(action) failed: could not run codesign verification: " +
        "\(error.localizedDescription)"
    )
    exit(1)
  }
  if result.timedOut {
    CLIOutput.error("\(action) failed: codesign verification timed out after 15 seconds.")
    exit(1)
  }
  let out = result.output
  guard result.terminationStatus == 0 else {
    if out.contains("a sealed resource is missing or invalid") {
      CLIOutput.error(
        "\(action) failed: this app bundle's signature is INVALID " +
          "(modified after signing)."
      )
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic("Fix:")
      CLIOutput.diagnostic("  1) Run: ./scripts/ojd rebuild-fast dev")
      CLIOutput.diagnostic(
        "  2) Then re-run: " +
          "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver " +
          "--headless \(action.lowercased())"
      )
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic("Diagnostic command:")
      CLIOutput.diagnostic("  /usr/bin/codesign --verify --deep --strict --verbose=2 \(appPath)")
      exit(1)
    }
    let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
    CLIOutput.error("\(action) failed: app signature verification failed:")
    if trimmed.isEmpty {
      CLIOutput.diagnostic("  (no output)")
    } else {
      CLIOutput.diagnostic(trimmed)
    }
    exit(1)
  }
}
