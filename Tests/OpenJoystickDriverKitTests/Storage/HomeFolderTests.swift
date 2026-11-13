import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HomeFolderTests {
  @Test
  func textShowsHomeFolderAsTilde() {
    let text = """
      == standardOutput: /Users/me/Library/Logs/ojd.log ==
      opened /Users/me
      kept /Users/meow/file and "/Users/me/a b"
      """
    #expect(
      HomeFolder.redacting(text, home: "/Users/me/")
        == """
        == standardOutput: ~/Library/Logs/ojd.log ==
        opened ~
        kept /Users/meow/file and "~/a b"
        """
    )
  }

  @Test
  func currentUsersHomeFolderIsDefault() {
    let home = MacOSDataDirectory().url(for: .home).path
    #expect(HomeFolder.redacting("\(home)/Library/x") == "~/Library/x")
    #expect(HomeFolder.redacting("/elsewhere/x") == "/elsewhere/x")
  }

  @Test
  func exportedLogsShowHomeFolderAsTilde() {
    let snapshot = ApplicationServiceLogSnapshot(
      stream: .standardOutput,
      path: "/Users/me/Library/Logs/ojd.log",
      exists: true,
      fileSizeBytes: 1,
      lines: ["opened /Users/me/x"],
      truncated: false
    )
    let text = ApplicationServiceLogService.exportText([snapshot], home: "/Users/me")
    #expect(text.contains("~/Library/Logs/ojd.log"))
    #expect(text.contains("opened ~/x"))
    #expect(!text.contains("/Users/me"))
  }
}
