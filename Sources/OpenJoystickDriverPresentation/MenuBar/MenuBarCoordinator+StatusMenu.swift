#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  extension MenuBarCoordinator {
    @objc
    func disconnectWirelessControllerFromStatus(_ sender: Any?) {
      guard let identifier = (sender as? NSMenuItem)?.representedObject as? String,
        let device = menuBarViewModel.devices.first(where: { $0.runtimeIdentifier == identifier })
      else { return }
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string(
        "controllers.disconnectWirelessConfirmTitle",
        fallback: "Disconnect Wireless Controller?"
      )
      alert.informativeText = OJDLocalized.formatted(
        "controllers.disconnectWirelessConfirmMessage",
        fallback: "%@ will stay disconnected until you connect it again manually.",
        device.name
      )
      alert.addButton(
        withTitle: OJDLocalized.string(
          "controllers.disconnectWirelessConfirm",
          fallback: "Disconnect"
        )
      )
      alert.addButton(withTitle: OJDLocalized.string("common.cancel", fallback: "Cancel"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      Task { @MainActor in await viewModel.disconnectWirelessController(device) }
    }

    func makeHelpMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("menu.help", fallback: "Help"))
      addNavigationItem(
        title: OJDLocalized.string("menu.console", fallback: "Open Console..."),
        pane: .console,
        symbol: "terminal",
        to: menu
      )
      let project = NSMenuItem(
        title: OJDLocalized.string("menu.projectPage", fallback: "GitHub"),
        action: #selector(openProjectPage(_:)),
        keyEquivalent: ""
      )
      project.target = self
      menu.addItem(project)
      return menu
    }

    func addNavigationItem(title: String, pane: SettingsPane, symbol: String, to menu: NSMenu) {
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

    @objc
    func requestAccessFromStatus(_ sender: Any?) {
      PermissionAccessActions.requestAccess(viewModel: viewModel)
    }

    func menuImage(symbol: String) -> NSImage? {
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      image?.isTemplate = true
      return image
    }

    func controllerMenuImage(for presentation: VirtualIdentityPresentation) -> NSImage? {
      if let image = menuImage(symbol: presentation.controllerSymbolName) { return image }
      return menuImage(symbol: presentation.controllerSymbolFallback)
    }

  }

#endif
