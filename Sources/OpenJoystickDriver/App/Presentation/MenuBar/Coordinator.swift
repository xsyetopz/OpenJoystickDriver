#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  @MainActor final class MenuBarCoordinator: NSObject, NSApplicationDelegate {
    let runtime: ApplicationServiceRuntime
    let viewModel: RuntimeViewModel

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?
    private var refreshTimer: Timer?
    private var liveStatusTimer: Timer?
    private let notificationMonitor = RuntimeNotificationMonitor()
    private let notificationPresenter = RuntimeNotificationCenterDelegate()
    private var liveStatusRefreshInFlight = false
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
      UNUserNotificationCenter.current().delegate = notificationPresenter
      refreshStatus()
      refreshTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.refreshStatus() }
      }
      liveStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.refreshLiveStatus() }
      }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
      guard !isStopping else { return .terminateNow }
      isStopping = true
      refreshTimer?.invalidate()
      refreshTimer = nil
      liveStatusTimer?.invalidate()
      liveStatusTimer = nil
      Task { @MainActor [weak self, weak sender] in
        guard let self else { return }
        await self.runtime.stop()
        sender?.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    }

    @objc func openSettings(_ sender: Any?) { openSettings(pane: .settings) }

    @objc func showApplication(_ sender: Any?) { openSettings(pane: nil) }

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
        if let appIcon = NSImage(named: NSImage.applicationIconName)?.copy() as? NSImage {
          appIcon.size = NSSize(width: 18, height: 18)
          button.image = appIcon
        } else if #available(macOS 11.0, *) {
          button.image = NSImage(
            systemSymbolName: "gamecontroller",
            accessibilityDescription: OJDLocalized.string(
              "app.name",
              fallback: "OpenJoystickDriver"
            )
          )
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
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        updateStatusMenu()
      }
    }

    private func refreshLiveStatus() {
      guard !liveStatusRefreshInFlight else { return }
      liveStatusRefreshInFlight = true
      Task { @MainActor [weak self] in
        guard let self else { return }
        await viewModel.refreshLiveStatus()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        updateStatusMenu()
        liveStatusRefreshInFlight = false
      }
    }

    private func updateStatusMenu() {
      guard let menu = statusMenu else { return }
      menu.removeAllItems()

      let show = NSMenuItem(
        title: OJDLocalized.string("menu.show", fallback: "Show OpenJoystickDriver"),
        action: #selector(showApplication(_:)),
        keyEquivalent: ""
      )
      show.target = self
      menu.addItem(show)
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

      let settings = NSMenuItem(
        title: OJDLocalized.string("menu.settings", fallback: "Settings..."),
        action: #selector(openSettingsFromStatus(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.representedObject = SettingsPane.settings.rawValue
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      menu.addItem(settings)
      menu.addItem(.separator())

      let controllers = NSMenuItem(
        title: OJDLocalized.string("common.controllers", fallback: "Controllers"),
        action: nil,
        keyEquivalent: ""
      )
      controllers.submenu = makeControllersMenu()
      menu.addItem(controllers)

      let help = NSMenuItem(
        title: OJDLocalized.string("menu.help", fallback: "Help"),
        action: nil,
        keyEquivalent: ""
      )
      help.submenu = makeHelpMenu()
      menu.addItem(help)
      menu.addItem(.separator())

      let about = NSMenuItem(
        title: OJDLocalized.string("menu.about", fallback: "About OpenJoystickDriver"),
        action: #selector(showAbout(_:)),
        keyEquivalent: ""
      )
      about.target = self
      menu.addItem(about)

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

    private func makeControllersMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("common.controllers", fallback: "Controllers"))
      if case .available(let status) = viewModel.statusState, !status.devices.isEmpty {
        for device in status.devices {
          let item = NSMenuItem(
            title: device.name,
            action: #selector(openSettingsFromStatus(_:)),
            keyEquivalent: ""
          )
          item.target = self
          item.representedObject = SettingsPane.controllers.rawValue
          item.image = controllerMenuImage(for: device.protocolVariant)
          menu.addItem(item)
        }
        menu.addItem(.separator())
      } else {
        let empty = NSMenuItem(
          title: OJDLocalized.string("controllers.emptyTitle", fallback: "No controller connected"),
          action: nil,
          keyEquivalent: ""
        )
        empty.isEnabled = false
        menu.addItem(empty)
        menu.addItem(.separator())
      }
      addNavigationItem(
        title: OJDLocalized.string("menu.controllers", fallback: "Open Controllers..."),
        pane: .controllers,
        symbol: "gamecontroller",
        to: menu
      )
      return menu
    }

    private func makeHelpMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("menu.help", fallback: "Help"))
      addNavigationItem(
        title: OJDLocalized.string("menu.console", fallback: "Open Console..."),
        pane: .console,
        symbol: "terminal",
        to: menu
      )
      let report = NSMenuItem(
        title: OJDLocalized.string("debug.saveReport", fallback: "Save Debug Report..."),
        action: #selector(saveSupportReport(_:)),
        keyEquivalent: ""
      )
      report.target = self
      menu.addItem(report)
      let logs = NSMenuItem(
        title: OJDLocalized.string("debug.saveLogs", fallback: "Save Logs..."),
        action: #selector(saveSupportLogs(_:)),
        keyEquivalent: ""
      )
      logs.target = self
      menu.addItem(logs)
      menu.addItem(.separator())
      let project = NSMenuItem(
        title: OJDLocalized.string("menu.projectPage", fallback: "GitHub"),
        action: #selector(openProjectPage(_:)),
        keyEquivalent: ""
      )
      project.target = self
      menu.addItem(project)
      return menu
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
      case "ant", "terminal": legacyName = "NSInfo"
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

    private func controllerMenuImage(for protocolVariant: ControllerProtocolVariant) -> NSImage? {
      if let image = menuImage(symbol: protocolVariant.controllerSymbolName) { return image }
      return menuImage(symbol: "gamecontroller")
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

    @objc private func saveSupportReport(_ sender: Any?) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveReportPanel", fallback: "Save Debug Report")
      panel.nameFieldStringValue = viewModel.defaultSupportReportFilename
      panel.canCreateDirectories = true
      panel.begin { [viewModel] response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in await viewModel.saveSupportReport(to: outputURL) }
      }
    }

    @objc private func saveSupportLogs(_ sender: Any?) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveLogsPanel", fallback: "Save Debug Logs")
      panel.nameFieldStringValue = viewModel.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      panel.begin { [viewModel] response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in await viewModel.saveSupportLogs(to: outputURL) }
      }
    }

    @objc private func openProjectPage(_ sender: Any?) {
      guard let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver") else { return }
      NSWorkspace.shared.open(url)
    }

    @objc private func showAbout(_ sender: Any?) {
      let repositoryTitle = OJDLocalized.string("menu.projectPage", fallback: "GitHub")
      let credits = NSMutableAttributedString(string: repositoryTitle)
      if let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver") {
        credits.addAttribute(.link, value: url, range: NSRange(location: 0, length: credits.length))
      }
      var options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver"),
        .applicationVersion: ApplicationVersion.current, .credits: credits
      ]
      if let icon = NSImage(named: NSImage.applicationIconName) { options[.applicationIcon] = icon }
      NSApplication.shared.orderFrontStandardAboutPanel(options: options)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

#else

  final class MenuBarCoordinator {}

#endif
