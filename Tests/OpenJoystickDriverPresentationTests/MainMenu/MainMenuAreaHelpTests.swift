import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainMenuAreaHelpTests {
  private static let wiki = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // MainMenu
    .deletingLastPathComponent()  // OpenJoystickDriverPresentationTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository
    .appendingPathComponent("wiki", isDirectory: true)

  @Test
  func everyAreaMapsToWikiPageExists() {
    for area in MainWindowArea.allCases {
      let file = Self.wiki.appendingPathComponent("\(area.wikiPage).md")
      #expect(
        FileManager.default.fileExists(atPath: file.path),
        "\(area) maps to \(area.wikiPage), which is not in wiki/"
      )
    }
  }

  @Test
  func everyAreaOpensItsPageOnProjectWiki() {
    for area in MainWindowArea.allCases {
      #expect(
        area.wikiURL.absoluteString
          == "https://github.com/xsyetopz/OpenJoystickDriver/wiki/\(area.wikiPage)"
      )
    }
  }

  @Test
  func helpMenuHoldsHelpForThisArea() throws {
    let help = try #require(MainMenuModel.sections.first { $0.id == "help" })
    let item = try #require(help.items.first { $0.action == .openAreaHelp })
    #expect(item.titleKey == "ui.menu.help.helpForThisArea")
    #expect(item.guiCounterpart == .externalLink)
    #expect(MainMenuModel.isEnabled(item, state: MainMenuState()))
  }
}
