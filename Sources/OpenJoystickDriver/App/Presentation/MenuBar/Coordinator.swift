#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  @MainActor final class MenuBarCoordinator: NSObject, NSApplicationDelegate {
    let runtime: ApplicationServiceRuntime
    let viewModel: RuntimeViewModel

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?
    private var refreshTimer: Timer?
    private var isStopping = false

    init(runtime: ApplicationServiceRuntime, gateway: any ApplicationServiceGateway) {
      self.runtime = runtime
      self.viewModel = RuntimeViewModel(gateway: gateway)
      super.init()
    }

    func run() -> Never {
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.delegate = self
      application.mainMenu = makeApplicationMenu()
      installStatusItem()
      application.run()

      // Normal termination has already awaited runtime.stop() in applicationShouldTerminate.
      // Exit only after AppKit has completed that reply; the signal path retains its own exit path.
      exit(0)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
      refreshStatus()
      refreshTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.refreshStatus() }
      }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
      guard !isStopping else { return .terminateNow }
      isStopping = true
      refreshTimer?.invalidate()
      refreshTimer = nil
      Task { @MainActor [weak self, weak sender] in
        guard let self else { return }
        await self.runtime.stop()
        sender?.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    }

    @objc func openSettings(_ sender: Any?) { openSettings(pane: nil) }

    @objc func openSettingsFromStatus(_ sender: Any?) {
      let item = sender as? NSMenuItem
      let pane = item.flatMap { SettingsPane(rawValue: $0.representedObject as? String ?? "") }
      openSettings(pane: pane ?? .overview)
    }

    @objc func refreshFromStatus(_ sender: Any?) { refreshStatus() }

    @objc func quit(_ sender: Any?) { NSApplication.shared.terminate(sender) }

    private func openSettings(pane: SettingsPane?) {
      if settingsWindowController == nil {
        settingsWindowController = SettingsWindowController(viewModel: viewModel)
      }
      settingsWindowController?.show(pane: pane)
    }

    private func installStatusItem() {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      statusItem = item
      if let button = item.button {
        button.toolTip = OJDLocalized.string("app.name", fallback: "OpenJoystickDriver")
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        if #available(macOS 11.0, *) {
          button.image = NSImage(
            systemSymbolName: "gamecontroller",
            accessibilityDescription: OJDLocalized.string(
              "app.name",
              fallback: "OpenJoystickDriver"
            )
          )
          button.image?.isTemplate = true
        } else if let appIcon = NSImage(named: NSImage.applicationIconName) {
          button.image = appIcon
          button.image?.isTemplate = true
        } else {
          // Text is an intentional final fallback for an unbundled debug executable.
          button.title = "OJ"
        }
      }
      statusMenu = NSMenu(title: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver"))
      // Use the action path rather than assigning a menu directly so each opening refreshes its
      // snapshot before the menu is shown.
      item.menu = nil
    }

    @objc private func showStatusMenu(_ sender: Any?) {
      refreshStatus()
      guard let menu = statusMenu, let button = statusItem?.button else { return }
      // Pop up the same native menu on every click after the asynchronous status refresh starts.
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func refreshStatus() {
      updateStatusMenu()
      Task { @MainActor [weak self] in
        guard let self else { return }
        await viewModel.refresh()
        updateStatusMenu()
      }
    }

    private func updateStatusMenu() {
      guard let menu = statusMenu else { return }
      menu.removeAllItems()

      let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
      statusItem.isEnabled = false
      menu.addItem(statusItem)

      let profileItem = NSMenuItem(
        title: activeProfileTitle,
        action: remappingNeedsRetry ? #selector(refreshFromStatus(_:)) : nil,
        keyEquivalent: ""
      )
      profileItem.target = remappingNeedsRetry ? self : nil
      profileItem.isEnabled = remappingNeedsRetry
      menu.addItem(profileItem)
      menu.addItem(.separator())

      if needsPermissionAttention {
        let request = NSMenuItem(
          title: OJDLocalized.string("menu.requestAccess", fallback: "Request Access..."),
          action: #selector(requestAccessFromStatus(_:)),
          keyEquivalent: ""
        )
        request.target = self
        request.image = menuImage(symbol: "lock.shield")
        menu.addItem(request)
      }

      let refresh = NSMenuItem(
        title: OJDLocalized.string("common.refresh", fallback: "Refresh"),
        action: #selector(refreshFromStatus(_:)),
        keyEquivalent: "r"
      )
      refresh.target = self
      refresh.keyEquivalentModifierMask = [.command]
      refresh.image = menuImage(symbol: "arrow.clockwise")
      menu.addItem(refresh)
      menu.addItem(.separator())

      addNavigationItem(
        title: OJDLocalized.string("menu.overview", fallback: "Overview..."),
        pane: .overview,
        symbol: "rectangle.grid.2x2",
        to: menu
      )
      addNavigationItem(
        title: OJDLocalized.string("menu.controllers", fallback: "Controllers..."),
        pane: .controllers,
        symbol: "gamecontroller",
        to: menu
      )
      addNavigationItem(
        title: OJDLocalized.string("menu.profiles", fallback: "Profiles..."),
        pane: .profiles,
        symbol: "slider.horizontal.3",
        to: menu
      )
      addNavigationItem(
        title: OJDLocalized.string("menu.debug", fallback: "Debug..."),
        pane: .debug,
        symbol: "ant",
        to: menu
      )
      menu.addItem(.separator())

      let settings = NSMenuItem(
        title: OJDLocalized.string("menu.settings", fallback: "Settings..."),
        action: #selector(openSettingsFromStatus(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.representedObject = SettingsPane.overview.rawValue
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      menu.addItem(settings)

      let quit = NSMenuItem(
        title: OJDLocalized.string("menu.quit", fallback: "Quit OpenJoystickDriver"),
        action: #selector(quit(_:)),
        keyEquivalent: "q"
      )
      quit.target = self
      quit.keyEquivalentModifierMask = [.command]
      quit.image = menuImage(symbol: "power")
      menu.addItem(quit)
    }

    private func addNavigationItem(
      title: String,
      pane: SettingsPane,
      symbol: String,
      to menu: NSMenu
    ) {
      let item = NSMenuItem(
        title: title,
        action: #selector(openSettingsFromStatus(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = pane.rawValue
      item.image = menuImage(symbol: symbol)
      menu.addItem(item)
    }

    @objc private func requestAccessFromStatus(_ sender: Any?) {
      PermissionAccessActions.requestAccess(viewModel: viewModel)
    }

    private func menuImage(symbol: String) -> NSImage? {
      if #available(macOS 11.0, *) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
      }
      let legacyName: String
      switch symbol {
      case "slider.horizontal.3", "gearshape": legacyName = "NSPreferencesGeneral"
      case "gamecontroller": legacyName = "NSBluetoothTemplate"
      case "rectangle.grid.2x2": legacyName = "NSIconViewTemplate"
      case "ant": legacyName = "NSInfo"
      case "info.circle": legacyName = "NSInfo"
      case "lock.shield": legacyName = "NSLockLockedTemplate"
      case "arrow.clockwise": legacyName = "NSRefreshTemplate"
      case "power": legacyName = "NSStopProgressTemplate"
      default: return nil
      }
      let image = NSImage(named: NSImage.Name(legacyName))
      image?.isTemplate = true
      return image
    }

    private var statusTitle: String {
      switch viewModel.statusState {
      case .loading: return OJDLocalized.string("status.starting", fallback: "Starting…")
      case .available(let status):
        return OJDLocalized.formatted(
          "status.availableSummary",
          fallback: "%@ · %@",
          status.readinessLabel,
          status.deviceCountLabel
        )
      case .unavailable:
        return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
      case .error: return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
      }
    }

    private var activeProfileTitle: String {
      switch viewModel.remappingState {
      case .loading:
        return OJDLocalized.string(
          "status.activeProfileChecking",
          fallback: "Active profile: Checking…"
        )
      case .unavailable(let message):
        return OJDLocalized.formatted(
          "status.activeProfileUnavailable",
          fallback: "Active profile unavailable · %@",
          message
        )
      case .error(let message):
        return OJDLocalized.formatted(
          "status.activeProfileError",
          fallback: "Active profile error · %@",
          message
        )
      case .available(let snapshot):
        let names = snapshot.activeProfiles.map(\.profileName)
        guard !names.isEmpty else {
          return OJDLocalized.string("status.noActiveProfile", fallback: "No active profile")
        }
        if names.count == 1 {
          return OJDLocalized.formatted(
            "status.activeProfileNamed",
            fallback: "Active profile: %@",
            names[0]
          )
        }
        return OJDLocalized.plural(
          "status.activeProfilesCount",
          count: names.count,
          fallback: "%d active profiles"
        )
      }
    }

    private var remappingNeedsRetry: Bool {
      switch viewModel.remappingState {
      case .unavailable, .error: return true
      case .loading, .available: return false
      }
    }

    private var needsPermissionAttention: Bool {
      switch viewModel.statusState {
      case .available(let status):
        let needsPostEventAccess =
          status.requiresPostEventAccess == true && status.postEventAccess != .granted
        return !status.permissions.isReady || needsPostEventAccess
      case .loading, .unavailable, .error: return false
      }
    }

    private func makeApplicationMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver"))

      let applicationMenu = NSMenu(
        title: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver")
      )
      let about = NSMenuItem(
        title: OJDLocalized.string("menu.about", fallback: "About OpenJoystickDriver"),
        action: #selector(showAbout(_:)),
        keyEquivalent: ""
      )
      about.target = self
      about.image = menuImage(symbol: "info.circle")
      applicationMenu.addItem(about)
      applicationMenu.addItem(.separator())
      let settings = NSMenuItem(
        title: OJDLocalized.string("menu.settings", fallback: "Settings..."),
        action: #selector(openSettings(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      applicationMenu.addItem(settings)
      applicationMenu.addItem(.separator())
      let quit = NSMenuItem(
        title: OJDLocalized.string("menu.quit", fallback: "Quit OpenJoystickDriver"),
        action: #selector(quit(_:)),
        keyEquivalent: "q"
      )
      quit.target = self
      quit.keyEquivalentModifierMask = [.command]
      quit.image = menuImage(symbol: "power")
      applicationMenu.addItem(quit)
      let applicationItem = NSMenuItem()
      applicationItem.submenu = applicationMenu
      menu.addItem(applicationItem)

      // Install real responder-chain menus rather than empty placeholders.  Text fields and the
      // profile editor therefore retain the familiar macOS editing commands even though the app
      // itself is primarily a menu-bar facade.
      let editMenu = NSMenu(title: OJDLocalized.string("menu.edit", fallback: "Edit"))
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.undo", fallback: "Undo"),
        action: #selector(UndoManager.undo),
        keyEquivalent: "z"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.redo", fallback: "Redo"),
        action: #selector(UndoManager.redo),
        keyEquivalent: "Z"
      )
      editMenu.addItem(.separator())
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.cut", fallback: "Cut"),
        action: #selector(NSText.cut(_:)),
        keyEquivalent: "x"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.copy", fallback: "Copy"),
        action: #selector(NSText.copy(_:)),
        keyEquivalent: "c"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.paste", fallback: "Paste"),
        action: #selector(NSText.paste(_:)),
        keyEquivalent: "v"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.selectAll", fallback: "Select All"),
        action: #selector(NSText.selectAll(_:)),
        keyEquivalent: "a"
      )
      let editItem = NSMenuItem(
        title: OJDLocalized.string("menu.edit", fallback: "Edit"),
        action: nil,
        keyEquivalent: ""
      )
      editItem.submenu = editMenu
      menu.addItem(editItem)

      let windowMenu = NSMenu(title: OJDLocalized.string("menu.window", fallback: "Window"))
      windowMenu.addItem(
        withTitle: OJDLocalized.string("menu.minimize", fallback: "Minimize"),
        action: #selector(NSWindow.performMiniaturize(_:)),
        keyEquivalent: "m"
      )
      windowMenu.addItem(
        withTitle: OJDLocalized.string("menu.zoom", fallback: "Zoom"),
        action: #selector(NSWindow.performZoom(_:)),
        keyEquivalent: ""
      )
      windowMenu.addItem(.separator())
      windowMenu.addItem(
        withTitle: OJDLocalized.string("menu.bringAllToFront", fallback: "Bring All to Front"),
        action: #selector(NSApplication.arrangeInFront(_:)),
        keyEquivalent: ""
      )
      let windowItem = NSMenuItem(
        title: OJDLocalized.string("menu.window", fallback: "Window"),
        action: nil,
        keyEquivalent: ""
      )
      windowItem.submenu = windowMenu
      menu.addItem(windowItem)
      NSApplication.shared.windowsMenu = windowMenu
      return menu
    }

    @objc private func showAbout(_ sender: Any?) {
      let alert = NSAlert()
      alert.messageText = OJDLocalized.string("app.name", fallback: "OpenJoystickDriver")
      alert.informativeText = OJDLocalized.formatted(
        "about.version",
        fallback: "Version %@\nController input for macOS",
        ApplicationVersion.current
      )
      alert.alertStyle = .informational
      alert.addButton(withTitle: OJDLocalized.string("menu.projectPage", fallback: "Project page"))
      alert.addButton(withTitle: OJDLocalized.string("common.ok", fallback: "OK"))
      if alert.runModal() == .alertFirstButtonReturn,
        let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }

#else

  final class MenuBarCoordinator {}

#endif
