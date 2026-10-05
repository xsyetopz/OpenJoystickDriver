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
        "controllers.disconnectWirelessConfirmTitle"
      )
      alert.informativeText = OJDLocalized.formatted(
        "controllers.disconnectWirelessConfirmMessage",
        device.name
      )
      alert.addButton(
        withTitle: OJDLocalized.string(
          "controllers.disconnectWirelessConfirm"
        )
      )
      alert.addButton(withTitle: OJDLocalized.string("common.cancel"))
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      Task { @MainActor in await viewModel.disconnectWirelessController(device) }
    }

    func makeHelpMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("menu.help"))
      addNavigationItem(
        title: OJDLocalized.string("menu.console"),
        pane: .console,
        symbol: "terminal",
        to: menu
      )
      let project = NSMenuItem(
        title: OJDLocalized.string("menu.projectPage"),
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
