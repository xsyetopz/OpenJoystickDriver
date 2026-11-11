import AppKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct MainMenuModelTests {
  private func section(_ id: String) throws -> MainMenuSection {
    try #require(MainMenuModel.sections.first { $0.id == id })
  }

  @Test
  func menuSetIsTheFixedEight() {
    #expect(
      MainMenuModel.sections.map(\.id)
        == ["app", "file", "edit", "view", "controller", "profile", "window", "help"]
    )
  }

  @Test
  func itemIDsAreUnique() {
    let ids = MainMenuModel.allItems.map(\.id)
    #expect(Set(ids).count == ids.count)
  }

  @Test
  func everyItemHasATitleAnActionAndAGUICounterpart() {
    for item in MainMenuModel.allItems {
      #expect(!item.titleKey.isEmpty, "\(item.id) has no title key")
      #expect(MainMenuModel.item(for: item.action)?.id == item.id, "\(item.id) action is shared")
    }
  }

  @Test
  @MainActor
  func everyActionIsRoutedToExactlyOneHandler() {
    // A responder selector means AppKit performs it; otherwise the coordinator does.
    for item in MainMenuModel.allItems {
      let responder = MainMenuRenderer.responderSelector(for: item.action) != nil
      let isSystem = item.enabled == .responderChain
      if item.action == .services { continue }
      #expect(responder == isSystem, "\(item.id) routing and enabled rule disagree")
    }
  }

  @Test
  func guiCounterpartsFollowTheCoverageMatrix() throws {
    func counterpart(_ action: MainMenuAction) throws -> MainMenuGUICounterpart {
      try #require(MainMenuModel.item(for: action)).guiCounterpart
    }
    #expect(try counterpart(.importProfile) == .area(.profiles))
    #expect(try counterpart(.exportProfile) == .area(.profiles))
    #expect(try counterpart(.activateProfile) == .area(.profiles))
    #expect(try counterpart(.deactivateProfile) == .area(.profiles))
    #expect(try counterpart(.installRecordOrMod) == .area(.library))
    #expect(try counterpart(.saveSupportReport) == .area(.activity))
    #expect(try counterpart(.saveActivityLog) == .area(.activity))
    #expect(try counterpart(.suspendOrResumeController) == .area(.controllers))
    #expect(try counterpart(.testInput) == .area(.controllers))
    #expect(try counterpart(.disconnectWirelessLink) == .area(.controllers))
    #expect(try counterpart(.showControllerInWindow) == .area(.controllers))
    #expect(try counterpart(.settings) == .settingsPane(.general))
    #expect(try counterpart(.toggleSidebar) == .sidebarToolbarButton)
  }

  @Test
  func toolbarItemUsesOptionCommandTAndNamesWhatItWillDo() throws {
    let item = try #require(MainMenuModel.item(for: .toggleToolbar))
    #expect(item.keyEquivalent == "t")
    #expect(item.modifiers == [.command, .option])
    var state = MainMenuState()
    state.isToolbarVisible = true
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.hideToolbar")
    state.isToolbarVisible = false
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.showToolbar")
    let actions = try section("view").items.map(\.action)
    #expect(actions.suffix(3) == [.toggleToolbar, .toggleSidebar, .toggleFullScreen])
  }

  @Test
  func sidebarItemUsesControlCommandSAndNamesWhatItWillDo() throws {
    let item = try #require(MainMenuModel.item(for: .toggleSidebar))
    #expect(item.keyEquivalent == "s")
    #expect(item.modifiers == [.command, .control])
    var state = MainMenuState()
    state.isSidebarVisible = true
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.hideSidebar")
    state.isSidebarVisible = false
    #expect(MainMenuModel.titleKey(of: item, state: state) == "ui.menu.view.showSidebar")
  }

  @Test
  func profileAndInstallItemsPerformFlows() throws {
    for action in [
      MainMenuAction.importProfile, .exportProfile, .activateProfile, .installRecordOrMod,
    ] {
      #expect(action.performsFlow)
      #expect(MainMenuModel.item(for: action) != nil)
    }
    #expect(!MainMenuAction.showArea(.profiles).performsFlow)
    let export = try #require(MainMenuModel.item(for: .exportProfile))
    var exportState = MainMenuState(hasMainWindow: true)
    #expect(!MainMenuModel.isEnabled(export, state: exportState))
    exportState.hasSelectedProfile = true
    #expect(MainMenuModel.isEnabled(export, state: exportState))
    let activate = try #require(MainMenuModel.item(for: .activateProfile))
    // The submenu parent stays available so people can open it and see there are no profiles.
    #expect(MainMenuModel.isEnabled(activate, state: MainMenuState()))
    // Its one disabled row claims no profile exists only after the service reported the list.
    #expect(
      MainMenuModel.emptyActivateProfileTitleKey(profileListRead: true) == "ui.menu.profile.none"
    )
    #expect(
      MainMenuModel.emptyActivateProfileTitleKey(profileListRead: false)
        == "ui.menu.profile.unavailable"
    )
    #expect(
      MainMenuModel.emptyDeactivateProfileTitleKey(profileListRead: true)
        == "ui.menu.profile.noneActive"
    )
    #expect(
      MainMenuModel.emptyDeactivateProfileTitleKey(profileListRead: false)
        == "ui.menu.profile.unavailable"
    )
  }

  @Test
  func appMenuHoldsTheStandardItems() throws {
    let actions = try section("app").items.map(\.action)
    #expect(actions == [.about, .settings, .services, .hide, .hideOthers, .showAll, .quit])
    let settings = try #require(MainMenuModel.item(for: .settings))
    #expect(settings.keyEquivalent == ",")
    #expect(settings.modifiers == [.command])
  }

  @Test
  func fileMenuHoldsTheCommandsAndTheStandardClose() throws {
    // The File menu order: items that open a file, then Close, then items that write a file.
    let file = try section("file")
    #expect(
      file.items.map(\.action) == [
        .importProfile, .installRecordOrMod, .toolbar(.validateLibraryItem),
        .toolbar(.testLibraryRecord), .toolbar(.removeLibraryItem), .toolbar(.grantProgram),
        .toolbar(.createToken), .close, .exportProfile, .saveSupportReport, .saveActivityLog,
        .toolbar(.showActivityLogInFinder),
      ]
    )
    let groups = file.entries.split(separator: .separator).map { $0.compactMap(\.item?.action) }
    #expect(
      groups == [
        [.importProfile, .installRecordOrMod],
        [.toolbar(.validateLibraryItem), .toolbar(.testLibraryRecord), .toolbar(.removeLibraryItem)],
        [.toolbar(.grantProgram), .toolbar(.createToken)], [.close],
        [.exportProfile, .saveSupportReport, .saveActivityLog, .toolbar(.showActivityLogInFinder)],
      ]
    )
    let close = try #require(MainMenuModel.item(for: .close))
    #expect(close.keyEquivalent == "w")
    #expect(close.modifiers == [.command])
    #expect(close.enabled == .responderChain)
  }

  @Test
  func editMenuHoldsTheStandardItemsInOrder() throws {
    #expect(
      try section("edit").items.map(\.action) == [
        .undo, .redo, .cut, .copy, .toolbar(.copyActivityLog), .paste, .delete, .selectAll,
        .find,
      ]
    )
    #expect(try #require(MainMenuModel.item(for: .delete)).keyEquivalent.isEmpty)
  }

  @Test
  func menusAppearInTheStandardOrder() {
    #expect(
      MainMenuModel.sections.map(\.id) == [
        "app", "file", "edit", "view", "controller", "profile", "window", "help",
      ]
    )
  }

  @Test
  func keyEquivalentsAreTheStandardOnesPlusTheAreaDigits() {
    struct Shortcut: Hashable {
      let key: String
      let modifiers: MainMenuModifiers
    }
    let shortcuts = MainMenuModel.allItems.filter { !$0.keyEquivalent.isEmpty }
    let keys = shortcuts.map { Shortcut(key: $0.keyEquivalent, modifiers: $0.modifiers) }
    #expect(Set(keys).count == keys.count, "two items share a key equivalent")
    // Shortcuts that the system or Apple's standard keyboard shortcuts give another action.
    let reserved: Set<Shortcut> = [
      Shortcut(key: "n", modifiers: [.command]), Shortcut(key: "p", modifiers: [.command]),
      Shortcut(key: "p", modifiers: [.command, .shift]),
      Shortcut(key: "s", modifiers: [.command]), Shortcut(key: "s", modifiers: [.command, .shift]),
      Shortcut(key: "e", modifiers: [.command]), Shortcut(key: "e", modifiers: [.command, .shift]),
      Shortcut(key: "f", modifiers: [.command, .option]),
      Shortcut(key: "g", modifiers: [.command]), Shortcut(key: "i", modifiers: [.command]),
      Shortcut(key: "t", modifiers: [.command]),
      Shortcut(key: "d", modifiers: [.command, .option]),
      Shortcut(key: "d", modifiers: [.command, .control]),
      Shortcut(key: "q", modifiers: [.command, .shift]),
      Shortcut(key: "q", modifiers: [.command, .control]),
      Shortcut(key: "3", modifiers: [.command, .shift]),
      Shortcut(key: "4", modifiers: [.command, .shift]),
      Shortcut(key: " ", modifiers: [.command]),
      Shortcut(key: " ", modifiers: [.command, .control]),
      Shortcut(key: "\t", modifiers: [.command]), Shortcut(key: "`", modifiers: [.command]),
      Shortcut(key: ".", modifiers: [.command]), Shortcut(key: "?", modifiers: [.command]),
    ]
    for item in shortcuts {
      let shortcut = Shortcut(key: item.keyEquivalent, modifiers: item.modifiers)
      #expect(!reserved.contains(shortcut), "\(item.id) takes a reserved shortcut")
      #expect(item.modifiers.contains(.command), "\(item.id) has no Command modifier")
    }
    // Every key equivalent: the standard shortcut of a standard item, Command-O for the item
    // that opens a file, Control-Command-S for Show Sidebar as AppKit's own menu has it, and
    // the five area digits.
    var expected: [MainMenuAction: Shortcut] = [
      .settings: Shortcut(key: ",", modifiers: [.command]),
      .hide: Shortcut(key: "h", modifiers: [.command]),
      .hideOthers: Shortcut(key: "h", modifiers: [.command, .option]),
      .quit: Shortcut(key: "q", modifiers: [.command]),
      .importProfile: Shortcut(key: "o", modifiers: [.command]),
      .close: Shortcut(key: "w", modifiers: [.command]),
      .undo: Shortcut(key: "z", modifiers: [.command]),
      .redo: Shortcut(key: "z", modifiers: [.command, .shift]),
      .cut: Shortcut(key: "x", modifiers: [.command]),
      .copy: Shortcut(key: "c", modifiers: [.command]),
      .paste: Shortcut(key: "v", modifiers: [.command]),
      .selectAll: Shortcut(key: "a", modifiers: [.command]),
      .find: Shortcut(key: "f", modifiers: [.command]),
      .toggleToolbar: Shortcut(key: "t", modifiers: [.command, .option]),
      .toggleSidebar: Shortcut(key: "s", modifiers: [.command, .control]),
      .toggleFullScreen: Shortcut(key: "f", modifiers: [.command, .control]),
      .minimize: Shortcut(key: "m", modifiers: [.command]),
    ]
    for area in MainWindowArea.allCases {
      expected[.showArea(area)] = Shortcut(key: area.keyEquivalent, modifiers: [.command])
    }
    let actual = Dictionary(
      uniqueKeysWithValues: shortcuts.map {
        ($0.action, Shortcut(key: $0.keyEquivalent, modifiers: $0.modifiers))
      }
    )
    #expect(actual == expected)
  }

  @Test
  func titlesUseTitleStyleCapitalizationAndEllipsisOnlyWhenMoreInputFollows() {
    let small: Set<String> = ["and", "or", "but", "in", "of", "to", "on", "for"]
    let articles: Set<String> = ["a", "an", "the"]
    let moreInput: Set<MainMenuAction> = [
      .settings, .importProfile, .exportProfile, .installRecordOrMod, .saveSupportReport,
      .saveActivityLog, .explainErrorCode, .reportProblem, .toolbar(.validateLibraryItem),
      .toolbar(.testLibraryRecord), .toolbar(.grantProgram), .toolbar(.createToken),
    ]
    func checkTitleStyle(_ key: String) {
      let title = OJDLocalized.string(key)
      let words = title.replacingOccurrences(of: "...", with: "").split(separator: " ")
      for (index, word) in words.enumerated() {
        #expect(!articles.contains(word.lowercased()), "\(key) holds an article: \(title)")
        let isEdge = index == 0 || index == words.count - 1
        let expected = isEdge || !small.contains(String(word))
        let isCapitalized = word.first.map { !$0.isLetter || $0.isUppercase } ?? true
        if expected { #expect(isCapitalized, "\(key) is not title-style: \(title)") }
      }
    }
    // The disabled rows that say why a menu has nothing to act on are menu items too.
    for key in [
      MainMenuModel.noControllerTitleKey, "ui.menu.controller.noneSelected",
      MainMenuModel.noProfilesTitleKey, MainMenuModel.profilesUnavailableTitleKey,
      MainMenuModel.noActiveProfileTitleKey,
    ] { checkTitleStyle(key) }
    for item in MainMenuModel.allItems where item.action != .controllerTarget {
      // A command of a toolbar action keeps the toolbar item's title, which is in sentence style.
      let isToolbarTitle = MainWindowToolbarAction.allCases.contains {
        $0.labelKey == item.titleKey
      }
      for key in [item.titleKey, item.alternateTitleKey].compactMap({ $0 }) where !isToolbarTitle {
        checkTitleStyle(key)
      }
      let title = OJDLocalized.string(item.titleKey)
      #expect(
        title.hasSuffix("...") == moreInput.contains(item.action),
        "\(item.titleKey) ellipsis does not match whether more input follows"
      )
    }
  }

  @Test
  func separatorsNeverLeadTrailOrRepeat() {
    for section in MainMenuModel.sections {
      let entries = section.entries
      #expect(entries.first != .separator, "\(section.id) starts with a separator")
      #expect(entries.last != .separator, "\(section.id) ends with a separator")
      for pair in zip(entries, entries.dropFirst()) {
        #expect(!(pair.0 == .separator && pair.1 == .separator), "\(section.id) repeats one")
      }
    }
  }

  @Test
  func fullScreenIsSeparatedFromTheShowHideItems() throws {
    let entries = try section("view").entries
    let index = try #require(entries.firstIndex { $0.item?.action == .toggleFullScreen })
    #expect(entries[index - 1] == .separator)
  }

  @Test
  func submenuParentsAndAreaOpeningItemsCarryNoEllipsis() throws {
    let withoutMoreInput: [MainMenuAction] = [
      .activateProfile, .testInput, .disconnectWirelessLink, .showActivityLog,
    ]
    for action in withoutMoreInput {
      let item = try #require(MainMenuModel.item(for: action))
      #expect(!OJDLocalized.string(item.titleKey).hasSuffix("..."), "\(item.titleKey)")
      #expect(!OJDLocalized.string(item.titleKey).hasSuffix("…"), "\(item.titleKey)")
    }
  }

  @Test
  func viewMenuHasFiveAreasWithCommandDigits() throws {
    let items = try section("view").items
    let areaItems = items.filter {
      if case .showArea = $0.action { return true }
      return false
    }
    #expect(areaItems.map(\.action) == MainWindowArea.allCases.map { .showArea($0) })
    #expect(areaItems.map(\.keyEquivalent) == ["1", "2", "3", "4", "5"])
    #expect(areaItems.allSatisfy { $0.modifiers == [.command] })
    #expect(areaItems.map(\.titleKey) == MainWindowArea.allCases.map(\.titleKey))
    #expect(MainMenuModel.item(for: .toggleFullScreen) != nil)
  }

  @Test
  func controllerAndProfileItemsAreDisabledNeverHidden() throws {
    let state = MainMenuState()
    for id in ["controller", "profile"] {
      for item in try section(id).items {
        // Activate Profile opens a submenu that lists profiles; it stays available.
        if item.action == .showControllerInWindow || item.action == .activateProfile { continue }
        // The profile commands of the toolbar act on the Profiles area, not on a controller.
        if case .toolbar = item.action { continue }
        #expect(!MainMenuModel.isEnabled(item, state: state), "\(item.id) enabled without target")
      }
    }
  }

  @Test
  func controllerItemsFollowTheControllerState() throws {
    let wired = MainMenuControllerState(
      id: "a",
      name: "A",
      isSuspended: false,
      isWireless: false,
      hasActiveProfile: false
    )
    var state = MainMenuState(
      controllers: [wired],
      selectedControllerID: "a",
      hasMainWindow: true
    )
    let disconnect = try #require(MainMenuModel.item(for: .disconnectWirelessLink))
    let deactivate = try #require(MainMenuModel.item(for: .deactivateProfile))
    let activate = try #require(MainMenuModel.item(for: .activateProfile))
    let suspend = try #require(MainMenuModel.item(for: .suspendOrResumeController))
    #expect(!MainMenuModel.isEnabled(disconnect, state: state))
    #expect(!MainMenuModel.isEnabled(deactivate, state: state))
    #expect(MainMenuModel.isEnabled(activate, state: state))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.suspend")

    state.controllers = [
      MainMenuControllerState(
        id: "a",
        name: "A",
        isSuspended: true,
        isWireless: true,
        hasActiveProfile: true
      )
    ]
    #expect(MainMenuModel.isEnabled(disconnect, state: state))
    #expect(MainMenuModel.isEnabled(deactivate, state: state))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.resume")

    state.selectedControllerID = nil
    #expect(!MainMenuModel.isEnabled(suspend, state: state))
  }

  @Test
  func controllerMenuActsOnTheSelectedOfTwoControllers() throws {
    let first = MainMenuControllerState(
      id: "a",
      name: "First",
      isSuspended: false,
      isWireless: false,
      hasActiveProfile: false
    )
    let second = MainMenuControllerState(
      id: "b",
      name: "Second",
      isSuspended: true,
      isWireless: true,
      hasActiveProfile: true
    )
    var state = MainMenuState(
      controllers: [first, second],
      selectedControllerID: "a",
      hasMainWindow: true
    )
    let suspend = try #require(MainMenuModel.item(for: .suspendOrResumeController))
    let disconnect = try #require(MainMenuModel.item(for: .disconnectWirelessLink))
    let deactivate = try #require(MainMenuModel.item(for: .deactivateProfile))
    #expect(state.controller == first)
    #expect(MainMenuModel.controllerTargetTitle(state: state) == .verbatim("First"))
    #expect(MainMenuModel.isEnabled(suspend, state: state))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.suspend")
    #expect(!MainMenuModel.isEnabled(disconnect, state: state))
    #expect(!MainMenuModel.isEnabled(deactivate, state: state))

    state.selectedControllerID = "b"
    #expect(state.controller == second)
    #expect(MainMenuModel.controllerTargetTitle(state: state) == .verbatim("Second"))
    #expect(MainMenuModel.titleKey(of: suspend, state: state) == "ui.menu.controller.resume")
    #expect(MainMenuModel.isEnabled(disconnect, state: state))
    #expect(MainMenuModel.isEnabled(deactivate, state: state))
  }

  @Test
  func controllerTargetRowSaysWhyTheMenuIsDisabled() throws {
    let target = try #require(MainMenuModel.item(for: .controllerTarget))
    var state = MainMenuState()
    #expect(
      MainMenuModel.controllerTargetTitle(state: state) == .key("ui.menu.controller.noneConnected")
    )
    #expect(!MainMenuModel.isEnabled(target, state: state))
    state.controllers = [
      MainMenuControllerState(
        id: "a",
        name: "A",
        isSuspended: false,
        isWireless: false,
        hasActiveProfile: false
      )
    ]
    state.selectedControllerID = "a"
    #expect(!MainMenuModel.isEnabled(target, state: state))
  }

  @Test
  func controllerTargetRowDistinguishesNoSelectionFromNoController() {
    var state = MainMenuState(
      controllers: [
        MainMenuControllerState(
          id: "a",
          name: "A",
          isSuspended: false,
          isWireless: false,
          hasActiveProfile: false
        )
      ]
    )
    #expect(
      MainMenuModel.controllerTargetTitle(state: state) == .key("ui.menu.controller.noneSelected")
    )
    state.selectedControllerID = "gone"
    #expect(state.controller == nil)
    #expect(
      MainMenuModel.controllerTargetTitle(state: state) == .key("ui.menu.controller.noneSelected")
    )
    state.controllers = []
    #expect(
      MainMenuModel.controllerTargetTitle(state: state) == .key("ui.menu.controller.noneConnected")
    )
  }

  @Test
  @MainActor
  func controllerTargetRowTextIsTheNameOrLocalizedText() {
    #expect(MainMenuRenderer.text(of: .verbatim("Pad")) == "Pad")
    for key in ["ui.menu.controller.noneConnected", "ui.menu.controller.noneSelected"] {
      let text = MainMenuRenderer.text(of: .key(key))
      #expect(!text.isEmpty && text != key, "\(key) has no text")
    }
  }

  @Test
  func theHelpMenuListsExplainErrorCodeAndReportProblemWithTheirCounterparts() throws {
    let help = try section("help")
    let explain = try #require(help.items.first { $0.action == .explainErrorCode })
    let report = try #require(help.items.first { $0.action == .reportProblem })
    #expect(explain.guiCounterpart == .area(.activity))
    #expect(report.guiCounterpart == .externalLink)
    #expect(!MainMenuModel.isEnabled(explain, state: MainMenuState()))
    #expect(MainMenuModel.isEnabled(explain, state: MainMenuState(hasMainWindow: true)))
    #expect(MainMenuModel.isEnabled(report, state: MainMenuState()))
  }

  @Test
  func theHelpMenuHoldsActivityLogExplainErrorCodeReportProblemAndProjectWebsite() throws {
    let help = try section("help")
    let titles = help.items.map { OJDLocalized.string($0.titleKey) }
    for title in [
      "Activity Log", "Explain Error Code...", "Report Problem...", "Project Website",
    ] {
      #expect(titles.contains(title), "\(title)")
    }
    for action in [
      MainMenuAction.showActivityLog, .explainErrorCode, .reportProblem, .openProjectWebsite,
    ] {
      #expect(help.items.contains { $0.action == action }, "\(action)")
    }
  }

  @Test
  func saveItemsDoNotNeedAWindow() throws {
    let state = MainMenuState()
    for action in [MainMenuAction.saveSupportReport, .saveActivityLog, .copySupportReport] {
      let item = try #require(MainMenuModel.item(for: action))
      #expect(MainMenuModel.isEnabled(item, state: state))
    }
  }
}

@Suite
struct MainMenuRoutingTests {
  @Test
  @MainActor
  func submenuParentsCarryNoAction() {
    for item in MainMenuModel.allItems {
      switch MainMenuRenderer.routing(for: item.action) {
      case .services, .profileSubmenu:
        #expect(item.action == .services || item.action == .activateProfile)
      case .activityChoices:
        #expect(item.action == .toolbar(.activityMode) || item.action == .toolbar(.activityFilter))
      case .responder, .coordinator:
        #expect(item.action != .services && item.action != .activateProfile)
      case .informational:
        #expect(item.action == .controllerTarget)
        #expect(item.enabled == .never)
      }
    }
    if case .profileSubmenu = MainMenuRenderer.routing(for: .activateProfile) {
    } else {
      Issue.record("Activate Profile is not routed as a submenu parent")
    }
  }
}

@Suite
struct MainMenuIdentifierTests {
  @Test
  func menuBarItemIdentifiersAreUniqueAndApartFromItemIDs() {
    let barIDs = MainMenuModel.sections.map {
      MainMenuModel.menuBarItemIdentifier(sectionID: $0.id)
    }
    #expect(Set(barIDs).count == barIDs.count)
    #expect(Set(barIDs).isDisjoint(with: MainMenuModel.allItems.map(\.id)))
    #expect(MainMenuModel.menuBarItemIdentifier(sectionID: "profile") == "menu.profile")
  }

  @Test
  @MainActor
  func identifyingAnItemSetsItsIdentifierAndItsAccessibilityIdentifier() {
    let item = NSMenuItem(title: "Activate Profile", action: nil, keyEquivalent: "")
    MainMenuRenderer.identify(item, as: "activateProfile")
    #expect(item.identifier?.rawValue == "activateProfile")
    #expect(item.accessibilityIdentifier() == "activateProfile")
  }
}
