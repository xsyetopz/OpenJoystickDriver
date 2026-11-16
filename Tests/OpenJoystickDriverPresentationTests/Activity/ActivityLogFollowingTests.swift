import AppKit
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityLogFollowingTests {
  @Test
  func logIsFollowedOnlyWhileVisibleWindowShowsIt() {
    for area in MainWindowArea.allCases {
      for mode in ActivityMode.allCases {
        let expected = area == .activity && mode == .log
        #expect(
          ActivityLogFollowing.shouldFollow(windowVisible: true, area: area, mode: mode)
            == expected
        )
        #expect(
          !ActivityLogFollowing.shouldFollow(windowVisible: false, area: area, mode: mode)
        )
      }
    }
  }
}

@Suite
@MainActor
struct ActivityLogRowsTests {
  nonisolated private static func quietSource() -> ActivityLogSource {
    ActivityLogSource(
      tail: { stream, _ in
        ApplicationServiceLogSnapshot(
          stream: stream,
          path: "/tmp/log",
          exists: true,
          fileSizeBytes: 0,
          lines: [],
          truncated: false
        )
      },
      follow: { _, _ in AsyncStream { $0.finish() } }
    )
  }

  private static func line(
    _ text: String,
    _ stream: ApplicationServiceLogStream = .standardOutput
  ) -> ApplicationServiceLogLine {
    ApplicationServiceLogLine(stream: stream, text: text)
  }

  @Test
  func appendedLineJoinsRowsOnlyWhenFilterAndSearchShowIt() {
    let model = ActivityLogModel(source: Self.quietSource())
    model.filter = .errors
    model.searchText = "disk"

    model.append(Self.line("disk full", .standardError))
    model.append(Self.line("disk ok", .standardOutput))
    model.append(Self.line("network down", .standardError))
    model.append(Self.line("disk slow", .standardError))

    #expect(model.rows.map(\.text) == ["disk slow", "disk full"])
    #expect(model.entries.count == 4)
  }

  @Test
  func changingFilterRebuildsRowsFromAllEntries() {
    let model = ActivityLogModel(source: Self.quietSource())
    model.append(Self.line("a"))
    model.append(Self.line("b", .standardError))
    model.filter = .output
    #expect(model.rows.map(\.text) == ["a"])

    model.filter = .all

    #expect(model.rows.map(\.text) == ["b", "a"])
  }

  @Test
  func trimmingDropsOldestEntriesInBatchesAndKeepsNewest() {
    let model = ActivityLogModel(source: Self.quietSource(), retainedEntries: 20)

    for number in 0..<23 { model.append(Self.line("line \(number)")) }

    // The batch is a tenth: nothing drops until 23 entries pile up past 20 + 2.
    #expect(model.entries.count == 20)
    #expect(model.entries.first?.text == "line 3")
    #expect(model.entries.last?.text == "line 22")
    #expect(model.rows.first?.text == "line 22")
    #expect(model.rows.last?.text == "line 3")
  }

  @Test
  func followingStartsOnceAndStopsWhenHidden() {
    let model = ActivityLogModel(source: Self.quietSource())

    model.setFollowing(true)
    #expect(model.isFollowing)
    model.setFollowing(true)
    #expect(model.isFollowing)
    model.setFollowing(false)
    #expect(!model.isFollowing)
  }
}

extension ActivityLogFollowingTests {
  @Test
  @MainActor
  func windowFollowsLogOnlyWhileActivityIsSelected() throws {
    let (controller, cleanup) = try MainWindowController.offScreen()
    defer { cleanup() }
    let window = try #require(controller.window)
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    let log = controller.screens.activity.log

    controller.navigation.requestArea(.activity)
    #expect(log.isFollowing)
    controller.navigation.requestArea(.controllers)
    #expect(!log.isFollowing)
  }
}
