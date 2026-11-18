import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// The status item menu has one top-level row per controller and at most two levels.
@Suite
struct StatusItemMenuTests {
  private static func controller(
    _ id: String,
    name: String = "Pad",
    isSuspended: Bool = false,
    isWireless: Bool = false,
    battery: String? = nil,
    profileInForce: String? = nil,
    profiles: [StatusItemState.Profile] = []
  ) -> StatusItemState.Controller {
    var controller = StatusItemState.Controller(
      id: id,
      name: name,
      isSuspended: isSuspended,
      isWireless: isWireless
    )
    controller.battery = battery
    controller.profileInForce = profileInForce
    controller.profiles = profiles
    return controller
  }

  private static func entries(
    _ controllers: [StatusItemState.Controller],
    problems: [StatusItemProblem] = [],
    profileListRead: Bool = true
  ) -> [StatusItemEntry] {
    StatusItemModel.entries(
      for: StatusItemState(
        problems: problems,
        controllers: controllers,
        profileListRead: profileListRead
      )
    )
  }

  private static func rows(_ entries: [StatusItemEntry]) -> [StatusItemEntry] {
    entries.filter { !$0.isSeparator }
  }

  private static func profile(_ name: String, active: Bool = false) -> StatusItemState.Profile {
    StatusItemState.Profile(id: UUID(), name: name, isActive: active)
  }

  @Test
  func oneControllerMenuHoldsItsRowOpenWindowSettingsAndQuitInOrder() {
    let menu = Self.rows(Self.entries([Self.controller("a")]))
    #expect(menu.map(\.id) == ["controller.a", "openWindow", "settings", "quit"])
    #expect(menu[1].title == .key("ui.extra.openWindow"))
    #expect(
      unsafe String(
        format: OJDLocalized.string("ui.extra.openWindow"),
        OJDLocalized.string("term.app.name")
      ) == "Open OpenJoystickDriver"
    )
    #expect(menu[2].title == .key("ui.menu.app.settings"))
    #expect(menu[3].title == .key("ui.menu.app.quit"))
  }

  @Test
  func eachConnectedControllerTopLevelRowWithOneSubmenu() {
    let menu = Self.rows(
      Self.entries([Self.controller("a", name: "One"), Self.controller("b", name: "Two")])
    )
    #expect(
      menu.map(\.id) == ["controller.a", "controller.b", "openWindow", "settings", "quit"]
    )
    for row in menu.prefix(2) { #expect(row.submenu != nil) }
    #expect(menu[0].title == .verbatim("One"))
    #expect(menu[1].title == .verbatim("Two"))
  }

  @Test
  func controllerRowShowsBatteryProfileInForceAndPausedState() {
    let menu = Self.rows(
      Self.entries([
        Self.controller("a", name: "Pad", battery: "80%", profileInForce: "Racing"),
        Self.controller("b", name: "Stick", isSuspended: true),
        Self.controller("c", name: "Wheel"),
      ])
    )
    #expect(menu[0].title == .verbatim("Pad"))
    #expect(menu[0].details == [.verbatim("80%"), .verbatim("Racing")])
    #expect(menu[1].details == [.key("ui.controllers.paused.value")])
    #expect(menu[2].details.isEmpty)
  }

  @Test
  @MainActor
  func profileInForceNamesAppThatSelectedIt() {
    let general = ApplicationServiceProfileInForce(name: "General", appID: nil)
    let forApp = ApplicationServiceProfileInForce(name: "Racing", appID: "com.example.game")
    let identity: (String) -> String = { $0 }
    let game: (String) -> String = { _ in "Game" }
    #expect(MenuBarViewModel.profileInForceText(general, appName: identity) == "General")
    #expect(
      MenuBarViewModel.profileInForceText(forApp, appName: game)
        == OJDLocalized.formatted("ui.menu.controller.profileForApp", "Racing", "Game")
    )
    #expect(MenuBarViewModel.profileInForceText(nil, appName: identity) == nil)
  }

  @Test
  func noControllerShowsOneUnavailableRowSaysSo() {
    let menu = Self.rows(Self.entries([]))
    #expect(menu.map(\.id) == ["controller.none", "openWindow", "settings", "quit"])
    #expect(menu[0].title == .key("ui.menu.controller.noneConnected"))
    #expect(!menu[0].isEnabled)
    #expect(menu[0].action == nil)
    #expect(menu[0].submenu == nil)
  }

  @Test
  func controllerSubmenuHoldsProfilesPauseTestInputShowInWindowAndDisconnectForWireless() throws {
    let wired = Self.rows(Self.entries([Self.controller("a")]))[0]
    #expect(
      Self.rows(try #require(wired.submenu)).map(\.id) == [
        "controller.a.profile.none", "controller.a.pause", "controller.a.testInput",
        "controller.a.showInWindow",
      ]
    )
    let wireless = Self.rows(Self.entries([Self.controller("a", isWireless: true)]))[0]
    let items = Self.rows(try #require(wireless.submenu))
    #expect(
      items.map(\.id) == [
        "controller.a.profile.none", "controller.a.pause", "controller.a.testInput",
        "controller.a.showInWindow", "controller.a.disconnectWireless",
      ]
    )
    #expect(items.last?.action == .disconnectWireless(sessionToken: "a"))
  }

  @Test
  func pausedControllerOffersResumeAndNoPause() throws {
    let menu = Self.entries([Self.controller("a", isSuspended: true)])
    let ids = try #require(menu.first { $0.id == "controller.a" }?.submenu).map(\.id)
    #expect(ids.contains("controller.a.resume"))
    #expect(!ids.contains("controller.a.pause"))
  }

  @Test
  func noItemOfControllerSubmenuOpensSubmenu() throws {
    let profiles = (0..<12).map { Self.profile("P\($0)") }
    let menu = Self.entries([
      Self.controller("a", isWireless: true, profiles: profiles), Self.controller("b"),
    ])
    for row in menu where row.id.hasPrefix("controller.") {
      for item in try #require(row.submenu) { #expect(item.submenu == nil, "\(item.id)") }
    }
    #expect(menu.filter { $0.submenu != nil }.count == 2)
  }

  @Test
  func oneCheckmarkedListChoosesProfile() throws {
    let active = Self.profile("A", active: true)
    let other = Self.profile("B")
    let menu = Self.entries([Self.controller("a", profiles: [active, other])])
    let submenu = try #require(menu.first { $0.id == "controller.a" }?.submenu)
    let list = submenu.filter { $0.id.hasPrefix("controller.a.profile.") }
    #expect(
      list.map(\.id) == [
        "controller.a.profile.\(active.id.uuidString)",
        "controller.a.profile.\(other.id.uuidString)", "controller.a.profile.none",
      ]
    )
    #expect(list.map(\.isChecked) == [true, false, false])
    #expect(list[0].action == nil)
    #expect(list[1].action == .activateProfile(other.id))
    #expect(list[2].title == .key("ui.extra.noProfile"))
    #expect(list[2].action == .deactivateProfile(active.id))
  }

  @Test
  func noProfileCheckedWhileNoProfileInForce() throws {
    let menu = Self.entries([Self.controller("a", profiles: [Self.profile("A")])])
    let submenu = try #require(menu.first { $0.id == "controller.a" }?.submenu)
    let none = try #require(submenu.first { $0.id == "controller.a.profile.none" })
    #expect(none.isChecked)
    #expect(none.action == nil)
  }

  @Test
  func moreThanTenProfilesShowTenAndMoreProfiles() throws {
    let profiles = (0..<11).map { Self.profile("P\($0)") }
    let menu = Self.entries([Self.controller("a", profiles: profiles)])
    let submenu = try #require(menu.first { $0.id == "controller.a" }?.submenu)
    let list = submenu.filter { $0.id.hasPrefix("controller.a.profile.") }
    #expect(list.count == 12)
    #expect(list.last?.id == "controller.a.profile.more")
    #expect(list.last?.title == .key("ui.extra.moreProfiles"))
    #expect(list.last?.action == .showArea(.profiles))
    let ten = Self.entries([Self.controller("a", profiles: Array(profiles.prefix(10)))])
    let tenItems = try #require(ten.first { $0.id == "controller.a" }?.submenu)
    #expect(!tenItems.contains { $0.id == "controller.a.profile.more" })
  }

  @Test
  func menuHoldsNoHelpCommandsNoStatusLineAndNoProfileSubmenus() {
    func all(_ entries: [StatusItemEntry]) -> [StatusItemEntry] {
      entries.flatMap { [$0] + all($0.submenu ?? []) }
    }
    let menu = all(
      Self.entries(
        [Self.controller("a", isWireless: true)],
        problems: [.missingPermission(.inputRead), .service(.stopped)]
      )
    )
    let allowed: Set<String> = [
      "ui.banner.service.title", "ui.extra.openWindow", "ui.menu.app.settings",
      "ui.menu.app.quit",
      "ui.extra.resume", "ui.extra.pause", "ui.extra.disconnectWireless", "ui.extra.testInput",
      "ui.extra.showInWindow", "ui.extra.noProfile", "ui.extra.moreProfiles",
      MainMenuModel.noControllerTitleKey,
    ]
    for entry in menu {
      if case .key(let key) = entry.title { #expect(allowed.contains(key), "\(entry.id)") }
      #expect(entry.id != "status")
      #expect(entry.action != .showArea(.activity))
    }
  }
}
