#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

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
    private var navigationObservation: AnyCancellable?

    init(
      viewModel: RuntimeViewModel,
      persistence: any SettingsPanePersistence = UserDefaultsSettingsPanePersistence()
    ) {
      navigation = SettingsNavigationModel(persistence: persistence)
      notificationPermission = NotificationPermissionModel()
      preferences = SettingsPreferencesModel()
      console = ConsoleViewModel()
      let rootView = SettingsRootView(
        navigation: navigation,
        viewModel: viewModel,
        notificationPermission: notificationPermission,
        preferences: preferences,
        console: console
      )
      let host = NSHostingView(rootView: rootView)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 460),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.minSize = NSSize(width: 640, height: 400)
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
      // Each segment already has an accessible pane label. Avoid repeating a visible group label
      // below the toolbar controls.
      group.label = ""
      group.paletteLabel = OJDLocalized.string(
        "settings.navigation",
        fallback: "Settings navigation"
      )
      group.toolTip = OJDLocalized.string("settings.choosePane", fallback: "Choose a settings pane")
      group.visibilityPriority = .high
      group.selectedIndex = SettingsPane.primaryCases.firstIndex(of: navigation.selectedPane) ?? 0
      return group
    }
  }

#endif
