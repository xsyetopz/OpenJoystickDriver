#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  extension MenuBarCoordinator: NSMenuDelegate, NSMenuItemValidation {
    /// Builds the main menu bar and registers its Services, Window and Help menus with the app.
    func makeApplicationMenu() -> NSMenu {
      let rendered = MainMenuRenderer.render(target: self)
      let application = NSApplication.shared
      application.servicesMenu = rendered.servicesMenu
      application.windowsMenu = rendered.windowMenu
      application.helpMenu = rendered.helpMenu
      return rendered.menu
    }

    /// The state that enables main menu items and picks their titles.
    func mainMenuState() -> MainMenuState {
      var state = MainMenuState()
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      if case .available(let available) = viewModel.remappingState {
        snapshot = available
      } else {
        snapshot = nil
      }
      state.controllers = menuBarViewModel.devices.map { device in
        MainMenuControllerState(
          id: device.sessionToken.rawValue,
          name: device.name,
          isSuspended: device.sessionState == .suspended,
          isWireless: device.supportsWirelessDisconnect,
          hasActiveProfile: snapshot?.activeProfiles.contains {
            $0.vendorID == device.vendorID && $0.productID == device.productID
          } == true
        )
      }
      state.selectedControllerID = mainWindow?.selectedControllerID
      state.hasMainWindow = mainWindow != nil
      state.hasSelectedProfile = mainWindow?.hasSelectedProfile == true
      state.enabledToolbarActions = mainWindow?.enabledToolbarActions ?? []
      state.disabledToolbarActions = mainWindow?.disabledToolbarActions ?? []
      state.hasSearchFieldInView = mainWindow?.searchFieldInView != nil
      state.hasSettingsWindow = settingsWindow != nil
      if let window = NSApplication.shared.keyWindow {
        state.isFullScreen = window.styleMask.contains(.fullScreen)
        state.isToolbarVisible = window.toolbar?.isVisible == true
        if let split = window.contentViewController as? NSSplitViewController,
          let sidebar = split.splitViewItems.first(where: { $0.behavior == .sidebar })
        {
          state.isSidebarVisible = !sidebar.isCollapsed
        }
      }
      return state
    }

    /// Updates the titles of the main menu items before `menu` opens, and lists the profiles in the
    /// Activate Profile submenu.
    package func menuNeedsUpdate(_ menu: NSMenu) {
      let state = mainMenuState()
      if menu.supermenu?.items.first(where: { $0.submenu === menu })?.identifier?.rawValue
        == MainMenuModel.item(for: .activateProfile)?.id
      {
        populateActivateProfileMenu(menu)
        return
      }
      let appName = OJDLocalized.string("term.app.name")
      for menuItem in menu.items {
        guard let id = menuItem.identifier?.rawValue,
          let item = MainMenuModel.allItems.first(where: { $0.id == id })
        else { continue }
        if item.action == .controllerTarget {
          menuItem.title = MainMenuRenderer.text(
            of: MainMenuModel.controllerTargetTitle(state: state)
          )
          continue
        }
        menuItem.title = MainMenuRenderer.title(
          MainMenuModel.titleKey(of: item, state: state),
          appName: appName
        )
      }
    }

    /// Returns whether the main menu item is enabled in the current state.
    package func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      guard let id = menuItem.identifier?.rawValue,
        let item = MainMenuModel.allItems.first(where: { $0.id == id })
      else { return true }
      return MainMenuModel.isEnabled(item, state: mainMenuState())
    }

    /// Runs the action of the chosen main menu item.
    @objc
    func performMainMenuItem(_ sender: NSMenuItem) {
      guard let id = sender.identifier?.rawValue,
        let item = MainMenuModel.allItems.first(where: { $0.id == id })
      else { return }
      performMainMenu(item.action)
    }

    /// Runs `action` of the main menu on the main window, the Settings window or the service.
    ///
    /// Responder-chain actions never arrive here.
    func performMainMenu(_ action: MainMenuAction) {
      let state = mainMenuState()
      switch action {
      case .about: showAbout(nil)
      case .settings: settingsWindow?.showSettings(pane: nil)
      case .quit: NSApplication.shared.terminate(nil)
      case .importProfile: mainWindow?.importProfile()
      case .exportProfile: mainWindow?.exportProfile()
      case .installRecordOrMod: mainWindow?.installRecordOrMod()
      case .activateProfile:
        // A submenu parent; its profile items run `activateProfileFromMenu`.
        preconditionFailure("\(action) opens a submenu")
      case .saveSupportReport: beginSaveSupportReport()
      case .saveActivityLog: beginSaveActivityLog()
      case .showArea(let area): mainWindow?.showMainWindow(area: area)
      case .find: mainWindow?.focusSearchField()
      case .toolbar(let toolbarAction): mainWindow?.perform(toolbarAction)
      case .controllerTarget:
        // Informational row; it carries no action.
        preconditionFailure("\(action) has no action")
      case .suspendOrResumeController:
        guard let controller = state.controller, let device = device(for: controller) else {
          return
        }
        Task { @MainActor in
          if controller.isSuspended {
            await viewModel.resumeController(device)
          } else {
            await viewModel.suspendController(device)
          }
        }
      case .testInput:
        guard let controller = state.controller else { return }
        mainWindow?.showInputTest(controllerID: controller.id)
      case .disconnectWirelessLink:
        guard let controller = state.controller, let device = device(for: controller) else {
          return
        }
        confirmDisconnectWireless(device)
      case .showControllerInWindow:
        if let controller = state.controller {
          mainWindow?.showController(id: controller.id)
        } else {
          mainWindow?.showMainWindow(area: .controllers)
        }
      case .deactivateProfile:
        guard let controller = state.controller, let device = device(for: controller) else {
          return
        }
        deactivateProfiles(of: device)
      case .showActivityLog: mainWindow?.showMainWindow(area: .activity)
      case .explainErrorCode: mainWindow?.showErrorCodeExplainer()
      case .copySupportReport: copySupportReportWithFeedback()
      case .reportProblem: open(urlString: StatusItemModel.problemReport)
      case .openProjectWebsite: openProjectPage(nil)
      case .services, .hide, .hideOthers, .showAll, .undo, .redo, .cut, .copy, .paste, .delete,
        .selectAll, .close, .toggleToolbar,
        .toggleSidebar, .toggleFullScreen, .minimize, .zoom, .bringAllToFront:
        // Sent down the responder chain by the menu item; the renderer never routes these here.
        preconditionFailure("\(action) is a responder-chain action")
      }
    }

    /// Fills the Activate Profile submenu with a row for each profile, or with one disabled row
    /// that says why there is none.
    ///
    /// The active profile shows a checkmark and cannot be chosen again.
    private func populateActivateProfileMenu(_ menu: NSMenu) {
      menu.removeAllItems()
      guard case .available(let snapshot) = viewModel.remappingState, !snapshot.profiles.isEmpty
      else {
        let profileListRead: Bool
        if case .available = viewModel.remappingState {
          profileListRead = true
        } else {
          profileListRead = false
        }
        let key = MainMenuModel.emptyActivateProfileTitleKey(profileListRead: profileListRead)
        let placeholder = NSMenuItem(
          title: OJDLocalized.string(key),
          action: nil,
          keyEquivalent: ""
        )
        placeholder.isEnabled = false
        menu.addItem(placeholder)
        return
      }
      let activeIDs = Set(snapshot.activeProfiles.map(\.profileID))
      for profile in snapshot.profiles {
        let item = NSMenuItem(title: profile.name, action: nil, keyEquivalent: "")
        item.representedObject = profile.id
        if activeIDs.contains(profile.id) {
          item.state = .on
          item.isEnabled = false
        } else {
          item.action = #selector(activateProfileFromMenu(_:))
          item.target = self
        }
        menu.addItem(item)
      }
    }

    /// Activates the chosen profile after asking about a profile that produces no output, and shows
    /// an alert when the activation fails.
    @objc
    func activateProfileFromMenu(_ sender: NSMenuItem) {
      guard let profileID = sender.representedObject as? UUID,
        let operation = confirmedActivation(of: profileID)
      else { return }
      Task { @MainActor in
        guard let mainWindow else { return }
        let outcome = await operation.perform(on: mainWindow)
        guard let outcome else {
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.profile.activateFailed"),
            message: OJDLocalized.string("ui.extra.profileEditorBusy"),
            style: .warning
          )
          return
        }
        switch outcome.result {
        case .succeeded: break
        case .conflict:
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.profile.activateFailed"),
            message: outcome.lastError ?? OJDLocalized.string("ui.menu.profile.activateConflict"),
            style: .warning
          )
        case .failed(_, _, let message), .rejected(_, _, let message):
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.profile.activateFailed"),
            message: message,
            style: .warning
          )
        }
      }
    }

    /// Returns the connected controller that `controller` stands for, or nil when it is gone.
    private func device(
      for controller: MainMenuControllerState
    ) -> ApplicationServiceDeviceDescription? {
      menuBarViewModel.devices.first { $0.sessionToken.rawValue == controller.id }
    }

    /// Shows an alert with a title, a message and an OK button.
    private func showMainMenuAlert(
      title: String,
      message: String,
      style: NSAlert.Style = .informational
    ) {
      let alert = NSAlert()
      alert.alertStyle = style
      alert.messageText = title
      alert.informativeText = message
      alert.addButton(withTitle: OJDLocalized.string("action.ok"))
      alert.runActivatingApp()
    }

    /// Asks to confirm, then disconnects the wireless link of `device`.
    private func confirmDisconnectWireless(_ device: ApplicationServiceDeviceDescription) {
      let confirmation = WirelessDisconnectConfirmation(controllerName: device.name)
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = confirmation.title
      alert.informativeText = confirmation.message
      alert.addButton(withTitle: confirmation.confirmTitle).hasDestructiveAction = true
      alert.addButton(withTitle: OJDLocalized.string("action.cancel"))
      guard alert.runActivatingApp() == .alertFirstButtonReturn else { return }
      Task { @MainActor in await viewModel.disconnectWirelessController(device) }
    }

    /// Deactivates the active profile of the controller model of `device`, and shows an alert when
    /// it is refused or fails.
    private func deactivateProfiles(of device: ApplicationServiceDeviceDescription) {
      let request = RuntimeMutationRequest(operation: .deactivate(profileID: nil))
      Task { @MainActor in
        guard let mainWindow else { return }
        let outcome = await mainWindow.performMenuProfileMutation(request) { library in
          await library.deactivateRemappingProfile(
            vendorID: device.vendorID,
            productID: device.productID,
            request: request
          )
        }
        guard let outcome else {
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.profile.deactivateFailed"),
            message: OJDLocalized.string("ui.extra.profileEditorBusy"),
            style: .warning
          )
          return
        }
        switch outcome.result {
        case .succeeded: break
        case .conflict:
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.profile.deactivateFailed"),
            message: OJDLocalized.string("ui.menu.profile.deactivateConflict"),
            style: .warning
          )
        case .failed(_, _, let message), .rejected(_, _, let message):
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.profile.deactivateFailed"),
            message: message,
            style: .warning
          )
        }
      }
    }

    /// Copies the support report and shows an alert that says whether it worked.
    private func copySupportReportWithFeedback() {
      Task { @MainActor in
        let copied = await supportReport.copySupportReport()
        if copied {
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.copySupportReport.done"),
            message: OJDLocalized.string("ui.menu.copySupportReport.doneDetail")
          )
        } else {
          showMainMenuAlert(
            title: OJDLocalized.string("ui.menu.copySupportReport.failed"),
            message: OJDLocalized.string("ui.menu.copySupportReport.failedDetail"),
            style: .warning
          )
        }
      }
    }

    /// Asks where to save the support report and writes it, then shows an alert when saving fails.
    private func beginSaveSupportReport() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.debug.saveReportPanel")
      panel.nameFieldStringValue = supportReport.defaultSupportReportFilename
      panel.canCreateDirectories = true
      panel.begin { [supportReport] response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in
          await supportReport.saveSupportReport(to: outputURL)
          if case .error(let message) = supportReport.supportReportState {
            self.showMainMenuAlert(
              title: OJDLocalized.string("ui.menu.file.saveFailed"),
              message: message,
              style: .warning
            )
          }
        }
      }
    }

    /// Asks where to save the logs and writes them, then shows an alert when saving fails.
    private func beginSaveActivityLog() {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.debug.saveLogsPanel")
      panel.nameFieldStringValue = supportReport.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      panel.begin { [supportReport] response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in
          await supportReport.saveSupportLogs(to: outputURL)
          if case .error(let message) = supportReport.supportLogsState {
            self.showMainMenuAlert(
              title: OJDLocalized.string("ui.menu.file.saveFailed"),
              message: message,
              style: .warning
            )
          }
        }
      }
    }

    /// Opens the project page in the default browser.
    @objc
    func openProjectPage(_ sender: Any?) {
      guard let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver") else { return }
      NSWorkspace.shared.open(url)
    }

    /// Shows the About panel with the app version and a link to the project page.
    @objc
    func showAbout(_ sender: Any?) {
      let repositoryTitle = OJDLocalized.string("ui.menu.projectPage")
      let credits = NSMutableAttributedString(string: repositoryTitle)
      if let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver") {
        credits.addAttribute(.link, value: url, range: NSRange(location: 0, length: credits.length))
      }
      var options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: OJDLocalized.string("term.app.name"),
        .applicationVersion: ApplicationVersion.display, .credits: credits,
      ]
      if let icon = NSImage(named: NSImage.applicationIconName) { options[.applicationIcon] = icon }
      NSApplication.shared.orderFrontStandardAboutPanel(options: options)
      AppForeground.activate()
    }
  }

#else

  /// A placeholder on a platform without AppKit and SwiftUI.
  final class MenuBarCoordinator {}

#endif
