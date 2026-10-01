#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case overview
    case controllers
    case profiles
    case console
    case developer
    case settings

    var id: String { rawValue }

    var title: String {
      switch self {
      case .overview: return OJDLocalized.string("settings.overview", fallback: "Overview")
      case .controllers: return OJDLocalized.string("common.controllers", fallback: "Controllers")
      case .profiles: return OJDLocalized.string("common.profiles", fallback: "Profiles")
      case .console: return OJDLocalized.string("console.title", fallback: "Console")
      case .developer:
        return OJDLocalized.string("settings.developerTools", fallback: "Developer Tools")
      case .settings: return OJDLocalized.string("settings.title", fallback: "Settings")
      }
    }

    var symbolName: String {
      switch self {
      case .overview: return "rectangle.grid.2x2"
      case .controllers: return "gamecontroller"
      case .profiles: return "slider.horizontal.3"
      case .console: return "terminal"
      case .developer: return "wrench.and.screwdriver"
      case .settings: return "gearshape"
      }
    }

    static func primaryCases(developerToolsEnabled: Bool) -> [Self] {
      developerToolsEnabled ? Self.allCases : Self.allCases.filter { $0 != Self.developer }
    }

    /// Toolbar images use SF Symbols; a missing symbol yields a blank template slot.
    var toolbarImage: NSImage {
      if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
      {
        image.isTemplate = true
        return image
      }
      return NSImage(size: NSSize(width: 16, height: 16))
    }
  }

  protocol SettingsPanePersistence {
    func loadPane() -> SettingsPane?
    func savePane(_ pane: SettingsPane)
  }

  struct UserDefaultsSettingsPanePersistence: SettingsPanePersistence {
    static let key = "OpenJoystickDriver.settings.lastPane"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadPane() -> SettingsPane? {
      guard let rawValue = defaults.string(forKey: Self.key) else { return nil }
      return SettingsPane(rawValue: rawValue)
    }

    func savePane(_ pane: SettingsPane) { defaults.set(pane.rawValue, forKey: Self.key) }
  }

  @MainActor
  final class SettingsNavigationModel: ObservableObject {
    @Published
    private(set) var selectedPane: SettingsPane
    @Published
    private(set) var pendingPane: SettingsPane?
    @Published
    private(set) var discardGeneration = 0
    @Published
    var isDiscardConfirmationPresented = false

    private let persistence: any SettingsPanePersistence
    private var developerToolsEnabled: Bool
    private var profilesEditorIsDirty = false
    private var activeProfilesEditorMutation: RuntimeMutationRequest?
    private var activeProfilesEditorMutationIsRuntimeBound = false

    init(
      persistence: any SettingsPanePersistence = UserDefaultsSettingsPanePersistence(),
      developerToolsEnabled: Bool = false
    ) {
      self.persistence = persistence
      self.developerToolsEnabled = developerToolsEnabled
      let restored = persistence.loadPane() ?? .overview
      selectedPane = restored == .developer && !developerToolsEnabled ? .overview : restored
    }

    func requestPane(_ pane: SettingsPane) {
      guard pane != .developer || developerToolsEnabled else { return }
      guard pane != selectedPane else { return }
      guard activeProfilesEditorMutation == nil else { return }
      guard profilesEditorIsDirty else {
        selectAcceptedPane(pane)
        return
      }
      pendingPane = pane
      isDiscardConfirmationPresented = true
    }

    func setProfilesEditorDirty(_ dirty: Bool) { profilesEditorIsDirty = dirty }

    func setDeveloperToolsEnabled(_ enabled: Bool) {
      developerToolsEnabled = enabled
      guard !enabled, selectedPane == .developer else { return }
      selectAcceptedPane(.settings)
    }

    @discardableResult
    func beginProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == nil else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = false
      cancelPendingPane()
      return true
    }

    func ownsProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      activeProfilesEditorMutation == request
    }

    @discardableResult
    func finishProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == request else { return false }
      activeProfilesEditorMutation = nil
      activeProfilesEditorMutationIsRuntimeBound = false
      return true
    }

    @discardableResult
    func reconcileProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard
        activeProfilesEditorMutation == nil || activeProfilesEditorMutation == request
          || (activeProfilesEditorMutation?.operation == request.operation
            && !activeProfilesEditorMutationIsRuntimeBound)
      else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = true
      cancelPendingPane()
      return true
    }

    func discardPendingPane() {
      guard let pendingPane else {
        cancelPendingPane()
        return
      }
      profilesEditorIsDirty = false
      discardGeneration &+= 1
      self.pendingPane = nil
      isDiscardConfirmationPresented = false
      selectAcceptedPane(pendingPane)
    }

    func cancelPendingPane() {
      pendingPane = nil
      isDiscardConfirmationPresented = false
    }

    private func selectAcceptedPane(_ pane: SettingsPane) {
      selectedPane = pane
      persistence.savePane(pane)
    }
  }

  struct SettingsRootView: View {
    @ObservedObject
    var navigation: SettingsNavigationModel
    @ObservedObject
    var viewModel: RuntimeViewModel
    let supportReport: SupportReportModel
    let notificationPermission: NotificationPermissionModel
    @ObservedObject
    var preferences: SettingsPreferencesModel
    let console: ConsoleViewModel
    let developerTools: DeveloperToolsViewModel
    let controllers: ControllersViewModel
    let library: ProfileLibraryModel
    @ObservedObject
    var profiles: ProfilesViewModel
    let restartApplication: @MainActor () -> Void
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void

    var body: some View {
      NavigationView {
        SettingsSidebar(
          navigation: navigation,
          panes: SettingsPane.primaryCases(developerToolsEnabled: preferences.developerToolsEnabled)
        )
        detail.id(navigation.selectedPane).frame(
          maxWidth: .infinity,
          minHeight: 0,
          maxHeight: .infinity
        ).background(Color(NSColor.windowBackgroundColor))
      }.navigationViewStyle(DoubleColumnNavigationViewStyle()).frame(
        maxWidth: .infinity,
        maxHeight: .infinity
      ).onAppear { refreshIfNeeded() }.alert(
        isPresented: $navigation.isDiscardConfirmationPresented
      ) {
        Alert(
          title: Text(
            OJDLocalized.string("settings.discardTitle", fallback: "Discard unsaved changes?")
          ),
          message: Text(
            OJDLocalized.string(
              "settings.discardProfileMessage",
              fallback: "Your profile changes have not been saved."
            )
          ),
          primaryButton: .destructive(
            Text(OJDLocalized.string("settings.discardAction", fallback: "Discard Changes"))
          ) { navigation.discardPendingPane() },
          secondaryButton: .cancel { navigation.cancelPendingPane() }
        )
      }
    }

    @ViewBuilder
    private var detail: some View {
      switch navigation.selectedPane {
      case .overview:
        OverviewView(
          viewModel: viewModel,
          supportReport: supportReport,
          navigation: navigation,
          notificationPermission: notificationPermission,
          restartApplication: restartApplication
        )
      case .controllers: ControllersView(screen: controllers, openInputTest: openInputTest)
      case .profiles:
        ProfilesView(
          viewModel: viewModel,
          library: library,
          navigation: navigation,
          screen: profiles
        )
      case .console: ConsoleView(model: console)
      case .developer: DeveloperToolsView(model: developerTools)
      case .settings: ApplicationSettingsView(preferences: preferences)
      }
    }

    private func refreshIfNeeded() {
      guard case .loading = viewModel.loadState else { return }
      Task { @MainActor in await viewModel.refresh() }
    }
  }

  // Presents the native macOS privacy flow without making the settings window own a permission
  // page. The request is still performed by the existing runtime gateway; this type only supplies
  // the user-initiated presentation path used by the Overview and menu-bar status surfaces.
  enum PermissionAccessActions {
    static func requestControllerAccess(
      viewModel: RuntimeViewModel,
      requirement: PermissionManager.Requirement
    ) {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let permissions = await viewModel.requestPermission(requirement) else { return }
        let isGranted: Bool
        switch requirement {
        case .inputMonitoring: isGranted = permissions.inputMonitoring == .granted
        case .accessibility: isGranted = permissions.accessibility == .granted
        }
        if !isGranted {
          openPrivacySettings(
            pane: requirement == .inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"
          )
        }
      }
    }

    static func requestPostEventAccess(viewModel: RuntimeViewModel) {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let access = await viewModel.requestPostEventAccess() else { return }
        if access != .granted { openPrivacySettings(pane: "Privacy_Accessibility") }
      }
    }

    static func requestAccess(viewModel: RuntimeViewModel) {
      Task { @MainActor in
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard let permissions = await viewModel.requestPermissions() else { return }
        guard permissions.isReady else {
          openPrivacySettings(for: permissions)
          return
        }
        guard case .available(let status) = viewModel.statusState,
          status.requiresPostEventAccess == true, status.postEventAccess != .granted
        else { return }
        guard let access = await viewModel.requestPostEventAccess() else { return }
        if access != .granted { openPrivacySettings(pane: "Privacy_Accessibility") }
      }
    }

    @MainActor
    private static func openPrivacySettings(for permissions: RuntimePermissionSummary) {
      let pane: String
      if permissions.inputMonitoring != .granted {
        pane = "Privacy_ListenEvent"
      } else {
        pane = "Privacy_Accessibility"
      }
      openPrivacySettings(pane: pane)
    }

    @MainActor
    private static func openPrivacySettings(pane: String) {
      var urls: [URL] = []
      if #available(macOS 13.0, *) {
        if let url = URL(
          string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)"
        ) {
          urls.append(url)
        }
      }
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
        urls.append(url)
      }
      for url in urls where NSWorkspace.shared.open(url) { return }
      let fallbackPath: String
      if #available(macOS 13.0, *) {
        fallbackPath = "/System/Applications/System Settings.app"
      } else {
        fallbackPath = "/System/Library/PreferencePanes/Security.prefPane"
      }
      NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
    }
  }

#endif
