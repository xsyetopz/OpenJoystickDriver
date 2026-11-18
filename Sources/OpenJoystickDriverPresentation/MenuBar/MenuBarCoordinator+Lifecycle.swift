#if canImport(AppKit) && canImport(SwiftUI)

  package import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  extension MenuBarCoordinator {

    /// Runs the app until it quits and then exits the process; it never returns.
    package func run() -> Never {
      Self.activeCoordinator = self
      let application = NSApplication.shared
      application.setActivationPolicy(.accessory)
      application.delegate = self
      // Set once, before the first window exists: the app's windows are never tabbed, so AppKit
      // adds no Show Tab Bar or Show All Tabs items to the View menu.
      NSWindow.allowsAutomaticWindowTabbing = false
      makeWindows()
      application.mainMenu = makeApplicationMenu()
      application.run()

      // Normal termination has already awaited stopRuntime() in applicationShouldTerminate.
      // Exit only after AppKit has completed that reply; the signal path retains its own exit path.
      exit(0)
    }

    /// Connects the notification center, the settings, the Dock icon, the menu-bar item and the
    /// live updates, then offers settings recovery when the file cannot be read.
    package func applicationDidFinishLaunching(_: Notification) {
      bundledNotificationCenter?.delegate = notificationPresenter
      refreshStatus()
      Task { @MainActor in viewModel.startSystemExtensionSetup() }
      preferences.settingsRecovered = { [weak self] in
        guard let self else { return }
        SettingsRecoveryFollowUp(
          updateCheck: launchUpdateCheck,
          registerLogin: Self.registerLoginIfNeeded
        ).run()
      }
      if case .skippedSettingsUnreadable(let error) = launchUpdateCheck.run() {
        SettingsSkipLog.write(
          feature: "the launch update check",
          file: error.file ?? "",
          error: error
        )
      }
      showInDockObservation = preferences.$showInDock.removeDuplicates().sink {
        [weak self] shown in self?.dockIcon.showsAlways = shown
      }
      showInMenuBarObservation = Publishers.CombineLatest(
        preferences.$showInMenuBar,
        preferences.$settingsFileError
      ).map { SettingsFileStartup.statusItemIsShown(showInMenuBar: $0, settingsError: $1) }
        .removeDuplicates().sink { [weak self] shown in self?.applyShowInMenuBar(shown) }
      mainMenuVisibilityObservation = Publishers.CombineLatest(
        preferences.$interfaceLevel,
        preferences.$developerToolsEnabled
      ).dropFirst().sink {
        [weak self] level, developer in
        NSApplication.shared.mainMenu = self?.makeApplicationMenu(
          level: level,
          developerToolsEnabled: developer
        )
      }
      let hotKey = PauseHotKey { [weak self] in
        guard let self else { return }
        Task { @MainActor in await self.viewModel.togglePauseAll() }
      }
      pauseHotKey = hotKey
      pauseShortcutObservation = preferences.$pauseShortcut.removeDuplicates().sink {
        [preferences] shortcut in
        do { try hotKey.register(shortcut) } catch { preferences.pauseShortcutRefused() }
      }
      if SettingsFileStartup.opensMainWindowAtLaunch(settingsError: preferences.settingsFileError) {
        mainWindow?.showMainWindow(area: nil)
      }
      Task { @MainActor in self.offerSettingsRecovery() }
      let updates = ControllerLiveUpdates(
        source: gatewayChangeSource,
        answerTestNotification: { [preferences] in preferences.answerTestNotification($0) },
        modeChanged: { [weak self] mode in
          if case .polling(let failure, _) = mode {
            self?.viewModel.liveUpdatesFallbackReason = failure
          } else {
            self?.viewModel.liveUpdatesFallbackReason = nil
          }
        },
        refresh: { [weak self] in await self?.refreshLiveStatusNow() }
      )
      controllerLiveUpdates = updates
      updates.start()
    }

    /// The launch update check, as the settings enable it.
    private var launchUpdateCheck: LaunchUpdateCheck {
      LaunchUpdateCheck(
        settingsError: { [preferences] in preferences.settingsFileError },
        isEnabled: { [preferences] in preferences.checkUpdatesAutomatically },
        check: { [preferences] in preferences.checkForUpdates(announcingAvailableUpdate: true) }
      )
    }

    /// Registers the login item unless the user opted out; only an installed app has one.
    private static func registerLoginIfNeeded() throws {
      guard Bundle.main.bundleURL.pathExtension == "app" else { return }
      try ApplicationServiceManager.installByDefaultIfNeeded()
    }

    /// Asks what to do about a settings file that cannot be used, and asks again while a reset
    /// leaves it unusable; `note` goes before the reason.
    func offerSettingsRecovery(note: String? = nil) {
      guard
        case .offerRecovery(let error) = SettingsFileStartup.decide(
          settingsError: preferences.settingsFileError
        )
      else { return }
      let reason = [note, preferences.errorMessage ?? error.localizedDescription]
        .compactMap { $0 }.joined(separator: "\n\n")
      var offersMigration = false
      if case .unsupported = error { offersMigration = true }
      switch SettingsUnreadableChoice(
        response: SettingsUnreadableAlert.make(reason: reason, offersMigration: offersMigration)
          .runActivatingApp(),
        offersMigration: offersMigration
      )
      {
      case .migrate:
        let failed = DocumentMigrator().run(dryRun: false).contains { $0.verdict == .failed }
        preferences.reloadSettings()
        offerSettingsRecovery(
          note: failed ? OJDLocalized.string("platform.macos.ui.migrate.failed") : nil
        )
      case .showInFinder: preferences.showSettingsFileInFinder()
      case .resetSettings:
        preferences.resetSettings()
        offerSettingsRecovery()
      case .quit: NSApplication.shared.terminate(nil)
      }
    }

    /// Reads the driver extension setup again when the app becomes active.
    package func applicationDidBecomeActive(_: Notification) {
      Task { @MainActor in viewModel.refreshSystemExtensionSetup() }
    }

    /// Reads the live status, opens the main window and returns true.
    package func applicationShouldHandleReopen(
      _: NSApplication,
      hasVisibleWindows _: Bool
    ) -> Bool {
      refreshLiveStatus()
      mainWindow?.showMainWindow(area: nil)
      return true
    }

    /// Stops the live status, the menu-bar item, the Input Test window and the runtime before the
    /// app quits.
    package func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
    {
      termination.request {
        self.stopLiveStatus()
        self.removeStatusItem()
        self.inputTestWindowController?.stop()
        await self.stopRuntime()
      } relaunch: {
        await self.relaunchApplication()
      } reply: {
        sender.reply(toApplicationShouldTerminate: true)
      }
    }

    /// Quits the app after a shutdown signal.
    func terminateFromShutdownSignal() { NSApplication.shared.terminate(nil) }

    /// Quits the running coordinator after a shutdown signal and returns whether one was running.
    @discardableResult
    package static func terminateFromShutdownSignalIfRunning() -> Bool {
      guard let activeCoordinator else { return false }
      activeCoordinator.terminateFromShutdownSignal()
      return true
    }

    /// Stops the live status and removes the menu-bar item when the app terminates.
    package func applicationWillTerminate(_: Notification) {
      stopLiveStatus()
      removeStatusItem()
    }

    /// Quits the app from the Quit menu item.
    @objc
    func quit(_ sender: Any?) { NSApplication.shared.terminate(sender) }

    /// Quits the app and relaunches it after the teardown.
    private func restartApplication() {
      termination.requestRelaunch { NSApplication.shared.terminate(nil) }
    }

    /// Opens a new instance of the app and logs a failure to standard error.
    private func relaunchApplication() async {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      await withCheckedContinuation { continuation in
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        { _, error in
          if let error {
            unsafe fputs("Failed to relaunch OpenJoystickDriver: \(error)\n", unsafe stderr)
          }
          continuation.resume()
        }
      }
    }

    /// Creates the main and Settings windows once; they hide on close and keep their state.
    func makeWindows() {
      mainWindow = MainWindowController(
        runtime: viewModel,
        supportReport: supportReport,
        preferences: preferences,
        restartApplication: { [weak self] in self?.restartApplication() },
        openInputTest: { [weak self] device in self?.openInputTest(for: device) },
        visibilityChanged: { [weak self] isOpen in self?.dockIcon.setOpen(.workbench, isOpen) }
      )
      settingsWindow = SettingsWindowController(
        gateway: gateway,
        runtime: viewModel,
        preferences: preferences,
        commandLineTool: commandLineTool
      ) { [weak self] isOpen in self?.dockIcon.setOpen(.settings, isOpen) }
    }

    /// Hiding the status item opens the main window, so the change shows where the app is now.
    private func applyShowInMenuBar(_ shown: Bool) {
      if shown {
        guard statusItem == nil else { return }
        installStatusItem()
      } else {
        removeStatusItem()
        mainWindow?.showMainWindow(area: nil)
      }
    }

    /// Shows the Input Test window for `device`, creating the window when needed.
    private func openInputTest(for device: ApplicationServiceDeviceDescription) {
      if inputTestWindowController == nil {
        inputTestWindowController = InputTestWindowController(
          gateway: gateway,
          runtimeViewModel: viewModel
        ) { [weak self] isOpen in self?.dockIcon.setOpen(.inputTest, isOpen) }
      }
      inputTestWindowController?.show(device: device)
    }

    /// Adds the menu-bar item with its image, tooltip and menu.
    private func installStatusItem() {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      statusItem = item
      item.behavior = .removalAllowed
      // macOS keeps the visibility of an item that the user dragged out, and the setting decides.
      item.isVisible = true
      statusItemVisibilityObservation = item.observe(\.isVisible) { [weak self] item, _ in
        guard !item.isVisible else { return }
        Task { @MainActor in self?.statusItemRemoved() }
      }
      if let button = item.button {
        button.toolTip = OJDLocalized.string("ui.help.statusItem")
      }
      frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.refreshLiveStatus() }
      }
      statusMenuTracker.onWillOpen = { [weak self] in self?.refreshLiveStatus() }
      // The menu runs the chosen item's action after it closes; rebuilding first would
      // release that item.
      statusMenuTracker.onDidClose = { [weak self] in
        DispatchQueue.main.async { self?.updateStatusMenu() }
      }
      updateStatusMenu()
    }

    /// Stops following the service's changes.
    private func stopLiveStatus() {
      controllerLiveUpdates?.stop()
      controllerLiveUpdates = nil
    }

    /// Handles the user dragging the status item out of the menu bar.
    ///
    /// The Show in Menu Bar setting turns off, which removes the item and opens the main window.
    /// The item returns when the setting cannot be stored.
    private func statusItemRemoved() {
      guard let item = statusItem, !item.isVisible else { return }
      if !preferences.menuBarItemRemoved() { item.isVisible = true }
    }

    /// Removes the menu-bar item and its menu.
    private func removeStatusItem() {
      guard let item = statusItem else { return }
      statusItemVisibilityObservation = nil
      frontAppObserver.map(NSWorkspace.shared.notificationCenter.removeObserver)
      frontAppObserver = nil
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
      statusMenu = nil
    }

    /// Rebuilds the status menu, reads the service status and then rebuilds the menu again.
    private func refreshStatus() {
      updateStatusMenu()
      Task { @MainActor [weak self] in
        guard let self else { return }
        await menuBarViewModel.refresh()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        updateStatusMenu()
      }
    }

    /// Reads the live service status in the background.
    private func refreshLiveStatus() {
      Task { @MainActor [weak self] in await self?.refreshLiveStatusNow() }
    }

    /// Reads the live service status and rebuilds the status menu when it changed.
    private func refreshLiveStatusNow() async {
      let statusChanged = await menuBarViewModel.refreshLiveStatus()
      notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
      if statusChanged { updateStatusMenu() }
    }

    /// Installs the current menu as the status item's menu, which AppKit places under the button.
    ///
    /// An open menu is left alone and replaced when it closes.
    private func updateStatusMenu() {
      guard !statusMenuTracker.isOpen else { return }
      let state = menuBarViewModel.statusItemState
      let menu = makeStatusMenu(
        from: StatusItemModel.entries(for: state),
        title: OJDLocalized.string("term.app.name")
      )
      menu.delegate = statusMenuTracker
      statusMenu = menu
      statusItem?.menu = menu
      if let button = statusItem?.button {
        let label = menuTitle(StatusItemModel.accessibilityTitle(for: state))
        button.image = MenuBarStatusItemImage.make(
          symbolName: StatusItemModel.symbolName(for: state),
          accessibilityDescription: label
        )
        button.setAccessibilityLabel(label)
      }
    }
  }

#endif
