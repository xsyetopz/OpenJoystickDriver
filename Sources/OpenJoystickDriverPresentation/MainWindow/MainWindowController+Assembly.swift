#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension MainWindowController {
    /// The screens of every area, with the diagnostic fixes wired to the runtime and navigation.
    static func makeScreens(
      runtime: RuntimeViewModel,
      supportReport: SupportReportModel,
      navigation: MainWindowNavigationModel,
      restartApplication: @escaping @MainActor () -> Void,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void
    ) -> MainWindowScreens {
      MainWindowScreens(
        runtime: runtime,
        supportReport: supportReport,
        controllers: ControllersViewModel(runtime: runtime),
        library: ProfileLibraryModel(runtime: runtime),
        profiles: ProfilesViewModel(),
        activity: ActivityModel(
          log: ActivityLogModel(),
          diagnostics: ActivityDiagnosticsModel {
            await ActivityDiagnosticsChecks.run(gateway: supportReport.gateway)
          }
        ) { fix in performFix(fix, runtime: runtime, navigation: navigation) },
        errorCodeExplainer: ErrorCodeExplainerModel(),
        whatsNew: WhatsNewModel(),
        libraryArea: LibraryViewModel(),
        access: AccessViewModel(),
        restartApplication: restartApplication,
        openInputTest: openInputTest
      )
    }

    /// Does the action of a diagnostic fix button; returns why it could not, if it could not.
    static func performFix(
      _ fix: ActivityCheckFix,
      runtime: RuntimeViewModel,
      navigation: MainWindowNavigationModel
    ) -> String? {
      switch fix {
      case .requestInputRead:
        PermissionAccessActions.requestControllerAccess(
          viewModel: runtime,
          requirement: .inputRead
        )
      case .requestInputInject:
        PermissionAccessActions.requestControllerAccess(
          viewModel: runtime,
          requirement: .inputInject
        )
      case .approveDriver:
        if !SystemExtensionApproval.openSystemSettings() {
          return OJDLocalized.string(
            SystemSettingsMessage.openSettingsFailed.localizationKey()
          )
        }
      case .showLibrary: _ = navigation.requestArea(.library)
      }
      return nil
    }

    /// The sidebar column, which the sidebar toggle collapses.
    static func makeSidebarItem(navigation: MainWindowNavigationModel) -> NSSplitViewItem {
      let sidebar = NSSplitViewItem(
        sidebarWithViewController: NSHostingController(
          rootView: MainWindowSidebar(navigation: navigation)
        )
      )
      sidebar.canCollapse = true
      sidebar.minimumThickness = MainWindowSizingPolicy.sidebarWidth.minimum
      sidebar.maximumThickness = MainWindowSizingPolicy.sidebarWidth.maximum
      return sidebar
    }

    /// The content list column, collapsed for an area without a list.
    static func makeListItem(
      navigation: MainWindowNavigationModel,
      runtime: RuntimeViewModel,
      screens: MainWindowScreens,
      preferences: SettingsPreferencesModel,
      visibility: WindowVisibility
    ) -> NSSplitViewItem {
      let list = NSSplitViewItem(
        contentListWithViewController: NSHostingController(
          rootView: MainWindowListRoot(
            navigation: navigation,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens,
            preferences: preferences,
            visibility: visibility
          )
        )
      )
      list.minimumThickness = MainWindowSizingPolicy.listWidth.minimum
      list.maximumThickness = MainWindowSizingPolicy.listWidth.maximum
      list.isCollapsed = !navigation.selectedArea.hasListColumn
      return list
    }

    /// The detail column.
    static func makeDetailItem(
      navigation: MainWindowNavigationModel,
      runtime: RuntimeViewModel,
      screens: MainWindowScreens,
      preferences: SettingsPreferencesModel,
      visibility: WindowVisibility
    ) -> NSSplitViewItem {
      let detailItem = NSSplitViewItem(
        viewController: NSHostingController(
          rootView: MainWindowRoot(
            navigation: navigation,
            runtime: runtime,
            profiles: screens.profiles,
            screens: screens,
            preferences: preferences,
            visibility: visibility
          )
        )
      )
      detailItem.minimumThickness = MainWindowSizingPolicy.minimumDetailWidth
      return detailItem
    }

    /// The window that shows `content`.
    static func makeWindow(content: NSSplitViewController) -> NSWindow {
      let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: MainWindowSizingPolicy.defaultContentSize),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.identifier = NSUserInterfaceItemIdentifier("mainWindow")
      window.hidesOnDeactivate = false
      window.isReleasedWhenClosed = false
      window.contentViewController = content
      return window
    }
  }

#endif
