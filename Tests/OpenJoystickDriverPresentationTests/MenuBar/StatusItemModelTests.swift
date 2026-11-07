import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct StatusItemModelTests {
  private static let pad = StatusItemState.Controller(
    id: "pad-a",
    name: "Pad",
    isSuspended: false,
    isWireless: true
  )

  private static func state(
    controllers: [StatusItemState.Controller] = [],
    profiles: [StatusItemState.Profile] = [],
    needsAccess: Bool = true,
    profileListRead: Bool = true
  ) -> StatusItemState {
    StatusItemState(
      statusLine: "status",
      needsAccess: needsAccess,
      controllers: controllers,
      profiles: profiles,
      profileListRead: profileListRead,
      statusSymbolName: "circle"
    )
  }

  private static func entry(_ id: String, in entries: [StatusItemEntry]) -> StatusItemEntry? {
    for entry in entries {
      if entry.id == id { return entry }
      if let submenu = entry.submenu, let found = Self.entry(id, in: submenu) { return found }
    }
    return nil
  }

  private static func ids(_ entries: [StatusItemEntry]) -> [String] {
    entries.flatMap { [$0.id] + ids($0.submenu ?? []) }.filter {
      !$0.contains("profiles.activate.") && !$0.contains("profiles.deactivate.")
        && !$0.contains("activeProfile.")
    }
  }

  @Test
  func grantAccessIsShownOnlyWhenAccessIsMissing() {
    let missing = StatusItemModel.entries(for: Self.state(needsAccess: true))
    let complete = StatusItemModel.entries(for: Self.state(needsAccess: false))
    #expect(Self.entry("grantAccess", in: missing)?.action == .showArea(.access))
    #expect(Self.entry("grantAccess", in: complete) == nil)
  }

  @Test
  func onlyTheStatusLineCarriesAnIcon() {
    let entries = StatusItemModel.entries(for: Self.state(controllers: [Self.pad]))
    func symbols(_ entries: [StatusItemEntry]) -> [String] {
      entries.flatMap { Array($0.symbolName.map { [$0] } ?? []) + symbols($0.submenu ?? []) }
    }
    #expect(symbols(entries) == ["circle"])
    #expect(Self.entry("status", in: entries)?.symbolName == "circle")
  }

  @Test
  func settingsAndQuitUseTheAppMenuTitles() {
    let entries = StatusItemModel.entries(for: Self.state())
    #expect(Self.entry("settings", in: entries)?.title == .key("ui.menu.app.settings"))
    #expect(Self.entry("quit", in: entries)?.title == .key("ui.menu.app.quit"))
    #expect(Self.entry("openWindow", in: entries)?.title == .key("ui.extra.openWindow"))
  }

  @Test
  func alreadyActiveProfileIsCheckedWithoutAnAction() throws {
    let active = StatusItemState.Profile(id: UUID(), name: "A", isActive: true)
    let other = StatusItemState.Profile(id: UUID(), name: "B", isActive: false)
    var pad = Self.pad
    pad.profiles = [active, other]
    let entries = StatusItemModel.entries(for: Self.state(controllers: [pad]))
    let activeEntry = try #require(
      Self.entry("controllers.pad-a.activeProfile.\(active.id.uuidString)", in: entries)
    )
    let otherEntry = try #require(
      Self.entry("controllers.pad-a.activeProfile.\(other.id.uuidString)", in: entries)
    )
    #expect(activeEntry.isChecked)
    #expect(!activeEntry.isEnabled)
    #expect(activeEntry.action == nil)
    #expect(!otherEntry.isChecked)
    #expect(otherEntry.action == .activateProfile(other.id))
  }

  @Test
  func noControllerShowsOneDisabledRowThatSaysSo() throws {
    let entries = StatusItemModel.entries(for: Self.state())
    let controllers = try #require(Self.entry("controllers", in: entries))
    #expect(controllers.isEnabled)
    #expect(controllers.submenu?.map(\.id) == ["controllers.none"])
    let none = try #require(Self.entry("controllers.none", in: entries))
    #expect(none.title == .key("ui.menu.controller.noneConnected"))
    #expect(!none.isEnabled)
    #expect(none.action == nil)
    #expect(try #require(Self.entry("grantAccess", in: entries)).isEnabled)
    #expect(try #require(Self.entry("quit", in: entries)).isEnabled)
    // Both profile submenus stay openable; each holds one disabled row.
    #expect(try #require(Self.entry("profiles.activate", in: entries)).isEnabled)
    #expect(try #require(Self.entry("profiles.deactivate", in: entries)).isEnabled)
  }

  @Test
  func activateSubmenuStaysOpenableWithOneDisabledRowWhenNoProfileExists() throws {
    let entries = StatusItemModel.entries(for: Self.state())
    let activate = try #require(Self.entry("profiles.activate", in: entries))
    #expect(activate.isEnabled)
    #expect(activate.submenu?.map(\.id) == ["profiles.activate.none"])
    let row = try #require(Self.entry("profiles.activate.none", in: entries))
    #expect(row.title == .key("ui.menu.profile.none"))
    #expect(!row.isEnabled)
    #expect(row.action == nil)
  }

  @Test
  func activateSubmenuSaysProfilesAreUnavailableUntilTheListIsRead() throws {
    let entries = StatusItemModel.entries(for: Self.state(profileListRead: false))
    let row = try #require(Self.entry("profiles.activate.none", in: entries))
    #expect(row.title == .key("ui.menu.profile.unavailable"))
    #expect(!row.isEnabled)
    #expect(try #require(Self.entry("profiles.activate", in: entries)).isEnabled)
    let deactivate = try #require(Self.entry("profiles.deactivate.none", in: entries))
    #expect(deactivate.title == .key("ui.menu.profile.unavailable"))
  }

  @Test
  func statusAndMainMenuNameTheEmptyActivateRowFromOneFunction() throws {
    for read in [true, false] {
      let entries = StatusItemModel.entries(for: Self.state(profileListRead: read))
      let row = try #require(Self.entry("profiles.activate.none", in: entries))
      #expect(
        row.title == .key(MainMenuModel.emptyActivateProfileTitleKey(profileListRead: read))
      )
    }
  }

  @Test
  func activateSubmenuListsEveryProfileAndChecksTheActiveOne() throws {
    let active = StatusItemState.Profile(id: UUID(), name: "A", isActive: true)
    let other = StatusItemState.Profile(id: UUID(), name: "B", isActive: false)
    let entries = StatusItemModel.entries(for: Self.state(profiles: [active, other]))
    let rows = try #require(Self.entry("profiles.activate", in: entries)?.submenu)
    #expect(rows.map(\.title) == [.verbatim("A"), .verbatim("B")])
    #expect(rows.map(\.isChecked) == [true, false])
    #expect(rows.map(\.isEnabled) == [false, true])
    #expect(rows.map(\.action) == [nil, .activateProfile(other.id)])
  }

  @Test
  func deactivateSubmenuHoldsOneDisabledRowWhileNoProfileIsActive() throws {
    let idle = StatusItemState.Profile(id: UUID(), name: "B", isActive: false)
    let entries = StatusItemModel.entries(for: Self.state(profiles: [idle]))
    let deactivate = try #require(Self.entry("profiles.deactivate", in: entries))
    #expect(deactivate.isEnabled)
    #expect(deactivate.submenu?.map(\.id) == ["profiles.deactivate.none"])
    let row = try #require(Self.entry("profiles.deactivate.none", in: entries))
    #expect(row.title == .key("ui.menu.profile.noneActive"))
    #expect(!row.isEnabled)
  }

  @Test
  func controllerWithoutApplicableProfilesKeepsItsProfileSubmenuOpenable() throws {
    let entries = StatusItemModel.entries(for: Self.state(controllers: [Self.pad]))
    let submenu = try #require(Self.entry("controllers.pad-a.activeProfile", in: entries))
    #expect(submenu.isEnabled)
    #expect(submenu.submenu?.map(\.id) == ["controllers.pad-a.activeProfile.none"])
    let row = try #require(Self.entry("controllers.pad-a.activeProfile.none", in: entries))
    #expect(row.title == .key("ui.menu.profile.none"))
    #expect(!row.isEnabled)
  }

  @Test
  func controllerProfileSubmenuSaysProfilesAreUnavailableUntilTheListIsRead() throws {
    let entries = StatusItemModel.entries(
      for: Self.state(controllers: [Self.pad], profileListRead: false)
    )
    let row = try #require(Self.entry("controllers.pad-a.activeProfile.none", in: entries))
    #expect(row.title == .key("ui.menu.profile.unavailable"))
    #expect(!row.isEnabled)
    #expect(try #require(Self.entry("controllers.pad-a.activeProfile", in: entries)).isEnabled)
  }

  @Test
  func entryIDsAreUniqueBecauseTheyAreTheAccessibilityIdentifiers() {
    let profile = StatusItemState.Profile(id: UUID(), name: "A", isActive: true)
    var pad = Self.pad
    pad.profiles = [profile]
    let other = StatusItemState.Controller(
      id: "pad-b",
      name: "Pad",
      isSuspended: false,
      isWireless: false
    )
    let entries = StatusItemModel.entries(
      for: Self.state(controllers: [pad, other], profiles: [profile])
    )
    func allIDs(_ entries: [StatusItemEntry]) -> [String] {
      entries.filter { !$0.isSeparator }.flatMap { [$0.id] + allIDs($0.submenu ?? []) }
    }
    let ids = allIDs(entries)
    #expect(Set(ids).count == ids.count)
  }

  @Test
  func eachControllerListsOnlyItsOwnProfilesAndChecksItsActiveOne() throws {
    let racing = StatusItemState.Profile(id: UUID(), name: "Racing", isActive: true)
    let menu = StatusItemState.Profile(id: UUID(), name: "Menu", isActive: false)
    let flight = StatusItemState.Profile(id: UUID(), name: "Flight", isActive: false)
    var first = Self.pad
    first.profiles = [racing, menu]
    var second = StatusItemState.Controller(
      id: "pad-b",
      name: "Stick",
      isSuspended: false,
      isWireless: false
    )
    second.profiles = [flight]
    let entries = StatusItemModel.entries(for: Self.state(controllers: [first, second]))
    let firstProfiles = try #require(
      Self.entry("controllers.pad-a.activeProfile", in: entries)?.submenu
    )
    #expect(firstProfiles.map(\.title) == [.verbatim("Racing"), .verbatim("Menu")])
    #expect(firstProfiles.map(\.isChecked) == [true, false])
    let secondProfiles = try #require(
      Self.entry("controllers.pad-b.activeProfile", in: entries)?.submenu
    )
    #expect(secondProfiles.map(\.title) == [.verbatim("Flight")])
    #expect(secondProfiles.map(\.isChecked) == [false])
    #expect(secondProfiles.map(\.action) == [.activateProfile(flight.id)])
  }

  @Test
  func controllerActionsAreDisabledNotHiddenWhenTheyDoNotApply() throws {
    let wired = StatusItemState.Controller(
      id: "pad-b",
      name: "Wired",
      isSuspended: false,
      isWireless: false
    )
    let entries = StatusItemModel.entries(for: Self.state(controllers: [Self.pad, wired]))
    let suffixes = ["suspend", "testInput", "activeProfile", "disconnectWireless", "showInWindow"]
    for token in ["pad-a", "pad-b"] {
      let actions = try #require(Self.entry("controllers.\(token)", in: entries)?.submenu)
      #expect(actions.map(\.id) == suffixes.map { "controllers.\(token).\($0)" })
    }
    let wiredActions = try #require(Self.entry("controllers.pad-b", in: entries)?.submenu)
    #expect(wiredActions.map(\.isEnabled) == [true, true, true, false, true])
    #expect(wiredActions[3].action == nil)
  }

  @Test
  func eachOfTwoControllersHasItsOwnActions() throws {
    let wired = StatusItemState.Controller(
      id: "pad-b",
      name: "Wired",
      isSuspended: true,
      isWireless: false
    )
    let entries = StatusItemModel.entries(for: Self.state(controllers: [Self.pad, wired]))
    let controllers = try #require(Self.entry("controllers", in: entries))
    #expect(controllers.submenu?.map(\.id) == ["controllers.pad-a", "controllers.pad-b"])
    #expect(controllers.submenu?.map(\.title) == [.verbatim("Pad"), .verbatim("Wired")])

    let padActions = try #require(Self.entry("controllers.pad-a", in: entries)?.submenu)
    #expect(
      padActions.map(\.action) == [
        .suspendController(sessionToken: "pad-a"), .testInput(sessionToken: "pad-a"), nil,
        .disconnectWireless(sessionToken: "pad-a"), .showController(sessionToken: "pad-a"),
      ]
    )
    #expect(padActions.map(\.isEnabled) == [true, true, true, true, true])

    let wiredActions = try #require(Self.entry("controllers.pad-b", in: entries)?.submenu)
    #expect(
      wiredActions.map(\.action) == [
        .resumeController(sessionToken: "pad-b"), .testInput(sessionToken: "pad-b"), nil, nil,
        .showController(sessionToken: "pad-b"),
      ]
    )
    #expect(wiredActions.map(\.isEnabled) == [true, true, true, false, true])
  }

  @Test
  func oneWirelessControllerEnablesItsItems() throws {
    let profile = StatusItemState.Profile(id: UUID(), name: "Racing", isActive: true)
    let other = StatusItemState.Profile(id: UUID(), name: "Menu", isActive: false)
    var pad = Self.pad
    pad.profiles = [profile, other]
    let entries = StatusItemModel.entries(
      for: Self.state(controllers: [pad], profiles: [profile, other])
    )
    let suspend = try #require(Self.entry("controllers.pad-a.suspend", in: entries))
    #expect(suspend.isEnabled)
    #expect(suspend.action == .suspendController(sessionToken: "pad-a"))
    let disconnect = try #require(Self.entry("controllers.pad-a.disconnectWireless", in: entries))
    #expect(disconnect.isEnabled)
    #expect(disconnect.action == .disconnectWireless(sessionToken: "pad-a"))
    #expect(try #require(Self.entry("controllers.pad-a.testInput", in: entries)).isEnabled)
    #expect(try #require(Self.entry("controllers.pad-a.showInWindow", in: entries)).isEnabled)
    let active = try #require(Self.entry("controllers.pad-a.activeProfile", in: entries))
    #expect(active.isEnabled)
    #expect(active.submenu?.map(\.isChecked) == [true, false])
    let activate = try #require(Self.entry("profiles.activate", in: entries))
    #expect(activate.submenu?.map(\.action) == [nil, .activateProfile(other.id)])
    let deactivate = try #require(Self.entry("profiles.deactivate", in: entries))
    #expect(deactivate.submenu?.map(\.action) == [.deactivateProfile(profile.id)])
  }

  @Test
  func suspendedControllerOffersResume() throws {
    let suspended = StatusItemState.Controller(
      id: Self.pad.id,
      name: Self.pad.name,
      isSuspended: true,
      isWireless: false
    )
    let entries = StatusItemModel.entries(for: Self.state(controllers: [suspended]))
    #expect(Self.entry("controllers.pad-a.suspend", in: entries) == nil)
    let resume = try #require(Self.entry("controllers.pad-a.resume", in: entries))
    #expect(resume.action == .resumeController(sessionToken: "pad-a"))
    let disconnect = try #require(Self.entry("controllers.pad-a.disconnectWireless", in: entries))
    #expect(!disconnect.isEnabled)
  }

  @Test
  func pausedControllerShowsADisabledPausedRow() throws {
    let paused = StatusItemState.Controller(
      id: Self.pad.id,
      name: Self.pad.name,
      isSuspended: false,
      isWireless: false,
      isPaused: true
    )
    let row = try #require(
      Self.entry(
        "controllers.pad-a.paused",
        in: StatusItemModel.entries(for: Self.state(controllers: [paused]))
      )
    )
    #expect(row.title == .key("ui.controllers.paused.value"))
    #expect(!row.isEnabled)
    #expect(
      Self.entry(
        "controllers.pad-a.paused",
        in: StatusItemModel.entries(for: Self.state(controllers: [Self.pad]))
      ) == nil
    )
  }

  @Test
  func wiredControllerLeavesDisconnectDisabled() throws {
    let wired = StatusItemState.Controller(
      id: "pad-b",
      name: "Wired",
      isSuspended: false,
      isWireless: false
    )
    let entries = StatusItemModel.entries(for: Self.state(controllers: [wired]))
    #expect(
      !(try #require(Self.entry("controllers.pad-b.disconnectWireless", in: entries))).isEnabled
    )
  }

  @Test
  func topLevelLayoutIsFixedAcrossStates() {
    func topLevel(_ state: StatusItemState) -> [String] {
      StatusItemModel.entries(for: state).map(\.id)
    }
    let none = topLevel(Self.state())
    var errored = Self.state()
    errored.statusLine = "service unavailable"
    errored.statusSymbolName = "xmark.octagon"
    #expect(none == topLevel(errored))
    #expect(none == topLevel(Self.state(controllers: [Self.pad])))
    #expect(
      none == [
        "status", "separator.status", "controllers", "profiles", "separator.profiles",
        "grantAccess", "openWindow", "settings", "separator.window", "help", "separator.help",
        "quit",
      ]
    )
    #expect(
      Self.ids(StatusItemModel.entries(for: Self.state(controllers: [Self.pad]))).filter {
        $0.hasPrefix("controllers.")
      } == [
        "controllers.pad-a", "controllers.pad-a.suspend", "controllers.pad-a.testInput",
        "controllers.pad-a.activeProfile", "controllers.pad-a.disconnectWireless",
        "controllers.pad-a.showInWindow",
      ]
    )
  }

  @Test
  func errorStateShowsTheStatusLineAndKeepsAccessReachable() throws {
    var errored = Self.state()
    errored.statusLine = "Needs attention"
    let entries = StatusItemModel.entries(for: errored)
    let line = try #require(Self.entry("status", in: entries))
    #expect(line.title == .verbatim("Needs attention"))
    #expect(!line.isEnabled)
    #expect(try #require(Self.entry("grantAccess", in: entries)).action == .showArea(.access))
    #expect(
      try #require(Self.entry("help.activityLog", in: entries)).action == .showArea(.activity)
    )
  }

  @Test
  func typedBluetoothTransportDecidesWireless() {
    func device(
      _ transport: PhysicalTransport?,
      connection: String
    )
      -> ApplicationServiceDeviceDescription
    {
      ApplicationServiceDeviceDescription(
        name: "Pad",
        vendorID: 1,
        productID: 2,
        protocolBinding: ProtocolBindingID(.hidDescriptor),
        connection: connection,
        discoverySource: .rawUSB,
        serialNumber: nil,
        bindingResult: .hidDescriptorFixture,
        recordServer: .system,
        recordAccessRoute: .system,
        connectionState: ControllerConnectionState(
          transport: transport,
          backend: .hid,
          isConnected: true,
          power: .unknown
        )
      )
    }
    #expect(device(.bluetoothClassic, connection: "HID").supportsWirelessDisconnect)
    #expect(!device(.bluetoothLE, connection: "HID").supportsWirelessDisconnect)
    #expect(!device(.usb, connection: "Bluetooth").supportsWirelessDisconnect)
    #expect(!device(nil, connection: "Bluetooth").supportsWirelessDisconnect)
  }

  @Test
  func statusLineIsOneLocalizedFormatWithPositionalArguments() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriverStatusLine-\(UUID().uuidString).bundle"
    )
    let resources = root.appendingPathComponent("Contents/Resources")
    for language in ["en-US", "ar-SA"] {
      try FileManager.default.createDirectory(
        at: resources.appendingPathComponent("\(language).lproj"),
        withIntermediateDirectories: true
      )
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let info = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>CFBundleIdentifier</key>
      <string>test.statusline</string></dict></plist>
      """
    try Data(info.utf8).write(to: root.appendingPathComponent("Contents/Info.plist"))
    try Data("\"ui.extra.statusLine\" = \"%1$@ · %2$@ · %3$@\";\n".utf8).write(
      to: resources.appendingPathComponent("en-US.lproj/Localizable.strings")
    )
    try Data("\"ui.extra.statusLine\" = \"%3$@ ، %2$@ ، %1$@\";\n".utf8).write(
      to: resources.appendingPathComponent("ar-SA.lproj/Localizable.strings")
    )
    let bundle = try #require(Bundle(path: root.path))

    let arabic = Localization(bundle: bundle, preferredLanguages: ["ar-SA"])
    #expect(
      StatusItemStatusLine.make(
        readiness: "A",
        controllers: "B",
        profile: "C",
        localization: arabic,
        locale: Locale(identifier: "ar_SA")
      ) == "C ، B ، A"
    )
    let english = Localization(bundle: bundle, preferredLanguages: ["en-US"])
    #expect(
      StatusItemStatusLine.make(
        readiness: "A",
        controllers: "B",
        profile: "C",
        localization: english,
        locale: Locale(identifier: "en_US")
      ) == "A · B · C"
    )
  }
}
