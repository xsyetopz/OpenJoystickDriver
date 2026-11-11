import AppKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainMenuInterfaceLevelTests {
  private func levelItems() throws -> [(InterfaceLevel, MainMenuItem)] {
    try InterfaceLevel.allCases.map {
      ($0, try #require(MainMenuModel.item(for: .setInterfaceLevel($0))))
    }
  }

  @Test
  func theViewMenuHasSimpleThenAdvanced() throws {
    let view = try #require(MainMenuModel.sections.first { $0.id == "view" })
    let actions = view.items.map(\.action)
    let simple = try #require(actions.firstIndex(of: .setInterfaceLevel(.simple)))
    #expect(actions[simple + 1] == .setInterfaceLevel(.advanced))
    #expect(
      try levelItems().map(\.1.titleKey)
        == ["ui.menu.view.interfaceSimple", "ui.menu.view.interfaceAdvanced"]
    )
  }

  @Test
  func theItemsAreEnabledAndPointToTheGeneralPane() throws {
    for (_, item) in try levelItems() {
      #expect(MainMenuModel.isEnabled(item, state: MainMenuState()))
      #expect(item.guiCounterpart == .settingsPane(.general))
      #expect(item.keyEquivalent.isEmpty)
    }
  }

  @Test(arguments: InterfaceLevel.allCases)
  @MainActor
  func theCheckmarkFollowsTheLevel(level: InterfaceLevel) throws {
    var state = MainMenuState()
    state.interfaceLevel = level
    for (itemLevel, item) in try levelItems() {
      #expect(MainMenuModel.isChecked(item, state: state) == (itemLevel == level))
      let mark = MainMenuRenderer.checkmark(of: item, state: state)
      #expect(mark == (itemLevel == level ? .on : .off))
    }
  }

  @Test
  func theDefaultStateChecksSimple() throws {
    let checked = try levelItems().filter { MainMenuModel.isChecked($0.1, state: MainMenuState()) }
    #expect(checked.map(\.0) == [.simple])
  }

  @Test
  func noOtherItemShowsACheckmark() {
    var state = MainMenuState()
    state.interfaceLevel = .advanced
    for item in MainMenuModel.allItems {
      if case .setInterfaceLevel = item.action { continue }
      #expect(!MainMenuModel.isChecked(item, state: state), "\(item.id)")
    }
  }
}
