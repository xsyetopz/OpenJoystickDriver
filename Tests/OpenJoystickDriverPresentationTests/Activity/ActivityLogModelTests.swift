import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityLogFilterTests {
  private let entries = [
    ActivityLogEntry(id: 0, stream: .standardOutput, text: "Service started"),
    ActivityLogEntry(id: 1, stream: .standardError, text: "Could not open controller"),
    ActivityLogEntry(id: 2, stream: .standardOutput, text: "Controller connected"),
  ]

  @Test
  func eachFilterKeepsItsStreams() {
    #expect(ActivityLogFilter.all.rows(in: entries, matching: "").map(\.id) == [0, 1, 2])
    #expect(ActivityLogFilter.output.rows(in: entries, matching: "").map(\.id) == [0, 2])
    #expect(ActivityLogFilter.errors.rows(in: entries, matching: "").map(\.id) == [1])
  }

  @Test
  func searchIgnoresCaseAndSurroundingWhitespace() {
    #expect(ActivityLogFilter.all.rows(in: entries, matching: "  CONTROLLER ").map(\.id) == [1, 2])
    #expect(ActivityLogFilter.output.rows(in: entries, matching: "controller").map(\.id) == [2])
    #expect(ActivityLogFilter.all.rows(in: entries, matching: "   ").map(\.id) == [0, 1, 2])
    #expect(ActivityLogFilter.all.rows(in: entries, matching: "absent").isEmpty)
  }

  @Test
  func filterSegmentsFollowToolbarOrder() {
    #expect(ActivityLogFilter.allCases.map(\.rawValue) == [0, 1, 2])
    #expect(
      ActivityLogFilter.allCases.map(\.titleKey) == [
        "ui.console.all", "ui.console.output", "ui.console.errors",
      ]
    )
  }

  @Test
  func lineCountChoicesStayInsideServiceRange() {
    #expect(
      ActivityLogLineCount.choices.allSatisfy {
        ApplicationServiceLogService.linesRange.contains($0)
      }
    )
    #expect(ActivityLogLineCount.choices.contains(ActivityLogLineCount.initial))
  }
}

@Suite
@MainActor
struct ActivityLogModelTests {
  nonisolated private static func snapshot(
    _ stream: ApplicationServiceLogStream,
    lines: [String],
    size: UInt64 = 10
  ) -> ApplicationServiceLogSnapshot {
    ApplicationServiceLogSnapshot(
      stream: stream,
      path: "/tmp/\(stream.rawValue).log",
      exists: true,
      fileSizeBytes: size,
      lines: lines,
      truncated: false
    )
  }

  @Test
  func startReadsRequestedLineCountOfBothStreams() {
    let requested = Locked<[Int]>([])
    let model = ActivityLogModel(
      source: ActivityLogSource(
        tail: { stream, count in
          requested.withLock { $0.append(count) }
          return Self.snapshot(stream, lines: ["\(stream.rawValue) line"])
        },
        follow: { _, _ in AsyncStream { $0.finish() } }
      )
    )

    model.start()
    model.setLineCount(1_000)

    #expect(requested.withLock { $0 } == [500, 500, 1_000, 1_000])
    #expect(model.entries.map(\.text) == ["StandardOutput line", "StandardError line"])
    #expect(model.loadFailure == nil)
    model.stop()
  }

  @Test
  func followedLinesAreAppendedAfterTailFromTailsEnd() async {
    let offsets = Locked<[UInt64]>([])
    let model = ActivityLogModel(
      source: ActivityLogSource(
        tail: { stream, _ in Self.snapshot(stream, lines: [], size: 42) },
        follow: { stream, offset in
          offsets.withLock { $0.append(offset) }
          return AsyncStream { continuation in
            if stream == .standardError {
              continuation.yield(ApplicationServiceLogLine(stream: stream, text: "late"))
            }
            continuation.finish()
          }
        }
      )
    )

    model.start()
    for _ in 0..<100 where model.entries.isEmpty { await Task.yield() }

    #expect(offsets.withLock { $0 } == [42, 42])
    #expect(model.entries.map(\.text) == ["late"])
    #expect(model.entries.map(\.stream) == [.standardError])
    model.stop()
  }

  @Test
  func unreadableLogShowsFailureAndNoEntries() {
    struct Unreadable: LocalizedError { var errorDescription: String? { "denied" } }
    let model = ActivityLogModel(
      source: ActivityLogSource(
        tail: { _, _ in throw Unreadable() },
        follow: { _, _ in AsyncStream { $0.finish() } }
      )
    )

    model.start()

    #expect(model.loadFailure == "denied")
    #expect(model.entries.isEmpty)
  }

  @Test
  func copyTextHoldsShownLinesOnly() {
    let model = ActivityLogModel(
      source: ActivityLogSource(
        tail: { stream, _ in
          Self.snapshot(stream, lines: ["\(stream.rawValue) a", "\(stream.rawValue) b"])
        },
        follow: { _, _ in AsyncStream { $0.finish() } }
      )
    )
    model.start()
    model.filter = .errors
    model.searchText = "b"

    #expect(model.copyText == "StandardError b")
    model.stop()
  }
}
