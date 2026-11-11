#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension MainWindowArea {
    /// The localized title of the area, shown in its sidebar row and the window title.
    var title: String { OJDLocalized.string(titleKey) }
  }

  /// The main window's sidebar: one row per area, in `Command-1` to `Command-5` order.
  ///
  /// A row that ``MainWindowNavigationModel`` refuses leaves the selection on the area still shown.
  struct MainWindowSidebar: View {
    /// Decides which area is selected and whether a switch is allowed.
    @ObservedObject
    var navigation: MainWindowNavigationModel

    /// The sidebar list of the main window areas; the selection switches the area.
    var body: some View {
      List(selection: selection) {
        ForEach(MainWindowArea.allCases) { area in
          Label(area.title, systemImage: area.symbolName).tag(area)
        }
      }.listStyle(SidebarListStyle()).frame(
        minWidth: MainWindowSizingPolicy.sidebarWidth.minimum,
        maxWidth: MainWindowSizingPolicy.sidebarWidth.maximum
      )
      .ojdAccessibilityLabel(OJDLocalized.string("a11y.mainWindow.sidebar"))
    }

    /// The list selection, bound to the selected area; choosing a row asks the model to switch.
    private var selection: Binding<MainWindowArea?> {
      Binding(
        get: { navigation.selectedArea },
        set: { area in if let area { navigation.requestArea(area) } }
      )
    }
  }

  /// The models that each area's screen reads.
  ///
  /// One instance lives as long as the main window.
  @MainActor
  struct MainWindowScreens {
    /// Runtime state: controllers, profiles and service status.
    let runtime: RuntimeViewModel
    /// Support report and log export state.
    let supportReport: SupportReportModel
    /// The Controllers area's model.
    let controllers: ControllersViewModel
    /// The profile library that the Profiles area edits.
    let library: ProfileLibraryModel
    /// The Profiles area's list and editor model.
    let profiles: ProfilesViewModel
    /// The Activity area's model.
    let activity: ActivityModel
    /// The Explain Error Code sheet's model.
    let errorCodeExplainer: ErrorCodeExplainerModel
    /// The Library area's model.
    let libraryArea: LibraryViewModel
    /// The Access area's model.
    let access: AccessViewModel
    /// Restarts the app, for example after a permission change.
    let restartApplication: @MainActor () -> Void
    /// Opens the Input Test window for a controller.
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
  }

  /// The main window's content list column: the selected area's list half, or nothing for an
  /// area without one.
  struct MainWindowListRoot: View {
    /// Decides which area is selected.
    @ObservedObject
    var navigation: MainWindowNavigationModel
    /// Runtime state that the list screens read.
    @ObservedObject
    var runtime: RuntimeViewModel
    /// The Profiles area's list and editor model.
    @ObservedObject
    var profiles: ProfilesViewModel
    /// The models of every area's screen.
    let screens: MainWindowScreens

    /// The list half of the selected area, rebuilt when the area changes.
    var body: some View {
      list.id(navigation.selectedArea).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The list half of the selected area.
    @ViewBuilder
    private var list: some View {
      switch navigation.selectedArea {
      case .controllers:
        ControllersView(
          screen: screens.controllers,
          column: .list,
          openInputTest: screens.openInputTest
        )
      case .profiles:
        ProfilesView(
          viewModel: runtime,
          library: screens.library,
          navigation: navigation,
          screen: profiles,
          column: .list
        )
      case .library: LibraryAreaView(runtime: runtime, model: screens.libraryArea, column: .list)
      case .access, .activity: EmptyView()
      }
    }
  }

  /// The main window's content: the problem banner while something is wrong, then the
  /// selected area.
  struct MainWindowRoot: View {
    /// Decides which area is selected and holds the alerts for refused switches.
    @ObservedObject
    var navigation: MainWindowNavigationModel
    /// Runtime state: permissions, service status and driver setup.
    @ObservedObject
    var runtime: RuntimeViewModel
    /// The Profiles area's list and editor model.
    @ObservedObject
    var profiles: ProfilesViewModel
    /// The models of every area's screen.
    let screens: MainWindowScreens
    /// Whether opening System Settings for the driver extension approval failed, which shows an
    /// alert.
    @State
    private var driverApprovalFailed = false

    /// The problem banner above the selected area, with the alerts of the main window.
    var body: some View {
      VStack(spacing: OJDSpacing.none) {
        MainWindowProblemBanner(
          problems: MainWindowProblem.current(
            permissions: runtime.permissionState,
            status: runtime.statusState,
            driver: runtime.systemExtensionSetupState,
            extensionRouteConnected: runtime.statusState.hasExtensionRouteController,
            liveUpdatesFallbackReason: runtime.liveUpdatesFallbackReason,
            listenerFailure: runtime.listenerFailure
          ),
          perform: perform
        )
        area.id(navigation.selectedArea).frame(maxWidth: .infinity, maxHeight: .infinity)
      }.frame(
        maxWidth: .infinity,
        minHeight: 0,
        maxHeight: .infinity
      ).background(Color(NSColor.windowBackgroundColor)).onAppear { refreshIfNeeded() }.background(
        Color.clear.alert(isPresented: $navigation.isMutationRefusalPresented) {
          Alert(
            title: Text(OJDLocalized.string("ui.mainWindow.profileMutationRunning")),
            dismissButton: .default(Text(OJDLocalized.string("action.ok")))
          )
        }
      ).background(
        Color.clear.alert(isPresented: $driverApprovalFailed) {
          Alert(
            title: Text(OJDLocalized.string("platform.macos.ui.setup.openSystemSettingsFailed")),
            dismissButton: .default(Text(OJDLocalized.string("action.ok")))
          )
        }
      ).background(ErrorCodeExplainerSheetHost(model: screens.errorCodeExplainer)).alert(
        isPresented: $navigation.isDiscardConfirmationPresented
      ) {
        Alert(
          title: Text(OJDLocalized.string("ui.settings.advanced.discardTitle")),
          message: Text(OJDLocalized.string("ui.settings.advanced.discardProfileMessage")),
          primaryButton: .destructive(
            Text(OJDLocalized.string("ui.settings.advanced.discardAction"))
          ) {
            navigation.discardPendingArea()
          },
          secondaryButton: .cancel { navigation.cancelPendingArea() }
        )
      }
    }

    /// The detail half of the selected area.
    @ViewBuilder
    private var area: some View {
      switch navigation.selectedArea {
      case .controllers:
        ControllersView(
          screen: screens.controllers,
          column: .detail,
          openInputTest: screens.openInputTest
        )
      case .profiles:
        ProfilesView(
          viewModel: runtime,
          library: screens.library,
          navigation: navigation,
          screen: profiles,
          column: .detail
        )
      case .library: LibraryAreaView(runtime: runtime, model: screens.libraryArea, column: .detail)
      case .access:
        AccessAreaView(
          runtime: runtime,
          model: screens.access,
          restartApplication: screens.restartApplication
        )
      case .activity: ActivityView(model: screens.activity)
      }
    }

    /// Runs the fix that a problem in the banner offers.
    private func perform(_ action: MainWindowProblemAction) {
      switch action {
      case .retryService: Task { @MainActor in await runtime.refresh() }
      case .restartListener: Task { @MainActor in await runtime.restartListener() }
      case .openDriverApproval: driverApprovalFailed = !SystemExtensionApproval.openSystemSettings()
      case .repairDriver: Task { @MainActor in await runtime.repairSystemExtension() }
      case .showAccess:
        navigation.requestArea(.access)
        PermissionAccessActions.requestAccess(viewModel: runtime)
      }
    }

    /// Loads the runtime state when the first load has not finished.
    private func refreshIfNeeded() {
      guard case .loading = runtime.loadState else { return }
      Task { @MainActor in await runtime.refresh() }
    }
  }

#endif
