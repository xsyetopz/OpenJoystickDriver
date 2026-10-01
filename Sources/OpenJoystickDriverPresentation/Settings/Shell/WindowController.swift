#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  enum SettingsWindowSizingPolicy {
    static let defaultContentSize = NSSize(width: 1_040, height: 700)
    static let minimumContentSize = NSSize(width: 800, height: 560)

    static func fittingContentSize(_ current: NSSize) -> NSSize {
      WindowFramePolicy.fittingSize(current, minimumSize: minimumContentSize)
    }

    @MainActor
    static func minimumFrameSize(for window: NSWindow) -> NSSize {
      window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
    }
  }

  @MainActor
  final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let toolbarIdentifier = NSToolbar.Identifier(
      "OpenJoystickDriver.SettingsToolbar"
    )
    private static let sidebarIdentifier = NSToolbarItem.Identifier(
      "OpenJoystickDriver.SettingsSidebar"
    )

    private let navigation: SettingsNavigationModel
    private let notificationPermission: NotificationPermissionModel
    private let preferences: SettingsPreferencesModel
    private let console: ConsoleViewModel
    private let developerTools: DeveloperToolsViewModel
    private let controllers: ControllersViewModel
    private let library: ProfileLibraryModel
    private let profiles: ProfilesViewModel
    private let visibilityChanged: @MainActor (Bool) -> Void
    private var developerToolsObservation: AnyCancellable?
    private var isEnforcingMinimumSize = false

    init(
      viewModel: RuntimeViewModel,
      supportReport: SupportReportModel,
      restartApplication: @escaping @MainActor () -> Void,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void,
      visibilityChanged: @escaping @MainActor (Bool) -> Void = { _ in },
      persistence: any SettingsPanePersistence = UserDefaultsSettingsPanePersistence()
    ) {
      self.visibilityChanged = visibilityChanged
      notificationPermission = NotificationPermissionModel()
      preferences = SettingsPreferencesModel()
      navigation = SettingsNavigationModel(
        persistence: persistence,
        developerToolsEnabled: preferences.developerToolsEnabled
      )
      console = ConsoleViewModel()
      developerTools = DeveloperToolsViewModel(gateway: viewModel.gateway)
      controllers = ControllersViewModel(runtime: viewModel)
      library = ProfileLibraryModel(runtime: viewModel)
      profiles = ProfilesViewModel()
      let rootView = SettingsRootView(
        navigation: navigation,
        viewModel: viewModel,
        supportReport: supportReport,
        notificationPermission: notificationPermission,
        preferences: preferences,
        console: console,
        developerTools: developerTools,
        controllers: controllers,
        library: library,
        profiles: profiles,
        restartApplication: restartApplication,
        openInputTest: openInputTest
      )
      let host = NSHostingView(rootView: rootView)
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: SettingsWindowSizingPolicy.defaultContentSize),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.hidesOnDeactivate = false
      window.title = OJDLocalized.string("app.name", fallback: "OpenJoystickDriver")
      window.isReleasedWhenClosed = false
      window.contentView = host
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      installSizingPolicy(on: window)
      developerToolsObservation = preferences.$developerToolsEnabled.dropFirst().sink {
        [weak self] enabled in
        guard let self else { return }
        self.navigation.setDeveloperToolsEnabled(enabled)
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(pane: SettingsPane?) {
      if let pane { navigation.requestPane(pane) }
      window?.toolbar?.isVisible = true
      if let window {
        let minimumFrameSize = SettingsWindowSizingPolicy.minimumFrameSize(for: window)
        window.contentMinSize = SettingsWindowSizingPolicy.minimumContentSize
        window.minSize = minimumFrameSize
        WindowFramePolicy.clamp(window, minimumSize: minimumFrameSize)
      }
      visibilityChanged(true)
      window?.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      // Hiding, rather than releasing, preserves the selected pane and the user's window geometry.
      sender.orderOut(nil)
      visibilityChanged(false)
      return false
    }

    func windowWillResize(_ sender: NSWindow, toFrameSize frameSize: NSSize) -> NSSize {
      WindowFramePolicy.fittingSize(
        frameSize,
        minimumSize: SettingsWindowSizingPolicy.minimumFrameSize(for: sender)
      )
    }

    func windowDidResize(_ notification: Notification) {
      guard !isEnforcingMinimumSize, let window = notification.object as? NSWindow else { return }
      let minimumFrameSize = SettingsWindowSizingPolicy.minimumFrameSize(for: window)
      let fittedFrame = WindowFramePolicy.fittingFrame(window.frame, minimumSize: minimumFrameSize)
      guard fittedFrame.size != window.frame.size else { return }
      isEnforcingMinimumSize = true
      window.setFrame(fittedFrame, display: true)
      isEnforcingMinimumSize = false
    }

    func windowDidChangeScreen(_ notification: Notification) {
      guard let window else { return }
      WindowFramePolicy.clamp(
        window,
        minimumSize: SettingsWindowSizingPolicy.minimumFrameSize(for: window)
      )
    }

    private func installSizingPolicy(on window: NSWindow) {
      window.contentMinSize = SettingsWindowSizingPolicy.minimumContentSize
      window.minSize = SettingsWindowSizingPolicy.minimumFrameSize(for: window)
      window.setContentSize(SettingsWindowSizingPolicy.defaultContentSize)

      let autosaveName = "SettingsWindowGeometry"
      let restoredFrame = window.setFrameUsingName(autosaveName)
      window.setFrameAutosaveName(autosaveName)
      if !restoredFrame { window.center() }
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
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

    @objc
    private func performToggleSidebar(_ sender: Any?) {
      NSApplication.shared.sendAction(
        #selector(NSSplitViewController.toggleSidebar(_:)),
        to: nil,
        from: sender
      )
    }
  }

  extension SettingsWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.sidebarIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [Self.sidebarIdentifier]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [] }

    func toolbar(
      _ toolbar: NSToolbar,
      itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
      willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
      guard itemIdentifier == Self.sidebarIdentifier else { return nil }
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      item.target = self
      item.action = #selector(performToggleSidebar(_:))
      item.label = OJDLocalized.string("settings.navigation", fallback: "Settings navigation")
      item.paletteLabel = item.label
      item.toolTip = item.label
      item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: item.label)
      return item
    }
  }

#endif
