#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  /// The SwiftUI content of one pane.
  private struct SettingsPaneContent: View {
    /// The pane to show.
    let pane: SettingsWindowPane
    /// The switches of General, Notifications and Advanced.
    let preferences: SettingsPreferencesModel
    /// The command-line tool link that Advanced shows.
    let commandLineTool: CommandLineToolModel
    /// The developer tools that Advanced shows while they are on.
    let developerTools: DeveloperToolsViewModel
    /// The driver extension state and actions that Advanced shows.
    let runtime: RuntimeViewModel

    /// The view of the pane.
    var body: some View {
      switch pane {
      case .general: GeneralPaneView(preferences: preferences)
      case .notifications: NotificationsPaneView(preferences: preferences)
      case .advanced:
        AdvancedPaneView(
          preferences: preferences,
          commandLineTool: commandLineTool,
          developerTools: developerTools,
          runtime: runtime
        )
      }
    }
  }

  /// The pane the Settings window shows: the content of the selected pane.
  private struct SettingsWindowContent: View {
    /// The selection of the pane.
    @ObservedObject
    var panes: SettingsWindowPaneModel
    /// Returns the content of a pane.
    let content: (SettingsWindowPane) -> SettingsPaneContent

    /// The content of the selected pane.
    var body: some View { content(panes.selected) }
  }

  /// The Settings window: toolbar buttons choose the pane, and the window title is the pane title.
  @MainActor
  final class SettingsWindowController: NSWindowController, NSWindowDelegate,
    SettingsWindowPresenting
  {
    /// The identifier of the Settings window's toolbar.
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.SettingsToolbar"
    )
    /// The selected pane.
    private let panes: SettingsWindowPaneModel
    /// The developer tools of Advanced; the window starts and stops their reads.
    let developerTools: DeveloperToolsViewModel
    /// The switches of General, Notifications and Advanced.
    private let preferences: SettingsPreferencesModel
    /// The command-line tool link of Advanced.
    private let commandLineTool: CommandLineToolModel
    /// Whether the app left the foreground after the window last read the pane state, so that
    /// coming back reads it once; showing the window reads it and clears this, so the activation
    /// that follows a show reads nothing more.
    private var refreshOnActivation = false
    /// Whether the window is on screen.
    private var isShown = false
    /// Whether the developer tools are reading controller diagnostics.
    private var developerToolsAreRunning = false
    /// The toolbar whose buttons choose the pane.
    private weak var toolbar: NSToolbar?
    /// Called with true when the window is shown and false when it closes.
    private let visibilityChanged: @MainActor (Bool) -> Void
    /// Returns the content of a pane, for the window and for measuring a pane's height.
    private let makeContent: (SettingsWindowPane) -> SettingsPaneContent
    /// The subscriptions that fit the window to its content and read the pane state on activation.
    private var contentChanges: [AnyCancellable] = []
    /// Fits the window to the pane after its content changes.
    private var fitting: RunLoopCoalescer?

    /// Creates the Settings window with the General pane selected.
    ///
    /// - Parameters:
    ///   - gateway: the service connection the developer tools in Advanced read.
    ///   - runtime: the driver extension state and actions of Advanced.
    ///   - preferences: the switches of General, Notifications and Advanced.
    ///   - commandLineTool: the command-line tool link of Advanced.
    ///   - visibilityChanged: called with true when the window is shown and false when it closes.
    init(
      gateway: any ApplicationServiceGateway,
      runtime: RuntimeViewModel,
      preferences: SettingsPreferencesModel,
      commandLineTool: CommandLineToolModel,
      visibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
      self.visibilityChanged = visibilityChanged
      self.preferences = preferences
      self.commandLineTool = commandLineTool
      panes = SettingsWindowPaneModel()
      developerTools = DeveloperToolsViewModel(gateway: gateway)
      let developerTools = developerTools
      let makeContent = { (pane: SettingsWindowPane) in
        SettingsPaneContent(
          pane: pane,
          preferences: preferences,
          commandLineTool: commandLineTool,
          developerTools: developerTools,
          runtime: runtime
        )
      }
      self.makeContent = makeContent
      let window = SettingsWindow(
        contentRect: NSRect(
          x: 0,
          y: 0,
          width: SettingsWindowPane.contentWidth,
          height: SettingsWindowPane.minimumContentHeight
        ),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      window.isReleasedWhenClosed = false
      window.hidesOnDeactivate = false
      let hostingView = NSHostingView(
        rootView: SettingsWindowContent(panes: panes, content: makeContent)
      )
      // The window height follows the pane through `paneChanged`, capped to the screen. The
      // hosting view sits in a container that positions it by autoresizing and has no
      // constraints, so on every macOS version the content's ideal height cannot become the
      // window's minimum size (on macOS 12, which has no `sizingOptions`, this container is the
      // only guard); macOS 13 and later also stop the hosting view from sizing itself.
      if #available(macOS 13, *) { hostingView.sizingOptions = [] }
      let container = NSView(
        frame: NSRect(x: 0, y: 0, width: SettingsWindowPane.contentWidth, height: 0)
      )
      hostingView.translatesAutoresizingMaskIntoConstraints = true
      hostingView.frame = container.bounds
      hostingView.autoresizingMask = [.width, .height]
      container.addSubview(hostingView)
      window.contentView = container
      super.init(window: window)
      window.delegate = self
      configureToolbar(on: window)
      paneChanged(animated: false)
      window.center()
      fitting = RunLoopCoalescer { [weak self] in
        self?.syncDeveloperTools()
        guard self?.window?.isVisible == true else { return }
        self?.paneChanged(animated: true)
      }
      // Each publisher announces a change before it is applied; the coalescer measures on a later
      // turn, once the content shows it. Fitting changes only the window, never these models.
      contentChanges = [
        preferences.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        developerTools.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        commandLineTool.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        runtime.objectWillChange.sink { [weak self] _ in self?.fitting?.schedule() },
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
          .sink { [weak self] _ in self?.refreshOnActivation = true },
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
          .sink { [weak self] _ in
            guard self?.refreshOnActivation == true else { return }
            self?.refreshOnActivation = false
            self?.refreshPaneState()
          },
        NotificationCenter.default.publisher(
          for: NSApplication.didChangeScreenParametersNotification
        ).sink { [weak self] _ in self?.paneChanged(animated: false) },
      ]
    }

    /// Unavailable, because the window controller is created in code only.
    ///
    /// - Parameter coder: The decoder, which is not used.
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Shows the Settings window in front, on `pane` when given and otherwise on the selected pane.
    func showSettings(pane: SettingsWindowPane?) {
      if let pane {
        panes.select(pane)
        paneChanged(animated: window?.isVisible == true)
      }
      isShown = true
      syncDeveloperTools()
      refreshPaneState()
      refreshOnActivation = false
      visibilityChanged(true)
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Fits the window to the screen it moved to, whose visible area may be smaller.
    ///
    /// - Parameter notification: The notification of the screen change.
    func windowDidChangeScreen(_ notification: Notification) { paneChanged(animated: false) }

    /// Marks the window as hidden, syncs the developer tools and reports that it is not visible.
    ///
    /// - Parameter notification: The notification of the closing window.
    func windowWillClose(_ notification: Notification) {
      isShown = false
      syncDeveloperTools()
      visibilityChanged(false)
    }

    /// Reads the state the selected pane shows from the system: the notification permission for
    /// Notifications, the command-line tool link for Advanced.
    ///
    /// The window drives these reads, so the offscreen view that measures a pane never starts them.
    func refreshPaneState() {
      guard isShown else { return }
      switch panes.selected {
      case .general: break
      case .notifications: preferences.refreshNotificationAuthorization()
      case .advanced: commandLineTool.refresh()
      }
    }

    /// Reads the controller diagnostics while the window shows Advanced with developer tools on,
    /// and stops them otherwise.
    ///
    /// This is the only place that starts or stops the reads.
    func syncDeveloperTools() {
      let wanted = isShown && panes.selected == .advanced && preferences.developerToolsEnabled
      guard wanted != developerToolsAreRunning else { return }
      developerToolsAreRunning = wanted
      if wanted { developerTools.requestRefresh() } else { developerTools.close() }
    }

    /// Adds the toolbar whose buttons choose the pane.
    private func configureToolbar(on window: NSWindow) {
      let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconAndLabel
      window.toolbar = toolbar
      window.toolbarStyle = .preference
      self.toolbar = toolbar
    }

    /// Sets the title of the selected pane and resizes the window's height to the pane's height,
    /// keeping its top edge in place unless the window would then leave the screen's visible area.
    private func paneChanged(animated: Bool) {
      guard let window else { return }
      window.title = OJDLocalized.string(panes.titleKey)
      toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(
        panes.selected.toolbarItemIdentifier
      )
      let fitting = fittingHeight(of: panes.selected)
      let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
      let visibleHeight =
        (window.screen ?? NSScreen.main)?.visibleFrame.height ?? .greatestFiniteMagnitude
      let size = SettingsWindowPane.contentSize(
        fittingHeight: fitting,
        availableHeight: SettingsWindowPane.availableContentHeight(
          visibleHeight: visibleHeight,
          chromeHeight: chrome
        )
      )
      guard
        window.contentRect(forFrameRect: window.frame).size
          != NSSize(
            width: size.width,
            height: size.height
          )
      else { return }
      var frame = window.frameRect(
        forContentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height)
      )
      frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
      if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
      }
      window.setFrame(frame, display: true, animate: animated)
    }

    /// The height the pane's content takes at the window's width.
    private func fittingHeight(of pane: SettingsWindowPane) -> Double {
      let probe = NSHostingView(
        rootView: makeContent(pane).frame(width: SettingsWindowPane.contentWidth)
          .fixedSize(horizontal: false, vertical: true)
      )
      return Double(probe.fittingSize.height)
    }

    /// Selects the pane of the clicked toolbar button.
    @objc
    private func paneButtonClicked(_ sender: NSToolbarItem) {
      guard let pane = SettingsWindowPane(toolbarItemIdentifier: sender.itemIdentifier.rawValue)
      else { return }
      panes.select(pane)
      syncDeveloperTools()
      refreshPaneState()
      paneChanged(animated: true)
    }
  }

  extension SettingsWindowController: NSToolbarDelegate {
    /// The toolbar item identifiers of the panes, in order.
    private var paneIdentifiers: [NSToolbarItem.Identifier] {
      panes.panes.map { NSToolbarItem.Identifier($0.toolbarItemIdentifier) }
    }

    /// Returns the identifiers of the panes.
    ///
    /// - Parameter toolbar: The toolbar of the window.
    /// - Returns: The identifiers, in the order of the panes.
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      paneIdentifiers
    }

    /// Returns the identifiers of the panes.
    ///
    /// - Parameter toolbar: The toolbar of the window.
    /// - Returns: The identifiers, in the order of the panes.
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      paneIdentifiers
    }

    /// Returns the identifiers of the panes.
    ///
    /// - Parameter toolbar: The toolbar of the window.
    /// - Returns: The identifiers, in the order of the panes.
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      paneIdentifiers
    }

    /// Creates the toolbar button of a pane.
    ///
    /// - Parameters:
    ///   - toolbar: The toolbar of the window.
    ///   - itemIdentifier: The identifier of the pane.
    ///   - flag: Whether the toolbar inserts the item.
    /// - Returns: The item with the pane's title, symbol and description, or nil for an identifier
    ///   that names no pane.
    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      guard let pane = SettingsWindowPane(toolbarItemIdentifier: itemIdentifier.rawValue)
      else { return nil }
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      let title = OJDLocalized.string(pane.titleKey)
      let description = OJDLocalized.string(pane.accessibilityKey)
      item.label = title
      item.paletteLabel = title
      item.toolTip = description
      item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: description)
      item.target = self
      item.action = #selector(paneButtonClicked(_:))
      return item
    }
  }

#endif
