#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension OverviewView {

    var body: some View {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: OJDLocalized.string("settings.overview"))
            SystemExtensionSetupCard(
              viewModel: viewModel,
              supportReport: supportReport,
              navigation: navigation
            )
            accessSummary(width: proxy.size.width - 56)
            statusCard
          }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.onAppear { notificationPermission.refresh() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in notificationPermission.refresh() }
    }

    private func accessSummary(width: CGFloat) -> some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          accessCards(width: width)
          if needsPermissionRestart {
            Button(
              OJDLocalized.string(
                "permissions.restartApplication"
              ),
              action: restartApplication
            )
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("settings.accessReadiness")).font(
          .headline
        )
      }.ojdAccessibilityLabel(
        OJDLocalized.string(
          "settings.accessReadinessAccessibility"
        )
      ).ojdAccessibilityValue(accessSummaryValue)
    }

    @ViewBuilder
    private func accessCards(width: CGFloat) -> some View {
      if width >= 850 {
        HStack(alignment: .top, spacing: 12) {
          inputMonitoringCard
          accessibilityCard
          postEventCard
          notificationCard
        }
      } else if width >= 430 {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 12) {
            inputMonitoringCard
            accessibilityCard
          }
          HStack(alignment: .top, spacing: 12) {
            postEventCard
            notificationCard
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          inputMonitoringCard
          accessibilityCard
          postEventCard
          notificationCard
        }
      }
    }

    private var inputMonitoringCard: some View {
      AccessRequirementCard(
        title: OJDLocalized.string("common.inputMonitoring"),
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
    }

    private var accessibilityCard: some View {
      AccessRequirementCard(
        title: OJDLocalized.string("common.accessibility"),
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
    }

    private var postEventCard: some View {
      AccessRequirementCard(
        title: OJDLocalized.string("common.keyboardPointer"),
        value: postEventStatus.value,
        symbol: "cursorarrow",
        tone: postEventStatus.tone,
        action: postEventStatus.isActionable
          ? { PermissionAccessActions.requestPostEventAccess(viewModel: viewModel) } : nil
      )
    }

    private var notificationCard: some View {
      AccessRequirementCard(
        title: OJDLocalized.string("settings.notifications"),
        value: notificationStatus.value,
        symbol: "bell",
        tone: notificationStatus.tone,
        action: notificationStatus.isActionable
          ? { notificationPermission.requestOrOpenSettings() } : nil
      )
    }

    private var accessSummaryValue: String {
      [
        inputMonitoringStatus.value, accessibilityStatus.value, postEventStatus.value,
        notificationStatus.value,
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
          value: OJDLocalized.string("status.checking"),
          tone: .neutral,
          isActionable: true
        )
      }
      guard let requiresPostEventAccess = status.requiresPostEventAccess else {
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking"),
          tone: .neutral,
          isActionable: true
        )
      }
      guard requiresPostEventAccess else {
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.notNeeded"),
          tone: .neutral,
          isActionable: false
        )
      }
      switch status.postEventAccess {
      case .granted:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.allowed"),
          tone: .positive,
          isActionable: false
        )
      case .notAuthorized:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.needsAttention"),
          tone: .caution,
          isActionable: true
        )
      case nil:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking"),
          tone: .neutral,
          isActionable: true
        )
      }
    }

    private var notificationStatus: OverviewAccessStatus {
      switch notificationPermission.state {
      case .checking:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.checking"),
          tone: .neutral,
          isActionable: false
        )
      case .allowed:
        if notificationPermission.settings.alertStyle == .none {
          return OverviewAccessStatus(
            value: OJDLocalized.string("settings.notificationBannersOff"),
            tone: .caution,
            isActionable: true
          )
        }
        if notificationPermission.settings.soundsEnabled == false {
          return OverviewAccessStatus(
            value: OJDLocalized.string("settings.notificationSoundOff"),
            tone: .caution,
            isActionable: true
          )
        }
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.allowed"),
          tone: .positive,
          isActionable: false
        )
      case .notDetermined:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.notRequested"),
          tone: .caution,
          isActionable: true
        )
      case .denied:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.needsAttention"),
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

    private var needsPermissionRestart: Bool {
      guard let permissionSummary else { return false }
      return permissionSummary.inputMonitoring != .granted
        || permissionSummary.accessibility != .granted
    }

    private func permissionStatus(for state: RuntimePermissionState?) -> OverviewAccessStatus {
      switch state {
      case .granted:
        return OverviewAccessStatus(
          value: OJDLocalized.string("status.allowed"),
          tone: .positive,
          isActionable: false
        )
      case .denied, .unknown:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.needsAttention"),
          tone: .caution,
          isActionable: true
        )
      case nil:
        switch viewModel.permissionState {
        case .loading, .requesting:
          return OverviewAccessStatus(
            value: OJDLocalized.string("status.checking"),
            tone: .neutral,
            isActionable: true
          )
        case .available, .unavailable, .error:
          return OverviewAccessStatus(
            value: OJDLocalized.string("common.needsAttention"),
            tone: .caution,
            isActionable: true
          )
        }
      case .unavailable:
        return OverviewAccessStatus(
          value: OJDLocalized.string("common.unavailable"),
          tone: .caution,
          isActionable: true
        )
      }
    }

    private var statusCard: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 10) {
          HStack(alignment: .firstTextBaseline) {
            StatusBadge(status: statusTitle, semanticState: statusSemanticState)
            Spacer()
            Button(OJDLocalized.string("common.refresh")) {
              Task { @MainActor in await viewModel.refresh() }
            }
          }
          Text(statusDetail).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }.padding(4)
      }.ojdAccessibilityLabel(
        OJDLocalized.string("settings.controllerStatus")
      ).ojdAccessibilityValue(statusDetail)
    }

    private var statusTitle: String {
      switch viewModel.statusState {
      case .loading: return OJDLocalized.string("status.starting")
      case .available(let status): return status.readinessLabel
      case .unavailable, .error:
        return OJDLocalized.string("common.needsAttention")
      }
    }

    private var statusSemanticState: SemanticState {
      switch viewModel.statusState {
      case .available(let status): return status.readiness == .ready ? .healthy : .attention
      case .loading: return .loading
      case .unavailable, .error: return .failure
      }
    }

    private var statusDetail: String {
      switch viewModel.statusState {
      case .loading:
        return OJDLocalized.string(
          "status.checkingControllerAccess"
        )
      case .unavailable(let message), .error(let message): return message
      case .available(let status): return status.deviceCountLabel
      }
    }
  }

#endif
