import Foundation
package import Testing

/// The socket paths one test created through ``temporarySocketPath()``.
package final class TemporarySocketPaths: @unchecked Sendable {
  @TaskLocal
  static var current: TemporarySocketPaths?

  private let lock = NSLock()
  private var paths: [String] = []

  func add(_ path: String) { lock.withLock { paths.append(path) } }

  /// Removes the file of each registered path; a path that never got a file is skipped.
  func removeFiles() {
    let created = lock.withLock { paths }
    for path in created where unsafe unlink(path) != 0 && errno != ENOENT {
      Issue.record(unsafe "Removing \(path) failed: \(String(cString: strerror(errno)))")
    }
  }
}

/// A unique path for a test's service socket, removed when the test ends.
///
/// The test or its suite must carry ``Trait/removingTemporarySockets``; a call outside that scope
/// stops the process, because the file it would leave behind outlives the run.
package func temporarySocketPath() -> String {
  guard let registry = TemporarySocketPaths.current else {
    preconditionFailure("temporarySocketPath() needs the .removingTemporarySockets trait")
  }
  let path = unregisteredSocketPath()
  registry.add(path)
  return path
}

/// A unique socket path whose owner removes the file itself, such as a server that unlinks it
/// when it stops.
package func unregisteredSocketPath() -> String {
  "/tmp/com.openjoystickdriver.test.\(UUID().uuidString).rpc"
}

/// Removes the socket paths a test registered with ``temporarySocketPath()`` after the test ends,
/// whether it passed or threw.
package struct RemovingTemporarySockets: SuiteTrait, TestTrait, TestScoping {
  package var isRecursive: Bool { true }

  @concurrent
  package func provideScope(
    for test: Test,
    testCase _: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    // A suite only contains tests; each test, and each case of a parameterized one, has its own
    // registry so its files go as soon as it ends.
    guard !test.isSuite else {
      try await function()
      return
    }
    let registry = TemporarySocketPaths()
    defer { registry.removeFiles() }
    try await TemporarySocketPaths.$current.withValue(registry) { try await function() }
  }
}

extension Trait where Self == RemovingTemporarySockets {
  /// Removes the files of the test's ``temporarySocketPath()`` paths when the test ends.
  package static var removingTemporarySockets: Self { Self() }
}
