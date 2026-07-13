import Foundation
import OpenJoystickDriverKit

/// Timeout for local service calls from CLI - keeps commands
/// responsive when application service is not running.
let applicationServiceCallTimeoutSeconds: Double = 0.5

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
/// Login registration and headless relaunch both require the signed installed bundle.
func requireApplicationsBundleOrExit() {
  let path = Bundle.main.bundlePath
  guard path.hasPrefix("/Applications/") else {
    print("ERROR: This command must be run from the /Applications-installed app bundle.")
    print("  Current bundle: \(path)")
    print(
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
    print(
      "ERROR: \(action) failed: could not run codesign verification: " +
        "\(error.localizedDescription)"
    )
    exit(1)
  }
  if result.timedOut {
    print("ERROR: \(action) failed: codesign verification timed out after 15 seconds.")
    exit(1)
  }
  let out = result.output
  guard result.terminationStatus == 0 else {
    if out.contains("a sealed resource is missing or invalid") {
      print(
        "ERROR: \(action) failed: this app bundle's signature is INVALID " +
          "(modified after signing)."
      )
      print("")
      print("Fix:")
      print("  1) Run: ./scripts/ojd rebuild-fast dev")
      print(
        "  2) Then re-run: " +
          "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver " +
          "--headless \(action.lowercased())"
      )
      print("")
      print("Diagnostic command:")
      print("  /usr/bin/codesign --verify --deep --strict --verbose=2 \(appPath)")
      exit(1)
    }
    let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
    print("ERROR: \(action) failed: app signature verification failed:")
    if trimmed.isEmpty {
      print("  (no output)")
    } else {
      print(trimmed)
    }
    exit(1)
  }
}
