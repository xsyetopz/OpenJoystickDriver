#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  // MARK: - Overview and status

  struct OverviewView: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let supportReport: SupportReportModel
    @ObservedObject
    var navigation: SettingsNavigationModel
    @ObservedObject
    var notificationPermission: NotificationPermissionModel
    let restartApplication: @MainActor () -> Void

    init(
      viewModel: RuntimeViewModel,
      supportReport: SupportReportModel,
      navigation: SettingsNavigationModel,
      notificationPermission: NotificationPermissionModel = NotificationPermissionModel(),
      restartApplication: @escaping @MainActor () -> Void
    ) {
      self.viewModel = viewModel
      self.supportReport = supportReport
      self.navigation = navigation
      self.notificationPermission = notificationPermission
      self.restartApplication = restartApplication
    }
  }

  struct OverviewAccessStatus {
    let value: String
    let tone: SemanticTone
    let isActionable: Bool
  }

  struct AccessRequirementCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: SemanticTone
    let action: (() -> Void)?

    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        OJDSystemSymbol(name: symbol, fallback: nil).foregroundColor(Color(tone.color)).frame(
          width: 20,
          height: 20
        ).accessibilityHidden(true)
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
    let semanticState: SemanticState

    var body: some View {
      HStack(spacing: 7) {
        OJDSystemSymbol(
          name: semanticState.presentation.symbolName,
          fallback: OJDLocalized.string("common.status", fallback: "Status")
        ).accessibilityHidden(true)
        Text(status).font(.headline.weight(.semibold))
      }.foregroundColor(Color(semanticState.presentation.tone.color)).ojdAccessibilityLabel(
        OJDLocalized.string("common.status", fallback: "Status")
      ).ojdAccessibilityValue(status)
    }
  }

#endif
