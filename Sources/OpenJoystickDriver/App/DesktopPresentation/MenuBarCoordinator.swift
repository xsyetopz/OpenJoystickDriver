#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  @MainActor final class DesktopPresentationCoordinator: NSObject, NSApplicationDelegate {
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
        button.toolTip = "OpenJoystickDriver"
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        if #available(macOS 11.0, *) {
          button.image = NSImage(
            systemSymbolName: "gamecontroller",
            accessibilityDescription: "OpenJoystickDriver"
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
      statusMenu = NSMenu(title: "OpenJoystickDriver")
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

      addNavigationItem(
        title: "Open Profiles…",
        pane: .profiles,
        symbol: "slider.horizontal.3",
        to: menu
      )
      addNavigationItem(
        title: "Controllers…",
        pane: .controllers,
        symbol: "gamecontroller",
        to: menu
      )
      addNavigationItem(title: "Debug…", pane: .debug, symbol: "ant", to: menu)
      if needsPermissionAttention {
        let request = NSMenuItem(
          title: "Request access…",
          action: #selector(requestAccessFromStatus(_:)),
          keyEquivalent: ""
        )
        request.target = self
        request.image = menuImage(symbol: "lock.shield")
        menu.addItem(request)
      }

      let refresh = NSMenuItem(
        title: "Refresh",
        action: #selector(refreshFromStatus(_:)),
        keyEquivalent: "r"
      )
      refresh.target = self
      refresh.keyEquivalentModifierMask = [.command]
      refresh.image = menuImage(symbol: "arrow.clockwise")
      menu.addItem(refresh)
      menu.addItem(.separator())

      let settings = NSMenuItem(
        title: "Settings…",
        action: #selector(openSettingsFromStatus(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.representedObject = SettingsPane.overview.rawValue
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      menu.addItem(settings)

      let quit = NSMenuItem(
        title: "Quit OpenJoystickDriver",
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
      case .loading: return "Starting…"
      case .available(let status): return "\(status.readinessLabel) · \(status.deviceCountLabel)"
      case .unavailable: return "Needs attention · Not available"
      case .error: return "Needs attention"
      }
    }

    private var activeProfileTitle: String {
      switch viewModel.remappingState {
      case .loading: return "Active profile: Checking…"
      case .unavailable(let message): return "Active profile unavailable · \(message)"
      case .error(let message): return "Active profile error · \(message)"
      case .available(let snapshot):
        let names = snapshot.activeProfiles.map(\.profileName)
        guard !names.isEmpty else { return "No active profile" }
        return names.count == 1 ? "Active profile: \(names[0])" : "\(names.count) active profiles"
      }
    }

    private var remappingNeedsRetry: Bool {
      switch viewModel.remappingState {
      case .unavailable, .error: return true
      case .loading, .available: return false
      }
    }

    private var needsPermissionAttention: Bool {
      guard case .available(let status) = viewModel.statusState else { return true }
      let needsPostEventAccess =
        status.requiresPostEventAccess == true && status.postEventAccess != .granted
      return !status.permissions.isReady || needsPostEventAccess
    }

    private func makeApplicationMenu() -> NSMenu {
      let menu = NSMenu(title: "OpenJoystickDriver")

      let applicationMenu = NSMenu(title: "OpenJoystickDriver")
      let settings = NSMenuItem(
        title: "Settings…",
        action: #selector(openSettings(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      applicationMenu.addItem(settings)
      let about = NSMenuItem(
        title: "About OpenJoystickDriver",
        action: #selector(showAbout(_:)),
        keyEquivalent: ""
      )
      about.target = self
      about.image = menuImage(symbol: "info.circle")
      applicationMenu.addItem(about)
      applicationMenu.addItem(.separator())
      let quit = NSMenuItem(
        title: "Quit OpenJoystickDriver",
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
      let editMenu = NSMenu(title: "Edit")
      editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
      editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
      editMenu.addItem(.separator())
      editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
      editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
      editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
      editMenu.addItem(
        withTitle: "Select All",
        action: #selector(NSText.selectAll(_:)),
        keyEquivalent: "a"
      )
      let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
      editItem.submenu = editMenu
      menu.addItem(editItem)

      let windowMenu = NSMenu(title: "Window")
      windowMenu.addItem(
        withTitle: "Minimize",
        action: #selector(NSWindow.performMiniaturize(_:)),
        keyEquivalent: "m"
      )
      windowMenu.addItem(
        withTitle: "Zoom",
        action: #selector(NSWindow.performZoom(_:)),
        keyEquivalent: ""
      )
      windowMenu.addItem(.separator())
      windowMenu.addItem(
        withTitle: "Bring All to Front",
        action: #selector(NSApplication.arrangeInFront(_:)),
        keyEquivalent: ""
      )
      let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
      windowItem.submenu = windowMenu
      menu.addItem(windowItem)
      NSApplication.shared.windowsMenu = windowMenu
      return menu
    }

    @objc private func showAbout(_ sender: Any?) {
      let alert = NSAlert()
      alert.messageText = "OpenJoystickDriver"
      alert.informativeText = "Version \(ApplicationVersion.current)\nController input for macOS"
      alert.alertStyle = .informational
      alert.addButton(withTitle: "Project page")
      alert.addButton(withTitle: "OK")
      if alert.runModal() == .alertFirstButtonReturn,
        let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver")
      {
        NSWorkspace.shared.open(url)
      }
    }
  }

  @MainActor final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.SettingsToolbar"
    )
    private static let paneGroupIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.SettingsPanes"
    )

    private let navigation: SettingsNavigationModel
    private var navigationObservation: AnyCancellable?

    init(
      viewModel: RuntimeViewModel,
      persistence: any SettingsPanePersistence = UserDefaultsSettingsPanePersistence()
    ) {
      navigation = SettingsNavigationModel(persistence: persistence)
      let rootView = SettingsRootView(navigation: navigation, viewModel: viewModel)
      let host = NSHostingView(rootView: rootView)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.minSize = NSSize(width: 680, height: 380)
      window.hidesOnDeactivate = false
      // Keep the production geometry separate from the retired oversized shell.
      window.setFrameAutosaveName("SettingsWindowGeometry")
      window.title = navigation.selectedPane.title
      window.isReleasedWhenClosed = false
      window.contentView = host
      window.center()
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      navigationObservation = navigation.$selectedPane.sink { [weak self] pane in
        guard let self, let window = self.window else { return }
        window.title = pane.title
        // Combine publishes this property in its willSet phase. Use the emitted pane rather than
        // reading navigation.selectedPane, which still contains the previous value here.
        self.updateToolbarSelection(for: pane)
      }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func show(pane: SettingsPane?) {
      if let pane { navigation.requestPane(pane) }
      window?.toolbar?.isVisible = true
      updateToolbarSelection()
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      // Hiding, rather than releasing, preserves the selected pane and the user's window geometry.
      sender.orderOut(nil)
      return false
    }

    private func configureToolbar(for window: NSWindow) {
      let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconAndLabel
      window.toolbar = toolbar
      toolbar.isVisible = true
    }

    private func updateToolbarSelection(for pane: SettingsPane? = nil) {
      guard
        let group = window?.toolbar?.items.first(where: {
          $0.itemIdentifier == Self.paneGroupIdentifier
        }) as? NSToolbarItemGroup,
        let index = SettingsPane.primaryCases.firstIndex(of: pane ?? navigation.selectedPane)
      else { return }
      group.selectedIndex = index
    }

    @objc private func selectPaneFromToolbar(_ sender: NSToolbarItemGroup) {
      guard SettingsPane.primaryCases.indices.contains(sender.selectedIndex) else {
        updateToolbarSelection()
        return
      }
      navigation.requestPane(SettingsPane.primaryCases[sender.selectedIndex])
      // A dirty profile editor may reject the request pending confirmation. Restore the current
      // selection immediately; accepted requests are applied again by the navigation observer.
      updateToolbarSelection()
    }
  }

  extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.paneGroupIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.paneGroupIdentifier]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      guard itemIdentifier == Self.paneGroupIdentifier else { return nil }
      let group = NSToolbarItemGroup(
        itemIdentifier: Self.paneGroupIdentifier,
        images: SettingsPane.primaryCases.map(\.toolbarImage),
        selectionMode: .selectOne,
        labels: SettingsPane.primaryCases.map(\.title),
        target: self,
        action: #selector(Self.selectPaneFromToolbar(_:))
      )
      group.controlRepresentation = .expanded
      group.label = "Settings panes"
      group.paletteLabel = "Settings panes"
      group.toolTip = "Settings panes"
      group.visibilityPriority = .high
      group.selectedIndex = SettingsPane.primaryCases.firstIndex(of: navigation.selectedPane) ?? 0
      return group
    }
  }

#else

  final class DesktopPresentationCoordinator {}

#endif
