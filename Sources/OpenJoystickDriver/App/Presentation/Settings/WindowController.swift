#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  enum SettingsWindowSizingPolicy {
    static let defaultContentSize = NSSize(width: 700, height: 460)
    static let defaultMinimumContentSize = NSSize(width: 640, height: 400)

    static func minimumContentSize(for pane: SettingsPane) -> NSSize {
      switch pane {
      case .controllers: return NSSize(width: 900, height: 500)
      case .developer: return NSSize(width: 900, height: 620)
      case .overview, .profiles, .console, .settings: return defaultMinimumContentSize
      }
    }

    static func fittingContentSize(current: NSSize, minimum: NSSize) -> NSSize {
      NSSize(width: max(current.width, minimum.width), height: max(current.height, minimum.height))
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
    private let notificationPermission: NotificationPermissionModel
    private let preferences: SettingsPreferencesModel
    private let console: ConsoleViewModel
    private let developerTools: DeveloperToolsViewModel
    private var navigationObservation: AnyCancellable?
    private var developerToolsObservation: AnyCancellable?

    init(
      viewModel: RuntimeViewModel,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void,
      persistence: any SettingsPanePersistence = UserDefaultsSettingsPanePersistence()
    ) {
      notificationPermission = NotificationPermissionModel()
      preferences = SettingsPreferencesModel()
      navigation = SettingsNavigationModel(
        persistence: persistence,
        developerToolsEnabled: preferences.developerToolsEnabled
      )
      console = ConsoleViewModel()
      developerTools = DeveloperToolsViewModel(gateway: viewModel.gateway)
      let rootView = SettingsRootView(
        navigation: navigation,
        viewModel: viewModel,
        notificationPermission: notificationPermission,
        preferences: preferences,
        console: console,
        developerTools: developerTools,
        openInputTest: openInputTest
      )
      let host = NSHostingView(rootView: rootView)
      let initialMinimumSize = SettingsWindowSizingPolicy.minimumContentSize(
        for: navigation.selectedPane
      )
      let initialContentSize = SettingsWindowSizingPolicy.fittingContentSize(
        current: SettingsWindowSizingPolicy.defaultContentSize,
        minimum: initialMinimumSize
      )
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: initialContentSize),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.contentMinSize = initialMinimumSize
      window.hidesOnDeactivate = false
      window.setFrameAutosaveName("SettingsWindowGeometry")
      window.title = navigation.selectedPane.title
      window.isReleasedWhenClosed = false
      window.contentView = host
      let restoredContentSize = window.contentView?.bounds.size ?? initialContentSize
      window.setContentSize(
        SettingsWindowSizingPolicy.fittingContentSize(
          current: restoredContentSize,
          minimum: initialMinimumSize
        )
      )
      window.center()
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      navigationObservation = navigation.$selectedPane.sink { [weak self] pane in
        guard let self, let window = self.window else { return }
        window.title = pane.title
        self.updateWindowSizing(for: pane)
        // Combine publishes this property in its willSet phase. Use the emitted pane rather than
        // reading navigation.selectedPane, which still contains the previous value here.
        self.updateToolbarSelection(for: pane)
      }
      developerToolsObservation = preferences.$developerToolsEnabled.dropFirst().sink {
        [weak self] enabled in
        guard let self else { return }
        self.navigation.setDeveloperToolsEnabled(enabled)
        if let window = self.window { self.configureToolbar(for: window) }
        self.updateToolbarSelection()
      }
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func show(pane: SettingsPane?) {
      if let pane { navigation.requestPane(pane) }
      updateWindowSizing(for: navigation.selectedPane)
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

    private func updateWindowSizing(for pane: SettingsPane) {
      guard let window else { return }
      let minimum = SettingsWindowSizingPolicy.minimumContentSize(for: pane)
      window.contentMinSize = minimum
      let current = window.contentView?.bounds.size ?? minimum
      let fitted = SettingsWindowSizingPolicy.fittingContentSize(current: current, minimum: minimum)
      guard fitted != current else { return }
      window.setContentSize(fitted)
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
      let panes = visiblePanes
      guard
        let group = window?.toolbar?.items.first(where: {
          $0.itemIdentifier == Self.paneGroupIdentifier
        }) as? NSToolbarItemGroup, let index = panes.firstIndex(of: pane ?? navigation.selectedPane)
      else { return }
      group.selectedIndex = index
    }

    @objc private func selectPaneFromToolbar(_ sender: NSToolbarItemGroup) {
      let panes = visiblePanes
      guard panes.indices.contains(sender.selectedIndex) else {
        updateToolbarSelection()
        return
      }
      navigation.requestPane(panes[sender.selectedIndex])
      // A dirty profile editor may reject the request pending confirmation. Restore the current
      // selection immediately; accepted requests are applied again by the navigation observer.
      updateToolbarSelection()
    }

    private var visiblePanes: [SettingsPane] {
      SettingsPane.primaryCases(developerToolsEnabled: preferences.developerToolsEnabled)
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
      let panes = visiblePanes
      let group = NSToolbarItemGroup(
        itemIdentifier: Self.paneGroupIdentifier,
        images: panes.map(\.toolbarImage),
        selectionMode: .selectOne,
        labels: panes.map(\.title),
        target: self,
        action: #selector(Self.selectPaneFromToolbar(_:))
      )
      group.controlRepresentation = .expanded
      // Each segment already has an accessible pane label. Avoid repeating a visible group label
      // below the toolbar controls.
      group.label = ""
      group.paletteLabel = OJDLocalized.string(
        "settings.navigation",
        fallback: "Settings navigation"
      )
      group.toolTip = OJDLocalized.string("settings.choosePane", fallback: "Choose a settings pane")
      group.visibilityPriority = .high
      group.selectedIndex = panes.firstIndex(of: navigation.selectedPane) ?? 0
      return group
    }
  }

#endif
