#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // SF Symbol via NSImage(systemSymbolName:), else fallback text.
  struct OJDSystemSymbol: View {
    let name: String
    let fallback: String
    let fallbackSymbolName: String?

    init(name: String, fallback: String, fallbackSymbolName: String? = nil) {
      self.name = name
      self.fallback = fallback
      self.fallbackSymbolName = fallbackSymbolName
    }

    var body: some View {
      if #available(macOS 11.0, *) {
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
          Image(nsImage: image)
        } else if let fallbackSymbolName,
          let image = NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil)
        {
          Image(nsImage: image)
        } else {
          Text(fallback).font(.caption)
        }
      } else {
        Text(fallback).font(.caption)
      }
    }
  }

  extension View {
    @ViewBuilder func ojdAccessibilityLabel(_ label: String) -> some View {
      if #available(macOS 11.0, *) {
        accessibilityLabel(Text(label))
      } else {
        accessibility(label: Text(label))
      }
    }

    @ViewBuilder func ojdAccessibilityValue(_ value: String) -> some View {
      if #available(macOS 11.0, *) {
        accessibilityValue(Text(value))
      } else {
        accessibility(value: Text(value))
      }
    }

    @ViewBuilder func ojdAccessibilityHidden(_ hidden: Bool) -> some View {
      if #available(macOS 11.0, *) {
        accessibilityHidden(hidden)
      } else {
        accessibility(hidden: hidden)
      }
    }

    @ViewBuilder func ojdAccessibilitySelection(_ selected: Bool) -> some View {
      let value = OJDLocalized.string(
        selected ? "common.selected" : "common.notSelected",
        fallback: selected ? "Selected" : "Not selected"
      )
      if #available(macOS 11.0, *) {
        accessibilityValue(Text(value)).accessibilityAddTraits(selected ? .isSelected : [])
      } else {
        accessibility(value: Text(value)).accessibility(addTraits: selected ? .isSelected : [])
      }
    }
  }

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
      case .developer: return OJDLocalized.string("developer.title", fallback: "Developer")
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

    /// Toolbar images use SF Symbols when available; otherwise a blank template slot.
    var toolbarImage: NSImage {
      if #available(macOS 11.0, *),
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
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

  @MainActor final class SettingsNavigationModel: ObservableObject {
    @Published private(set) var selectedPane: SettingsPane
    @Published private(set) var pendingPane: SettingsPane?
    @Published private(set) var discardGeneration = 0
    @Published var isDiscardConfirmationPresented = false

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

    @discardableResult func beginProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      guard activeProfilesEditorMutation == nil else { return false }
      activeProfilesEditorMutation = request
      activeProfilesEditorMutationIsRuntimeBound = false
      cancelPendingPane()
      return true
    }

    func ownsProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool {
      activeProfilesEditorMutation == request
    }

    @discardableResult func finishProfilesEditorMutation(_ request: RuntimeMutationRequest) -> Bool
    {
      guard activeProfilesEditorMutation == request else { return false }
      activeProfilesEditorMutation = nil
      activeProfilesEditorMutationIsRuntimeBound = false
      return true
    }

    @discardableResult func reconcileProfilesEditorMutation(_ request: RuntimeMutationRequest)
      -> Bool
    {
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
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject var viewModel: RuntimeViewModel
    let notificationPermission: NotificationPermissionModel
    let preferences: SettingsPreferencesModel
    let console: ConsoleViewModel
    let developerTools: DeveloperToolsViewModel
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void

    var body: some View {
      detail.id(navigation.selectedPane).frame(
        maxWidth: .infinity,
        minHeight: 0,
        maxHeight: .infinity
      ).background(Color(NSColor.windowBackgroundColor)).frame(
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

    @ViewBuilder private var detail: some View {
      switch navigation.selectedPane {
      case .overview:
        OverviewView(
          viewModel: viewModel,
          navigation: navigation,
          notificationPermission: notificationPermission
        )
      case .controllers: ControllersView(viewModel: viewModel, openInputTest: openInputTest)
      case .profiles: ProfilesView(viewModel: viewModel, navigation: navigation)
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

    @MainActor private static func openPrivacySettings(for permissions: RuntimePermissionSummary) {
      let pane: String
      if permissions.inputMonitoring != .granted {
        pane = "Privacy_ListenEvent"
      } else {
        pane = "Privacy_Accessibility"
      }
      openPrivacySettings(pane: pane)
    }

    @MainActor private static func openPrivacySettings(pane: String) {
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

  // MARK: - Overview and status

  struct OverviewView: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @ObservedObject var navigation: SettingsNavigationModel
    @ObservedObject private var notificationPermission: NotificationPermissionModel

    init(
      viewModel: RuntimeViewModel,
      navigation: SettingsNavigationModel,
      notificationPermission: NotificationPermissionModel = NotificationPermissionModel()
    ) {
      self.viewModel = viewModel
      self.navigation = navigation
      self.notificationPermission = notificationPermission
    }

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          PageHeader(title: OJDLocalized.string("settings.overview", fallback: "Overview"))
          SystemExtensionSetupCard(viewModel: viewModel, navigation: navigation)
          accessSummary
          statusCard
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
      }.onAppear { notificationPermission.refresh() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in notificationPermission.refresh() }
    }

    private var accessSummary: some View {
      GroupBox {
        HStack(alignment: .top, spacing: 12) {
          AccessRequirementCard(
            title: OJDLocalized.string("common.inputMonitoring", fallback: "Input Monitoring"),
            value: inputMonitoringStatus.value,
            symbol: "keyboard",
            tone: inputMonitoringStatus.tone,
            action: inputMonitoringStatus.isActionable
              ? {
                PermissionAccessActions.requestControllerAccess(
                  viewModel: viewModel,
                  requirement: .inputMonitoring
                )
              } : nil
          )
          AccessRequirementCard(
            title: OJDLocalized.string("common.accessibility", fallback: "Accessibility"),
            value: accessibilityStatus.value,
            symbol: "lock.shield",
            tone: accessibilityStatus.tone,
            action: accessibilityStatus.isActionable
              ? {
                PermissionAccessActions.requestControllerAccess(
                  viewModel: viewModel,
                  requirement: .accessibility
                )
              } : nil
          )
          AccessRequirementCard(
            title: OJDLocalized.string("common.keyboardPointer", fallback: "Keyboard & pointer"),
            value: postEventStatus.value,
            symbol: "cursorarrow",
            tone: postEventStatus.tone,
            action: postEventStatus.isActionable
              ? { PermissionAccessActions.requestPostEventAccess(viewModel: viewModel) } : nil
          )
          AccessRequirementCard(
            title: OJDLocalized.string("settings.notifications", fallback: "Notifications"),
            value: notificationStatus.value,
            symbol: "bell",
            tone: notificationStatus.tone,
            action: notificationStatus.isActionable
              ? { notificationPermission.requestOrOpenSettings() } : nil
          )
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("settings.accessReadiness", fallback: "Access & readiness")).font(
          .headline
        )
      }.ojdAccessibilityLabel(
        OJDLocalized.string(
          "settings.accessReadinessAccessibility",
          fallback: "Access and readiness"
        )
      ).ojdAccessibilityValue(accessSummaryValue)
    }

    private var accessSummaryValue: String {
      [
        inputMonitoringStatus.value, accessibilityStatus.value, postEventStatus.value,
        notificationStatus.value
      ].joined(separator: ", ")
    }

    private var inputMonitoringStatus: OverviewAccessStatus {
      permissionStatus(for: permissionSummary?.inputMonitoring)
    }

    private var accessibilityStatus: OverviewAccessStatus {
      permissionStatus(for: permissionSummary?.accessibility)
    }

    private var postEventStatus: OverviewAccessStatus {
      guard case .available(let status) = viewModel.statusState else {
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking", fallback: "Checking..."),
          tone: .neutral,
          isActionable: true
        )
      }
      guard let requiresPostEventAccess = status.requiresPostEventAccess else {
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking", fallback: "Checking..."),
          tone: .neutral,
          isActionable: true
        )
      }
      guard requiresPostEventAccess else {
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.notNeeded", fallback: "Not needed"),
          tone: .neutral,
          isActionable: false
        )
      }
      switch status.postEventAccess {
      case .granted:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.allowed", fallback: "Allowed"),
          tone: .positive,
          isActionable: false
        )
      case .notAuthorized:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.needsAttention", fallback: "Needs attention"),
          tone: .caution,
          isActionable: true
        )
      case nil:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking", fallback: "Checking..."),
          tone: .neutral,
          isActionable: true
        )
      }
    }

    private var notificationStatus: OverviewAccessStatus {
      switch notificationPermission.state {
      case .checking:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking", fallback: "Checking..."),
          tone: .neutral,
          isActionable: false
        )
      case .allowed:
        if notificationPermission.settings.alertStyle == .none {
          return OverviewAccessStatus(
            value: OJDLocalized.string("settings.notificationBannersOff", fallback: "Banners off"),
            tone: .caution,
            isActionable: true
          )
        }
        if notificationPermission.settings.soundsEnabled == false {
          return OverviewAccessStatus(
            value: OJDLocalized.string("settings.notificationSoundOff", fallback: "Sound off"),
            tone: .caution,
            isActionable: true
          )
        }
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.allowed", fallback: "Allowed"),
          tone: .positive,
          isActionable: false
        )
      case .notDetermined:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.notRequested", fallback: "Not requested"),
          tone: .caution,
          isActionable: true
        )
      case .denied:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.needsAttention", fallback: "Needs attention"),
          tone: .caution,
          isActionable: true
        )
      }
    }

    private var permissionSummary: RuntimePermissionSummary? {
      if case .available(let permissions) = viewModel.permissionState { return permissions }
      if case .available(let status) = viewModel.statusState { return status.permissions }
      return nil
    }

    private func permissionStatus(for state: RuntimePermissionState?) -> OverviewAccessStatus {
      switch state {
      case .granted:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.allowed", fallback: "Allowed"),
          tone: .positive,
          isActionable: false
        )
      case .denied, .unknown:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.needsAttention", fallback: "Needs attention"),
          tone: .caution,
          isActionable: true
        )
      case nil:
        switch viewModel.permissionState {
        case .loading, .requesting:
          return OverviewAccessStatus(
            value: OJDLocalized.string("status.checking", fallback: "Checking..."),
            tone: .neutral,
            isActionable: true
          )
        case .available, .unavailable, .error:
          return OverviewAccessStatus(
            value: OJDLocalized.string("common.needsAttention", fallback: "Needs attention"),
            tone: .caution,
            isActionable: true
          )
        }
      case .unavailable:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.unavailable", fallback: "Unavailable"),
          tone: .caution,
          isActionable: true
        )
      }
    }

    private var statusCard: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            StatusBadge(status: statusTitle, symbol: statusSymbol)
            Spacer()
            Button(OJDLocalized.string("common.refresh", fallback: "Refresh")) {
              Task { @MainActor in await viewModel.refresh() }
            }
          }
          Text(statusDetail).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }.padding(4)
      }.ojdAccessibilityLabel(
        OJDLocalized.string("settings.controllerStatus", fallback: "Controller status")
      ).ojdAccessibilityValue(statusDetail)
    }

    private var statusTitle: String {
      switch viewModel.statusState {
      case .loading: return OJDLocalized.string("status.starting", fallback: "Starting...")
      case .available(let status): return status.readinessLabel
      case .unavailable, .error:
        return OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
      }
    }

    private var statusSymbol: String {
      switch viewModel.statusState {
      case .available(let status):
        return status.readiness == .ready ? "checkmark.circle" : "exclamationmark.circle"
      case .loading: return "clock"
      case .unavailable, .error: return "exclamationmark.triangle"
      }
    }

    private var statusDetail: String {
      switch viewModel.statusState {
      case .loading:
        return OJDLocalized.string(
          "status.checkingControllerAccess",
          fallback: "Checking controller access..."
        )
      case .unavailable(let message), .error(let message): return message
      case .available(let status): return status.deviceCountLabel
      }
    }
  }

  private struct OverviewAccessStatus {
    let value: String
    let tone: OverviewAccessTone
    let isActionable: Bool
  }

  private enum OverviewAccessTone {
    case positive
    case caution
    case neutral

    var color: Color {
      switch self {
      case .positive: return Color(NSColor.systemGreen)
      case .caution: return Color(NSColor.systemOrange)
      case .neutral: return Color(NSColor.secondaryLabelColor)
      }
    }
  }

  private struct AccessRequirementCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: OverviewAccessTone
    let action: (() -> Void)?

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        OJDSystemSymbol(name: symbol, fallback: title).foregroundColor(tone.color).frame(
          width: 20,
          height: 20
        ).ojdAccessibilityHidden(true)
        Text(title).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        Text(value).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        if let action {
          Button(OJDLocalized.string("common.request", fallback: "Request..."), action: action)
            .frame(minHeight: 28).ojdAccessibilityLabel(
              OJDLocalized.formatted("settings.requestAccess", fallback: "Request %@ access", title)
            ).ojdAccessibilityValue(value)
        }
        Spacer(minLength: 0)
      }.padding(8).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading).background(
        Color(NSColor.controlBackgroundColor)
      ).cornerRadius(8).contentShape(Rectangle()).ojdAccessibilityLabel(title)
        .ojdAccessibilityValue(value)
    }
  }

  struct StatusBadge: View {
    let status: String
    let symbol: String

    var body: some View {
      HStack(spacing: 7) {
        OJDSystemSymbol(
          name: symbol,
          fallback: OJDLocalized.string("common.status", fallback: "Status")
        ).ojdAccessibilityHidden(true)
        Text(status).font(.headline.weight(.semibold))
      }.foregroundColor(Color(NSColor.labelColor)).ojdAccessibilityLabel(
        OJDLocalized.string("common.status", fallback: "Status")
      ).ojdAccessibilityValue(status)
    }
  }

#endif
