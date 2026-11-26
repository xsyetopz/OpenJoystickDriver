#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import OpenJoystickDriverKit
  import SwiftUI

  /// The main window: a sidebar, a content list column and a detail column, with a toolbar.
  ///
  /// Closing the window hides it, which keeps the selected area, the screens' state and the window
  /// geometry.
  @MainActor
  final class MainWindowController: NSWindowController, NSWindowDelegate, MainWindowPresenting,
    MenuProfileMutating
  {
    /// Decides which area is selected and guards switches away from a profile editor with edits.
    let navigation: MainWindowNavigationModel
    /// The models of every area's screen.
    let screens: MainWindowScreens
    /// Reports to the app whether the window is visible.
    private let visibilityChanged: @MainActor (Bool) -> Void
    /// Whether any part of the window is on screen, which gates the views' live readings.
    let visibility = WindowVisibility()
    /// The split view that holds the sidebar, the list column and the detail column.
    let splitViewController = NSSplitViewController()
    /// The content list column, collapsed for an area without a list.
    private let listItem: NSSplitViewItem
    /// The sidebar column, collapsed by the sidebar toggle.
    private let sidebarItem: NSSplitViewItem
    /// Re-applies the window minimum when the sidebar collapses or returns.
    private var sidebarObservation: AnyCancellable?
    /// Fits the list column to the title after each column resize.
    private var splitResizeObservation: AnyCancellable?
    /// Keeps the window title and the toolbar in step with the selected area.
    private var areaObservation: AnyCancellable?
    /// Re-validates the toolbar items when any state that enables them changes.
    private var toolbarEnablementObservation: AnyCancellable?
    /// Updates the toolbar actions and log following when Activity switches its view.
    private var activityModeObservation: AnyCancellable?
    /// Keeps the window subtitle in step with the service status.
    private var summaryObservation: AnyCancellable?
    /// Shows the toolbar items that the interface level and the developer switch allow.
    private var interfaceLevelObservation: AnyCancellable?
    /// The Settings preferences, which hold the interface level and the developer switch.
    private let preferences: SettingsPreferencesModel
    /// Whether a resize is being corrected, so that the correction does not repeat.
    private var isEnforcingMinimumSize = false

    /// Creates the main window with its screens, split view and toolbar.
    ///
    /// The window restores its saved frame, or centers when there is none.
    /// - Parameters:
    ///   - runtime: The runtime state that every area reads.
    ///   - supportReport: The support report and log export model.
    ///   - preferences: The Settings preferences, which hold the interface level.
    ///   - restartApplication: Restarts the app, for the Access area.
    ///   - openInputTest: Opens the Input Test window for a controller.
    ///   - visibilityChanged: Called with true when the window is shown and false when it is
    ///     hidden.
    ///   - persistence: Where the selected area is saved between launches.
    init(
      runtime: RuntimeViewModel,
      supportReport: SupportReportModel,
      preferences: SettingsPreferencesModel,
      restartApplication: @escaping @MainActor () -> Void,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void,
      visibilityChanged: @escaping @MainActor (Bool) -> Void,
      persistence: any MainWindowAreaPersistence = UserDefaultsMainWindowAreaPersistence()
    ) {
      self.visibilityChanged = visibilityChanged
      self.preferences = preferences
      let navigationModel = MainWindowNavigationModel(persistence: persistence)
      self.navigation = navigationModel
      let windowScreens = Self.makeScreens(
        runtime: runtime,
        supportReport: supportReport,
        navigation: navigationModel,
        restartApplication: restartApplication,
        openInputTest: openInputTest
      )
      self.screens = windowScreens

      let sidebar = Self.makeSidebarItem(navigation: navigationModel)
      self.sidebarItem = sidebar
      let list = Self.makeListItem(
        navigation: navigationModel,
        runtime: runtime,
        screens: windowScreens,
        preferences: preferences,
        visibility: visibility
      )
      self.listItem = list
      let detailItem = Self.makeDetailItem(
        navigation: navigationModel,
        runtime: runtime,
        screens: windowScreens,
        preferences: preferences,
        visibility: visibility
      )
      splitViewController.addSplitViewItem(sidebar)
      splitViewController.addSplitViewItem(list)
      splitViewController.addSplitViewItem(detailItem)

      let window = Self.makeWindow(content: splitViewController)
      super.init(window: window)
      window.delegate = self
      configureToolbar(for: window)
      installSizingPolicy(on: window)
      observeLayout(sidebar: sidebar, window: window)
      observeState(runtime: runtime, window: window)
    }

    /// Keeps the window minimum and the list column width in step with the split view.
    private func observeLayout(sidebar: NSSplitViewItem, window: NSWindow) {
      sidebarObservation = sidebar.publisher(for: \.isCollapsed).dropFirst().sink {
        [weak self, weak window] _ in
        guard let self, let window else { return }
        applyMinimumSize(to: window)
      }
      splitResizeObservation = NotificationCenter.default.publisher(
        for: NSSplitView.didResizeSubviewsNotification,
        object: splitViewController.splitView
      ).receive(on: RunLoop.main).sink { [weak self] _ in self?.fitListToTitle() }
    }

    /// Keeps the window title, subtitle and toolbar in step with the selected area and the state
    /// that enables the toolbar items.
    private func observeState(runtime: RuntimeViewModel, window: NSWindow) {
      let navigationModel = navigation
      areaObservation = navigationModel.$selectedArea.sink { [weak self] area in
        self?.reflect(area: area)
      }
      toolbarEnablementObservation = Publishers.MergeMany(
        runtime.scopedRefreshInFlightPublisher.map { _ in () }.eraseToAnyPublisher(),
        runtime.$remappingState.map { _ in () }.eraseToAnyPublisher(),
        screens.library.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.libraryArea.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.profiles.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.access.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.activity.log.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        screens.activity.diagnostics.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        navigationModel.objectWillChange.map { _ in () }.eraseToAnyPublisher()
      ).receive(on: DispatchQueue.main).sink { [weak self] in
        self?.window?.toolbar?.validateVisibleItems()
      }
      activityModeObservation = screens.activity.$mode.receive(on: DispatchQueue.main).sink {
        [weak self] _ in
        guard let self else { return }
        showToolbarActions(of: navigationModel.selectedArea)
        updateLogFollowing(area: navigationModel.selectedArea)
      }
      interfaceLevelObservation = preferences.objectWillChange.receive(on: DispatchQueue.main)
        .sink { [weak self] in
          guard let self else { return }
          showToolbarActions(of: navigationModel.selectedArea)
        }
      summaryObservation = runtime.$statusState.sink { [weak self, weak window] status in
        window?.subtitle = MainWindowSummary.text(for: navigationModel.selectedArea, status: status)
        self?.fitListToTitle()
      }
    }

    /// Unavailable, because the window controller is created in code only.
    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: MainWindowPresenting

    /// Shows the main window, on `area` when it is not nil.
    func showMainWindow(area: MainWindowArea?) {
      if let area { navigation.requestArea(area) }
      present()
      screens.whatsNew.presentIfNeeded()
    }

    /// Shows Access and has its permission rows scroll to the permission.
    func showAccess(permission: AccessPermissionRow.Kind) {
      screens.access.focusedPermission = permission
      showMainWindow(area: .access)
    }

    /// Shows Controllers with the controller selected.
    func showController(id: String) {
      guard navigation.requestArea(.controllers) else {
        present()
        return
      }
      screens.controllers.select(sessionToken: id)
      present()
    }

    /// Shows the main window with the Explain Error Code sheet open.
    func showErrorCodeExplainer() {
      guard
        ActivityRow.explainErrorCode.rowLevel.isShown(
          at: preferences.interfaceLevel,
          developerToolsEnabled: preferences.developerToolsEnabled
        )
      else { return }
      present()
      screens.errorCodeExplainer.isPresented = true
    }

    /// The session token of the selected controller, or nil when none is selected.
    var selectedControllerID: String? {
      screens.controllers.selectedDevice?.sessionToken.rawValue
    }

    /// The area the window shows.
    var selectedArea: MainWindowArea { navigation.selectedArea }

    /// Shows the Input Test window for the controller, after selecting it in Controllers.
    ///
    /// Returns false when the controller is not in Controllers. A refused area switch shows its own
    /// alert, so it counts as shown.
    func showInputTest(controllerID: String) -> Bool {
      guard navigation.requestArea(.controllers) else {
        present()
        return true
      }
      showController(id: controllerID)
      guard
        let device = screens.controllers.devices.first(where: {
          $0.sessionToken.rawValue == controllerID
        })
      else { return false }
      screens.openInputTest(device)
      return true
    }

    // MARK: Profile mutations from menus

    /// Runs a profile mutation of the status or main menu on the shared library under the
    /// Profiles editor's mutation tracking.
    ///
    /// Returns nil, without running `mutation`, when the editor holds a mutation.
    func performMenuProfileMutation(
      _ request: RuntimeMutationRequest,
      _ mutation: @MainActor (ProfileLibraryModel) async -> RuntimeMutationResult
    ) async -> MenuProfileMutationOutcome? {
      let library = screens.library
      return await navigation.trackMenuProfileMutation(request) {
        let result = await mutation(library)
        return MenuProfileMutationOutcome(result: result, lastError: library.lastError)
      }
    }

    /// Shows Profiles and asks for a profile file to import.
    func importProfile() {
      present()
      navigation.perform(in: .profiles) { [weak self] in
        self?.screens.profiles.chooseProfileToImport()
      }
    }

    /// Shows Profiles and asks where to save the selected profile.
    func exportProfile() {
      present()
      navigation.perform(in: .profiles) { [weak self] in
        guard let self, let profile = selectedProfile else { return }
        screens.profiles.exportProfile(profile)
      }
    }

    /// Whether a saved profile is selected in the Profiles screen.
    var hasSelectedProfile: Bool { selectedProfile != nil }

    /// The selected profile, or nil while the runtime is unavailable, a damaged entry is selected
    /// or nothing is selected.
    var selectedProfile: RemappingProfile? {
      guard case .available(let snapshot) = screens.runtime.remappingState,
        screens.profiles.selectedRecoveryIssueID == nil,
        let selectedID = screens.profiles.selectedProfileID
      else { return nil }
      return snapshot.profiles.first { $0.id == selectedID }
    }

    /// Shows Library and asks for a record file or mod folder to install.
    func installRecordOrMod() {
      present()
      navigation.perform(in: .library) { [weak self] in
        guard let url = LibraryFilePicker.chooseRecordOrModFolder() else { return }
        self?.screens.libraryArea.beginInstall(from: url)
      }
    }

    // MARK: Window

    /// Sizes the window, shows it in front and activates the app.
    private func present() {
      guard let window else { return }
      applyMinimumSize(to: window)
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
      visibilityChanged(true)
      AppForeground.show(window)
      visibility.update(window.occlusionState.contains(.visible))
      updateLogFollowing(area: navigation.selectedArea)
    }

    /// Hides the window instead of closing it and returns false.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
      sender.orderOut(nil)
      updateLogFollowing(area: navigation.selectedArea)
      visibilityChanged(false)
      visibility.update(false)
      return false
    }

    /// Keeps the window from being resized below its minimum frame size.
    func windowWillResize(_ sender: NSWindow, toFrameSize frameSize: NSSize) -> NSSize {
      WindowFramePolicy.fittingSize(frameSize, minimumSize: minimumFrameSize(for: sender))
    }

    /// The smallest frame of `window` that fits the sidebar and list column while they show.
    private func minimumFrameSize(for window: NSWindow) -> NSSize {
      MainWindowSizingPolicy.minimumFrameSize(
        for: window,
        showsSidebar: !sidebarItem.isCollapsed,
        showsList: !listItem.isCollapsed,
        listMinimum: listItem.minimumThickness
      )
    }

    /// Sets the window's minimum sizes from the columns that show, and grows the window when it is
    /// smaller than that.
    private func applyMinimumSize(to window: NSWindow) {
      window.contentMinSize = MainWindowSizingPolicy.minimumContentSize(
        showsSidebar: !sidebarItem.isCollapsed,
        showsList: !listItem.isCollapsed,
        listMinimum: listItem.minimumThickness
      )
      window.minSize = minimumFrameSize(for: window)
      let fittedFrame = WindowFramePolicy.fittingFrame(window.frame, minimumSize: window.minSize)
      guard fittedFrame.size != window.frame.size else { return }
      isEnforcingMinimumSize = true
      window.setFrame(fittedFrame, display: true)
      isEnforcingMinimumSize = false
    }

    /// Pauses the views' live readings while no part of the window is on screen.
    func windowDidChangeOcclusionState(_: Notification) {
      guard let window else { return }
      visibility.update(window.isVisible && window.occlusionState.contains(.visible))
    }

    /// Stops following the logs while the window is miniaturized.
    func windowDidMiniaturize(_: Notification) {
      updateLogFollowing(area: navigation.selectedArea)
    }

    /// Resumes following the logs when the window returns from the Dock.
    func windowDidDeminiaturize(_: Notification) {
      updateLogFollowing(area: navigation.selectedArea)
    }

    /// Grows the window back to its minimum frame size after a resize that made it smaller.
    func windowDidResize(_ notification: Notification) {
      guard !isEnforcingMinimumSize, let window = notification.object as? NSWindow else { return }
      applyMinimumSize(to: window)
    }

    /// Moves the window inside the visible frame of its new screen.
    func windowDidChangeScreen(_: Notification) {
      guard let window else { return }
      WindowFramePolicy.clamp(window, minimumSize: minimumFrameSize(for: window))
    }

    /// Applies the minimum sizes, restores the saved frame and keeps the window on screen.
    private func installSizingPolicy(on window: NSWindow) {
      applyMinimumSize(to: window)
      window.setContentSize(MainWindowSizingPolicy.defaultContentSize)
      let autosaveName = "MainWindowGeometry"
      let restoredFrame = window.setFrameUsingName(autosaveName)
      window.setFrameAutosaveName(autosaveName)
      if !restoredFrame { window.center() }
      WindowFramePolicy.clamp(window, minimumSize: window.minSize)
    }

    /// Gives the window its unified toolbar, with no user customization.
    private func configureToolbar(for window: NSWindow) {
      // AppKit keeps toolbars that share an identifier showing the same items, and each window
      // shows its own area's actions, so each toolbar gets its own identifier.
      let toolbar = NSToolbar(
        identifier: "\(MainWindowToolbarLayout.toolbar).\(UUID().uuidString)"
      )
      toolbar.delegate = self
      toolbar.allowsUserCustomization = false
      toolbar.autosavesConfiguration = false
      toolbar.displayMode = .iconOnly
      window.toolbar = toolbar
      window.toolbarStyle = .unified
    }

    /// Collapses or shows the list column and updates the toolbar, log following, title and
    /// subtitle for `area`.
    private func reflect(area: MainWindowArea) {
      listItem.isCollapsed = !area.hasListColumn
      if let window { applyMinimumSize(to: window) }
      showToolbarActions(of: area)
      updateLogFollowing(area: area)
      window?.title = area.title
      window?.subtitle = MainWindowSummary.text(for: area, status: screens.runtime.statusState)
      fitListToTitle()
    }

    /// Widens the list column's minimum so the title and subtitle end inside it.
    ///
    /// The fit lays out the window, so it waits for the next turn of the run loop: a `@Published`
    /// sink runs before the value changes, and a layout there draws the hosted views with the old
    /// value.
    private func fitListToTitle() {
      RunLoop.main.perform { [weak self] in
        MainActor.assumeIsolated {
          guard let self, let window = self.window,
            MainWindowTitleFit.fit(self.listItem, in: window)
          else { return }
          self.applyMinimumSize(to: window)
        }
      }
    }
  }

  extension MainWindowController {
    /// Replaces the toolbar's area actions with those of `area`.
    func showToolbarActions(of area: MainWindowArea) {
      guard let toolbar = window?.toolbar else { return }
      let fixedCount = MainWindowToolbarLayout.fixedItems.count
      while toolbar.items.count > fixedCount { toolbar.removeItem(at: toolbar.items.count - 1) }
      let actions = shownToolbarActions(of: area)
      for (offset, action) in actions.enumerated() {
        toolbar.insertItem(withItemIdentifier: action.identifier, at: fixedCount + offset)
      }
    }

    /// The toolbar actions of `area` that the interface level and the developer switch show.
    func shownToolbarActions(of area: MainWindowArea) -> [MainWindowToolbarAction] {
      area.toolbarActions(
        activityMode: screens.activity.mode,
        level: preferences.interfaceLevel,
        developerToolsEnabled: preferences.developerToolsEnabled
      )
    }

    /// The menu-run actions of the selected area that the interface level and the developer switch
    /// show.
    var shownCommandActions: [MainWindowToolbarAction] {
      navigation.selectedArea.commandActions(
        activityMode: screens.activity.mode,
        level: preferences.interfaceLevel,
        developerToolsEnabled: preferences.developerToolsEnabled
      )
    }
  }

#endif
