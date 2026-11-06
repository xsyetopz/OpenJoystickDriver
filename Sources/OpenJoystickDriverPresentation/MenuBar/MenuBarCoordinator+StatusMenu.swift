#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  /// Carries a status-item action through `NSMenuItem.representedObject`.
  final class StatusItemActionBox: NSObject {
    /// The action that the menu item runs.
    let action: StatusItemAction

    /// Creates a box that carries `action`.
    init(_ action: StatusItemAction) { self.action = action }
  }

  /// Reports when the status menu opens and closes so it is refreshed on opening and never
  /// replaced while it is showing.
  @MainActor
  final class StatusMenuTracker: NSObject, NSMenuDelegate {
    /// Whether the menu is open now.
    private(set) var isOpen = false
    /// Called when the menu is about to open.
    var onWillOpen: () -> Void = {}
    /// Called when the menu has closed.
    var onDidClose: () -> Void = {}

    /// Marks the menu open and calls ``onWillOpen``.
    func menuWillOpen(_ menu: NSMenu) {
      isOpen = true
      onWillOpen()
    }

    /// Marks the menu closed and calls ``onDidClose``.
    func menuDidClose(_ menu: NSMenu) {
      isOpen = false
      onDidClose()
    }
  }

  extension MenuBarCoordinator {
    /// Builds the status menu from the model.
    func makeStatusMenu(from entries: [StatusItemEntry], title: String) -> NSMenu {
      let menu = NSMenu(title: title)
      menu.autoenablesItems = false
      for entry in entries { menu.addItem(makeMenuItem(for: entry)) }
      return menu
    }

    /// Returns the menu item for `entry`: a separator, or an item with its state, symbol, submenu
    /// or action.
    ///
    /// Settings gets `Command-,` and Quit gets `Command-Q`.
    private func makeMenuItem(for entry: StatusItemEntry) -> NSMenuItem {
      if entry.isSeparator { return .separator() }
      let title: String
      switch entry.title {
      case .key(let key):
        title = MainMenuRenderer.title(key, appName: OJDLocalized.string("term.app.name"))
      case .verbatim(let text): title = text
      }
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      MainMenuRenderer.identify(item, as: entry.id)
      item.isEnabled = entry.isEnabled
      item.state = entry.isChecked ? .on : .off
      if let symbolName = entry.symbolName { item.image = menuImage(symbol: symbolName) }
      if let submenu = entry.submenu {
        item.submenu = makeStatusMenu(from: submenu, title: title)
      } else if let action = entry.action {
        item.target = self
        item.action = #selector(performStatusItemAction(_:))
        item.representedObject = StatusItemActionBox(action)
        if action == .showSettings {
          item.keyEquivalent = ","
          item.keyEquivalentModifierMask = [.command]
        } else if action == .quit {
          item.keyEquivalent = "q"
          item.keyEquivalentModifierMask = [.command]
        }
      }
      return item
    }

    /// Runs the action of the chosen status menu item.
    @objc
    func performStatusItemAction(_ sender: Any?) {
      guard let box = (sender as? NSMenuItem)?.representedObject as? StatusItemActionBox else {
        return
      }
      switch box.action {
      case .suspendController(let token):
        runControllerAction(token) { device in await self.viewModel.suspendController(device) }
      case .resumeController(let token):
        runControllerAction(token) { device in await self.viewModel.resumeController(device) }
      case .testInput(let token): mainWindow?.showInputTest(controllerID: token)
      case .showController(let token): mainWindow?.showController(id: token)
      case .disconnectWireless(let token): disconnectWirelessController(sessionToken: token)
      case .activateProfile(let id):
        if let operation = confirmedActivation(of: id) { changeProfile(operation) }
      case .deactivateProfile(let id): changeProfile(.deactivate(profileID: id))
      case .showArea(let area): mainWindow?.showMainWindow(area: area)
      case .openWindow: mainWindow?.showMainWindow(area: nil)
      case .showSettings: settingsWindow?.showSettings(pane: nil)
      case .explainErrorCode: mainWindow?.showErrorCodeExplainer()
      case .openProjectWebsite: open(urlString: StatusItemModel.projectWebsite)
      case .openProblemReport: open(urlString: StatusItemModel.problemReport)
      case .quit: NSApplication.shared.terminate(sender)
      }
    }

    /// Opens the web address in the default browser, and does nothing when it is not a valid URL.
    func open(urlString: String) {
      guard let url = URL(string: urlString) else { return }
      NSWorkspace.shared.open(url)
    }

    /// Runs `action` on the connected controller with `sessionToken`, then shows its failure if the
    /// action recorded one.
    private func runControllerAction(
      _ sessionToken: String,
      _ action: @escaping @MainActor (ApplicationServiceDeviceDescription) async -> Void
    ) {
      guard
        let device = menuBarViewModel.devices.first(where: {
          $0.sessionToken.rawValue == sessionToken
        })
      else { return }
      Task { @MainActor in
        await action(device)
        if let failure = viewModel.controllerActionFailures[sessionToken] {
          presentFailure(failure)
        }
      }
    }

    /// Asks to confirm, then disconnects the wireless controller with `sessionToken`.
    private func disconnectWirelessController(sessionToken: String) {
      guard
        let device = menuBarViewModel.devices.first(where: {
          $0.sessionToken.rawValue == sessionToken
        })
      else { return }
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string("ui.controllers.disconnectWirelessConfirmTitle")
      alert.informativeText = OJDLocalized.formatted(
        "ui.controllers.disconnectWirelessConfirmMessage",
        device.name
      )
      alert.addButton(withTitle: OJDLocalized.string("ui.controllers.disconnectWirelessConfirm"))
        .hasDestructiveAction = true
      alert.addButton(withTitle: OJDLocalized.string("action.cancel"))
      guard alert.runActivatingApp() == .alertFirstButtonReturn else { return }
      runControllerAction(sessionToken) { device in
        await self.viewModel.disconnectWirelessController(device)
      }
    }

    /// The activation of a profile, after asking about a profile that produces no output; nil when
    /// the person declines.
    func confirmedActivation(of profileID: UUID) -> StatusItemProfileOperation? {
      let profiles: [RemappingProfile]
      if case .available(let snapshot) = viewModel.remappingState {
        profiles = snapshot.profiles
      } else {
        profiles = []
      }
      return StatusItemProfileOperation.activation(of: profileID, in: profiles) { _ in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = OJDLocalized.string("ui.profiles.emptyActivationTitle")
        alert.informativeText = OJDLocalized.string("ui.profiles.emptyActivationMessage")
        alert.addButton(withTitle: OJDLocalized.string("action.setActive"))
        alert.addButton(withTitle: OJDLocalized.string("action.cancel"))
        return alert.runActivatingApp() == .alertFirstButtonReturn
      }
    }

    /// Runs the profile operation through the main window, and shows an alert when it is refused or
    /// fails.
    private func changeProfile(_ operation: StatusItemProfileOperation) {
      Task { @MainActor in
        guard let mainWindow else { return }
        let outcome = await operation.perform(on: mainWindow)
        guard let outcome else {
          presentFailure(OJDLocalized.string("ui.extra.profileEditorBusy"))
          return
        }
        switch outcome.result {
        case .succeeded: return
        case .failed(_, _, let message), .rejected(_, _, let message): presentFailure(message)
        case .conflict:
          presentFailure(outcome.lastError ?? OJDLocalized.string("ui.extra.profileConflict"))
        }
      }
    }

    /// Shows an alert that names the failed action and gives `message`.
    private func presentFailure(_ message: String) {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = OJDLocalized.string("ui.extra.actionFailedTitle")
      alert.informativeText = message
      alert.addButton(withTitle: OJDLocalized.string("action.ok"))
      alert.runActivatingApp()
    }

    /// Returns the template SF Symbol `symbol` for a menu item, or nil when it does not exist.
    func menuImage(symbol: String) -> NSImage? {
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      image?.isTemplate = true
      return image
    }
  }

#endif
