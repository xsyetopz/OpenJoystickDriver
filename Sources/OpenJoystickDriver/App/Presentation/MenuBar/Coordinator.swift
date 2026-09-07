#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  enum MenuBarStatusItemImage {
    static let statusItemSize = NSSize(width: 18, height: 18)

    static func make(applicationIcon: NSImage?, accessibilityDescription: String) -> NSImage? {
      if let icon = scaledApplicationIcon(applicationIcon) { return icon }
      return templateSymbol(accessibilityDescription: accessibilityDescription)
    }

    static func scaledApplicationIcon(_ icon: NSImage?) -> NSImage? {
      guard let icon, icon.isValid, !icon.representations.isEmpty else { return nil }
      guard icon.size.width > 0, icon.size.height > 0 else { return nil }
      guard let copy = icon.copy() as? NSImage else { return nil }
      copy.size = statusItemSize
      return copy
    }

    static func templateSymbol(accessibilityDescription: String) -> NSImage? {
      guard #available(macOS 11.0, *) else { return nil }
      let image = NSImage(
        systemSymbolName: "gamecontroller",
        accessibilityDescription: accessibilityDescription
      )
      image?.isTemplate = true
      return image
    }
  }

  enum MenuBarTerminateRelaunchPolicy {
    static let logOutReason: OSType = 0x6C6F676F
    static let reallyLogOutReason: OSType = 0x726C676F
    static let shutDownReason: OSType = 0x73687574
    static let restartReason: OSType = 0x72657374
    static let waiterInterpreterPath = "/bin/sh"
    static let openToolPath = "/usr/bin/open"

    enum FollowUp: Equatable, Sendable {
      case none
      case retireStaleJob
      case relaunch
    }

    struct TerminateWaiter: Equatable, Sendable {
      var interpreterPath: String { MenuBarTerminateRelaunchPolicy.waiterInterpreterPath }
      var openToolPath: String { MenuBarTerminateRelaunchPolicy.openToolPath }
      var createsNewSession: Bool { true }
      let parentProcessIdentifier: Int32
      let bundleURL: URL
      let openAfterParentExits: Bool

      var arguments: [String] {
        [
          interpreterPath,
          "-c",
          MenuBarTerminateRelaunchPolicy.waiterScript,
          "openjoystickdriver-terminate-waiter",
          String(parentProcessIdentifier),
          bundleURL.path,
          openToolPath,
          openAfterParentExits ? "1" : "0",
        ]
      }
    }

    /// TCC “Quit & Reopen” is a generic Apple Event quit with no session-end
    /// reason. Menu Quit and SIGTERM must not relaunch. Session-end Apple Events
    /// (log out / shut down / restart) must not spawn a waiter.
    static func followUp(
      userInitiatedQuit: Bool,
      signalInitiatedQuit: Bool,
      appleEventQuitReason: OSType?
    ) -> FollowUp {
      switch appleEventQuitReason {
      case logOutReason, reallyLogOutReason, shutDownReason, restartReason: return .none
      default: break
      }
      if userInitiatedQuit || signalInitiatedQuit { return .retireStaleJob }
      return .relaunch
    }

    static func shouldRelaunch(
      userInitiatedQuit: Bool,
      signalInitiatedQuit: Bool,
      appleEventQuitReason: OSType?
    ) -> Bool {
      followUp(
        userInitiatedQuit: userInitiatedQuit,
        signalInitiatedQuit: signalInitiatedQuit,
        appleEventQuitReason: appleEventQuitReason
      ) == .relaunch
    }

    static func terminateWaiter(
      parentProcessIdentifier: Int32,
      bundleURL: URL,
      followUp: FollowUp
    ) -> TerminateWaiter? {
      guard followUp != .none else { return nil }
      guard bundleURL.pathExtension == "app" else { return nil }
      return TerminateWaiter(
        parentProcessIdentifier: parentProcessIdentifier,
        bundleURL: bundleURL,
        openAfterParentExits: followUp == .relaunch
      )
    }

    /// Spawns `/bin/sh` in a new session. The waiter waits until this PID is no
    /// longer a live process (including zombie/exiting rss 0), boots out leftover
    /// Launch Services jobs whose pid is dead, then optionally opens the `.app`
    /// bundle via Launch Services. Do not exec the Mach-O. Do not spawn while
    /// this process is still the Launch Services job.
    static func spawnTerminateWaiter(followUp: FollowUp) {
      guard
        let waiter = terminateWaiter(
          parentProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
          bundleURL: Bundle.main.bundleURL,
          followUp: followUp
        )
      else { return }
      spawn(waiter)
    }

    private static let waiterScript = """
      trap "" HUP
      parent="$1"
      target="$2"
      open_tool="$3"
      should_open="$4"
      process_is_live() {
        /bin/ps -p "$1" -o state=,rss= 2>/dev/null | /usr/bin/awk '{
          s=toupper($1); rss=$2+0;
          if (index(s,"Z") || index(s,"E")) { print 0; exit }
          if (rss<=0) { print 0; exit }
          print 1
        }'
      }
      while /bin/kill -0 "$parent" 2>/dev/null; do
        [ "$(process_is_live "$parent")" = "1" ] || break
        /bin/sleep 0.05
      done
      uid=$(/usr/bin/id -u)
      /bin/launchctl print "gui/$uid" 2>/dev/null | /usr/bin/awk '
        $NF ~ /^application\\.com\\.openjoystickdriver\\./ { print $NF }
      ' | while IFS= read -r label; do
        [ -n "$label" ] || continue
        info=$(/bin/launchctl print "gui/$uid/$label" 2>/dev/null) || continue
        pid=$(printf '%s\\n' "$info" | /usr/bin/awk '/^[[:space:]]*pid = / { print $3; exit }')
        if [ -n "$pid" ] && [ "$(process_is_live "$pid")" = "1" ]; then
          continue
        fi
        /bin/launchctl bootout "gui/$uid/$label" >/dev/null 2>&1
      done
      [ "$should_open" = "1" ] || exit 0
      exec "$open_tool" -- "$target"
      """

    private static func spawn(_ waiter: TerminateWaiter) {
      var spawnedProcessIdentifier: pid_t = 0
      var attributes: posix_spawnattr_t?
      guard posix_spawnattr_init(&attributes) == 0 else {
        writeSpawnFailure(errno)
        return
      }
      defer { posix_spawnattr_destroy(&attributes) }
      posix_spawnattr_setflags(
        &attributes,
        Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT)
      )

      var fileActions: posix_spawn_file_actions_t?
      guard posix_spawn_file_actions_init(&fileActions) == 0 else {
        writeSpawnFailure(errno)
        return
      }
      defer { posix_spawn_file_actions_destroy(&fileActions) }
      posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
      posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
      posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

      var argv = waiter.arguments.map { argument in
        argument.withCString { strdup($0) }
      }
      defer {
        for pointer in argv {
          if let pointer { free(pointer) }
        }
      }
      guard argv.allSatisfy({ $0 != nil }) else {
        writeSpawnFailure(ENOMEM)
        return
      }
      argv.append(nil)

      let status = waiter.interpreterPath.withCString { path in
        argv.withUnsafeMutableBufferPointer { buffer in
          posix_spawn(
            &spawnedProcessIdentifier,
            path,
            &fileActions,
            &attributes,
            buffer.baseAddress,
            environ
          )
        }
      }
      if status != 0 { writeSpawnFailure(status) }
    }

    private static func writeSpawnFailure(_ status: Int32) {
      let detail = String(cString: strerror(status))
      FileHandle.standardError.write(
        Data("[OpenJoystickDriver] Could not relaunch: \(detail)\n".utf8)
      )
    }
  }

  @MainActor final class MenuBarCoordinator: NSObject, NSApplicationDelegate {
    let runtime: ApplicationServiceRuntime
    let viewModel: RuntimeViewModel

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsWindowController: SettingsWindowController?
    private var inputTestWindowController: InputTestWindowController?
    private var liveStatusTimer: Timer?
    private let notificationMonitor = RuntimeNotificationMonitor()
    private let notificationPresenter = RuntimeNotificationCenterDelegate()
    private var liveStatusRefreshInFlight = false
    private var isStopping = false
    private var userInitiatedQuit = false
    private var signalInitiatedQuit = false
    private static weak var activeCoordinator: MenuBarCoordinator?

    init(runtime: ApplicationServiceRuntime, gateway: any ApplicationServiceGateway) {
      self.runtime = runtime
      self.viewModel = RuntimeViewModel(gateway: gateway)
      super.init()
    }

    func run() -> Never {
      Self.activeCoordinator = self
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
      Task { @MainActor in await viewModel.startSystemExtensionSetup() }
      liveStatusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        guard let self else { return }
        Task { @MainActor in self.refreshLiveStatus() }
      }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
      Task { @MainActor in await viewModel.refreshSystemExtensionSetup() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
      guard !isStopping else { return .terminateNow }
      isStopping = true
      let followUp = MenuBarTerminateRelaunchPolicy.followUp(
        userInitiatedQuit: userInitiatedQuit,
        signalInitiatedQuit: signalInitiatedQuit,
        appleEventQuitReason: Self.currentAppleEventQuitReason()
      )
      removeStatusItem()
      inputTestWindowController?.stop()
      Task { @MainActor [weak self, weak sender] in
        guard let self else { return }
        await self.runtime.stop()
        MenuBarTerminateRelaunchPolicy.spawnTerminateWaiter(followUp: followUp)
        sender?.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    }

    func terminateFromShutdownSignal() {
      signalInitiatedQuit = true
      NSApplication.shared.terminate(nil)
    }

    @discardableResult static func terminateFromShutdownSignalIfRunning() -> Bool {
      guard let activeCoordinator else { return false }
      activeCoordinator.terminateFromShutdownSignal()
      return true
    }

    private static func currentAppleEventQuitReason() -> OSType? {
      let keyword: AEKeyword = 0x77687920
      let code =
        NSAppleEventManager.shared().currentAppleEvent?
        .paramDescriptor(forKeyword: keyword)?.enumCodeValue ?? 0
      return code == 0 ? nil : code
    }

    func applicationWillTerminate(_ notification: Notification) { removeStatusItem() }

    @objc func openSettings(_ sender: Any?) { openSettings(pane: .settings) }

    @objc func showApplication(_ sender: Any?) { openSettings(pane: nil) }

    @objc func openSettingsFromStatus(_ sender: Any?) {
      let item = sender as? NSMenuItem
      let pane = item.flatMap { SettingsPane(rawValue: $0.representedObject as? String ?? "") }
      openSettings(pane: pane ?? .overview)
    }

    @objc func refreshFromStatus(_ sender: Any?) { refreshLiveStatus() }

    @objc func quit(_ sender: Any?) {
      userInitiatedQuit = true
      NSApplication.shared.terminate(sender)
    }

    private func openSettings(pane: SettingsPane?) {
      if settingsWindowController == nil {
        settingsWindowController = SettingsWindowController(viewModel: viewModel) {
          [weak self] device in self?.openInputTest(for: device)
        }
      }
      settingsWindowController?.show(pane: pane)
    }

    private func openInputTest(for device: ApplicationServiceDeviceDescription) {
      if inputTestWindowController == nil {
        inputTestWindowController = InputTestWindowController(
          runtime: runtime,
          runtimeViewModel: viewModel
        )
      }
      inputTestWindowController?.show(device: device)
    }

    private func installStatusItem() {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      statusItem = item
      if let button = item.button {
        button.toolTip = OJDLocalized.string("app.name", fallback: "OpenJoystickDriver")
        button.target = self
        button.action = #selector(showStatusMenu(_:))
        if let image = MenuBarStatusItemImage.make(
          applicationIcon: NSImage(named: NSImage.applicationIconName),
          accessibilityDescription: OJDLocalized.string(
            "app.name",
            fallback: "OpenJoystickDriver"
          )
        ) {
          button.image = image
        }
        if button.image == nil {
          // Text is an intentional final fallback for an unbundled debug executable.
          button.title = "OJ"
        }
      }
      statusMenu = NSMenu(title: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver"))
      // Use the action path rather than assigning a menu directly so each opening refreshes its
      // snapshot before the menu is shown.
      item.menu = nil
    }

    private func removeStatusItem() {
      liveStatusTimer?.invalidate()
      liveStatusTimer = nil
      guard let item = statusItem else { return }
      NSStatusBar.system.removeStatusItem(item)
      statusItem = nil
      statusMenu = nil
    }

    @objc private func showStatusMenu(_ sender: Any?) {
      refreshLiveStatus()
      guard let menu = statusMenu, let button = statusItem?.button else { return }
      // Pop up the same native menu on every click after the asynchronous status refresh starts.
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func refreshStatus() {
      updateStatusMenu()
      Task { @MainActor [weak self] in
        guard let self else { return }
        await viewModel.refreshSystemExtensionSetup()
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
        let statusChanged = await viewModel.refreshLiveStatus()
        notificationMonitor.observe(RuntimeNotificationSnapshot(viewModel: viewModel))
        if statusChanged { updateStatusMenu() }
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
          item.image = controllerMenuImage(
            for: PublishedVirtualIdentity.presentation(
              for: device,
              requested: viewModel.requestedCompatibilityIdentity
            )
          )
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
      guard #available(macOS 11.0, *) else { return nil }
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      image?.isTemplate = true
      return image
    }

    private func controllerMenuImage(for presentation: VirtualIdentityPresentation) -> NSImage? {
      if let image = menuImage(symbol: presentation.controllerSymbolName) { return image }
      return menuImage(symbol: presentation.controllerSymbolFallback)
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
