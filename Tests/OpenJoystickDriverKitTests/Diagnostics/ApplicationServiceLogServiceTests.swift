import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ApplicationServiceLogServiceTests {
  @Test
  func missingLogReturnsEmptyTypedSnapshot() throws {
    let url = temporaryURL()
    let snapshot = try ApplicationServiceLogService.tail(
      url: url,
      stream: .standardError,
      maximumLines: 10,
      maximumBytes: 1_024
    )

    #expect(!snapshot.exists)
    #expect(snapshot.lines.isEmpty)
    #expect(snapshot.stream == .standardError)
    #expect(snapshot.path == url.path)
    #expect(!snapshot.truncated)
  }

  @Test
  func tailReturnsOnlyRequestedFinalLines() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("one\ntwo\nthree\nfour\n".utf8).write(to: url)

    let snapshot = try ApplicationServiceLogService.tail(
      url: url,
      stream: .standardOutput,
      maximumLines: 2,
      maximumBytes: 1_024
    )

    #expect(snapshot.exists)
    #expect(snapshot.lines == ["three", "four"])
    #expect(snapshot.truncated)
  }

  @Test
  func byteLimitDropsLeadingPartialLine() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("discard-this-line\nkeep-one\nkeep-two\n".utf8).write(to: url)

    let snapshot = try ApplicationServiceLogService.tail(
      url: url,
      stream: .standardOutput,
      maximumLines: 10,
      maximumBytes: 20
    )

    #expect(snapshot.lines == ["keep-one", "keep-two"])
    #expect(snapshot.truncated)
    #expect(snapshot.fileSizeBytes > 20)
  }

  private func temporaryURL() -> URL {
    MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-application service-log-\(UUID().uuidString)"
    )
  }
}

extension ApplicationServiceLogServiceTests {
  @Test
  func secondProcessCannotClaimSessionLogsWhileFirstHoldsThem() throws {
    let directory = temporaryURL()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try ApplicationServiceLogService.claimSessionLogs(in: directory)
    #expect(throws: (any Error).self) {
      try ApplicationServiceLogService.claimSessionLogs(in: directory)
    }
    close(first)
    close(try ApplicationServiceLogService.claimSessionLogs(in: directory))
  }
}
