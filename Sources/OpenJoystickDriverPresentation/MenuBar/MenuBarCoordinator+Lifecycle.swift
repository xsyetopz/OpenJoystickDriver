#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  extension MenuBarCoordinator {

    package func run() -> Never {
      Self.activeCoordinator = self
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.delegate = self
      application.mainMenu = makeApplicationMenu()
      installStatusItem()
      application.run()

      // Normal termination has already awaited stopRuntime() in applicationShouldTerminate.
      // Exit only after AppKit has completed that reply; the signal path retains its own exit path.
      exit(0)
    }

    package func applicationDidFinishLaunching(_ notification: Notification) {
      bundledNotificationCenter?.delegate = notificationPresenter
      refreshStatus()
      controllerInventoryObserver = NotificationCenter.default.addObserver(
        forName: .ojdControllerInventoryDidChange,
        object: nil,
        queue: .main
      ) { [weak self] _ in Task { @MainActor [weak self] in self?.refreshLiveStatus() } }
      Task { @MainActor in await viewModel.startSystemExtensionSetup() }
      liveStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.refreshLiveStatus() }
      }
    }

    package func applicationDidBecomeActive(_ notification: Notification) {
      Task { @MainActor in await viewModel.refreshSystemExtensionSetup() }
    }

    package func applicationShouldHandleReopen(
      _ sender: NSApplication,
      hasVisibleWindows flag: Bool
    ) -> Bool {
      refreshLiveStatus()
      openSettings(pane: .overview)
      return true
    }

    package func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    {
      termination.request {
        self.removeStatusItem()
        self.inputTestWindowController?.stop()
        await self.stopRuntime()
      } relaunch: {
        await self.relaunchApplication()
      } reply: {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }

    func terminateFromShutdownSignal() { NSApplication.shared.terminate(nil) }

    @discardableResult
    package static func terminateFromShutdownSignalIfRunning() -> Bool {
      guard let activeCoordinator else { return false }
      activeCoordinator.terminateFromShutdownSignal()
      return true
    }

    package func applicationWillTerminate(_ notification: Notification) { removeStatusItem() }

    @objc
    func openSettings(_ sender: Any?) { openSettings(pane: .settings) }

    @objc
    func showApplication(_ sender: Any?) { openSettings(pane: nil) }

    @objc
    func openSettingsFromStatus(_ sender: Any?) {
      let item = sender as? NSMenuItem
      let pane = item.flatMap { SettingsPane(rawValue: $0.representedObject as? String ?? "") }
      openSettings(pane: pane ?? .overview)
    }

    @objc
    func quit(_ sender: Any?) { NSApplication.shared.terminate(sender) }

    private func restartApplication() {
      termination.requestRelaunch { NSApplication.shared.terminate(nil) }
    }

    private func relaunchApplication() async {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      await withCheckedContinuation { continuation in
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        { _, error in
          if let error { fputs("Failed to relaunch OpenJoystickDriver: \(error)\n", stderr) }
          continuation.resume()
        }
      }
    }

    func openSettings(pane: SettingsPane?) {
      if settingsWindowController == nil {
        settingsWindowController = SettingsWindowController(
          viewModel: viewModel,
          supportReport: supportReport,
          restartApplication: { [weak self] in self?.restartApplication() },
          openInputTest: { [weak self] device in self?.openInputTest(for: device) },
          visibilityChanged: { [weak self] isOpen in
            if isOpen {
              self?.primaryWindowVisibility.opened(.workbench)
            } else {
              self?.primaryWindowVisibility.closed(.workbench)
            }
          }
        )
      }
      settingsWindowController?.show(pane: pane)
    }

    private func openInputTest(for device: ApplicationServiceDeviceDescription) {
      if inputTestWindowController == nil {
        inputTestWindowController = InputTestWindowController(
          gateway: gateway,
          runtimeViewModel: viewModel
        ) { [weak self] isOpen in
          if isOpen {
            self?.primaryWindowVisibility.opened(.inputTest)
          } else {
            self?.primaryWindowVisibility.closed(.inputTest)
          }
        }
      }
      inputTestWindowController?.show(device: device)
    }

    private func installStatusItem() {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      statusItem = item
      if let button = item.button {
        button.toolTip = OJDLocalized.string("app.name")
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        if let image = MenuBarStatusItemImage.make(
          applicationIcon: NSImage(named: NSImage.applicationIconName),
          accessibilityDescription: OJDLocalized.string("app.name")
        ) {
          button.image = image
        }
        if button.image == nil {
          // Text is an intentional final fallback for an unbundled debug executable.
          button.title = "OJ"
        }
      }
      statusMenu = NSMenu(title: OJDLocalized.string("app.name"))
      // Use the action path rather than assigning a menu directly so each opening refreshes its
      // snapshot before the menu is shown.
      item.menu = nil
    }

    private func removeStatusItem() {
      liveStatusTimer?.invalidate()
      liveStatusTimer = nil
      if let controllerInventoryObserver {
        NotificationCenter.default.removeObserver(controllerInventoryObserver)
        self.controllerInventoryObserver = nil
      }
      guard let item = statusItem else { return }
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
      statusMenu = nil
    }

    @objc
    private func showStatusMenu(_ sender: Any?) {
      refreshLiveStatus()
      guard let menu = statusMenu, let button = statusItem?.button else { return }
      // Pop up the same native menu on every click after the asynchronous status refresh starts.
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func refreshStatus() {
      updateStatusMenu()
      Task { @MainActor [weak self] in
        guard let self else { return }
        await menuBarViewModel.refresh()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        updateStatusMenu()
      }
    }

    private func refreshLiveStatus() {
      Task { @MainActor [weak self] in
        guard let self else { return }
        let statusChanged = await menuBarViewModel.refreshLiveStatus()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        if statusChanged { updateStatusMenu() }
      }
    }

    private func updateStatusMenu() {
      guard let menu = statusMenu else { return }
      menu.removeAllItems()

      let summary = NSMenuItem(title: menuBarViewModel.summaryTitle, action: nil, keyEquivalent: "")
      summary.isEnabled = false
      summary.image = menuImage(
        symbol: menuBarViewModel.summarySemanticState.presentation.symbolName
      )
      menu.addItem(summary)
      menu.addItem(.separator())

      if menuBarViewModel.needsPermissionAttention {
        let request = NSMenuItem(
          title: OJDLocalized.string("menu.requestAccess"),
          action: #selector(requestAccessFromStatus(_:)),
          keyEquivalent: ""
        )
        request.target = self
        request.image = menuImage(symbol: "lock.shield")
        menu.addItem(request)
      }

      let controllers = NSMenuItem(
        title: OJDLocalized.string("common.controllers"),
        action: nil,
        keyEquivalent: ""
      )
      controllers.submenu = makeControllersMenu()
      menu.addItem(controllers)

      let show = NSMenuItem(
        title: OJDLocalized.string("menu.show"),
        action: #selector(showApplication(_:)),
        keyEquivalent: ""
      )
      show.target = self
      menu.addItem(show)

      let settings = NSMenuItem(
        title: OJDLocalized.string("menu.settings"),
        action: #selector(openSettingsFromStatus(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.representedObject = SettingsPane.settings.rawValue
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      menu.addItem(settings)
      menu.addItem(.separator())

      let help = NSMenuItem(
        title: OJDLocalized.string("menu.help"),
        action: nil,
        keyEquivalent: ""
      )
      help.submenu = makeHelpMenu()
      menu.addItem(help)
      menu.addItem(.separator())

      let about = NSMenuItem(
        title: OJDLocalized.string("menu.about"),
        action: #selector(showAbout(_:)),
        keyEquivalent: ""
      )
      about.target = self
      menu.addItem(about)

      let quit = NSMenuItem(
        title: OJDLocalized.string("menu.quit"),
        action: #selector(quit(_:)),
        keyEquivalent: "q"
      )
      quit.target = self
      quit.keyEquivalentModifierMask = [.command]
      quit.image = menuImage(symbol: "power")
      menu.addItem(quit)
    }

    private func makeControllersMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("common.controllers"))
      if !menuBarViewModel.devices.isEmpty {
        for device in menuBarViewModel.devices {
          let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
          item.image = controllerMenuImage(for: device.publishedIdentityPresentation)
          item.submenu = makeControllerMenu(for: device)
          menu.addItem(item)
        }
        menu.addItem(.separator())
      } else {
        let empty = NSMenuItem(
          title: OJDLocalized.string("controllers.emptyTitle"),
          action: nil,
          keyEquivalent: ""
        )
        empty.isEnabled = false
        menu.addItem(empty)
        menu.addItem(.separator())
      }
      addNavigationItem(
        title: OJDLocalized.string("menu.controllers"),
        pane: .controllers,
        symbol: "gamecontroller",
        to: menu
      )
      return menu
    }

    private func makeControllerMenu(for device: ApplicationServiceDeviceDescription) -> NSMenu {
      let menu = NSMenu(title: device.name)
      addNavigationItem(
        title: OJDLocalized.string("menu.controllers"),
        pane: .controllers,
        symbol: "info.circle",
        to: menu
      )
      if device.connection.caseInsensitiveCompare("Bluetooth") == .orderedSame {
        let disconnect = NSMenuItem(
          title: OJDLocalized.string(
            "controllers.disconnectWireless"
          ),
          action: #selector(disconnectWirelessControllerFromStatus(_:)),
          keyEquivalent: ""
        )
        disconnect.target = self
        disconnect.representedObject = device.runtimeIdentifier
        disconnect.image = menuImage(symbol: "antenna.radiowaves.left.and.right.slash")
        menu.addItem(disconnect)
      }
      return menu
    }

  }

#endif
