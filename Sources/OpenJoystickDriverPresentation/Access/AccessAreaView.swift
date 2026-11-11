#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Access area: what macOS lets the app do, and which programs and web pages may use the
  /// endpoint that `ojd access` manages.
  ///
  /// One grouped form; Grant and Create are toolbar actions.
  struct AccessAreaView: View {
    /// Runtime state, which holds the macOS permissions and the service status.
    @ObservedObject
    var runtime: RuntimeViewModel
    /// The state and actions of the Access area.
    @ObservedObject
    var model: AccessViewModel
    /// Restarts the app, which an input permission needs before it takes effect.
    let restartApplication: @MainActor () -> Void
    /// Reads and requests the notification permission.
    @StateObject
    private var notificationPermission: NotificationPermissionModel

    /// Creates the Access area on `runtime` and `model`.
    @MainActor
    init(
      runtime: RuntimeViewModel,
      model: AccessViewModel,
      restartApplication: @escaping @MainActor () -> Void
    ) {
      self.runtime = runtime
      self.model = model
      self.restartApplication = restartApplication
      _notificationPermission = StateObject(wrappedValue: NotificationPermissionModel())
    }

    /// The macOS permissions as the permission rows show them.
    private var readiness: AccessReadiness {
      AccessReadiness(
        permissionState: runtime.permissionState,
        statusState: runtime.statusState,
        notificationState: notificationPermission.state,
        notificationSettings: notificationPermission.settings
      )
    }

    /// The Access form: the failure, if any, the permissions, then the load state or the endpoints
    /// and lists.
    var body: some View {
      ScrollViewReader { proxy in
        form.onReceive(model.$focusedPermission) { permission in
          guard let permission else { return }
          withAnimation { proxy.scrollTo(permission.rawValue, anchor: .top) }
          model.focusedPermission = nil
        }
      }
    }

    /// The form of the area.
    private var form: some View {
      Form {
        if let failure = model.failure {
          Section {
            errorView(failure, actionTitle: "ui.access.dismiss", action: model.dismissFailure)
          }
        }
        permissionsSection
        switch model.load {
        case .loading:
          Section { LoadingStateView(message: OJDLocalized.string("ui.access.loading")) }
        case .failed(let failure):
          Section {
            errorView(
              failure,
              actionTitle: "ui.access.tryAgain",
              migrates: failure.code == .unsupportedAPIVersion
            ) { Task { await model.refresh() } }
          }
        case .loaded(let status):
          endpointsSection(status)
          listSections(status)
        }
      }.ojdGroupedForm().onAppear { notificationPermission.refresh() }.onReceive(
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
      ) { _ in notificationPermission.refresh() }.task { await model.refresh() }.sheet(
        item: $model.sheet
      ) { sheet in
        switch sheet {
        case .confirm(let pending):
          AccessConfirmationSheet(model: model, pending: pending)
        case .tokenForm:
          AccessTokenFormSheet(model: model)
        case .issuedToken(let issued):
          AccessIssuedTokenSheet(issued: issued) { model.closeIssuedToken() }
        }
      }
    }

    /// Returns an inline error with a button that runs `action`; `actionTitle` is a localization
    /// key. `migrates` adds the Migrate button.
    private func errorView(
      _ failure: AccessFailure,
      actionTitle: String,
      migrates: Bool = false,
      action: @escaping () -> Void
    ) -> some View {
      InlineErrorView(
        message: failure.message,
        code: failure.code,
        detailsTitle: OJDLocalized.string("ui.access.details"),
        detailsAccessibilityLabel: OJDLocalized.string("a11y.access.details"),
        actionTitle: OJDLocalized.string(actionTitle),
        actionAccessibilityLabel: OJDLocalized.string(
          actionTitle == "ui.access.dismiss" ? "a11y.access.dismissError" : "a11y.access.tryAgain"
        ),
        action: action,
        secondaryActionTitle: migrates ? OJDLocalized.string("ui.migrate.action") : nil,
        secondaryAction: migrates ? { Task { await model.migrate() } } : nil
      )
    }

    // MARK: macOS permissions

    /// The section of macOS permission rows, with a restart button while an input permission is
    /// missing.
    private var permissionsSection: some View {
      let current = readiness
      return Section(header: Text(OJDLocalized.string("ui.settings.notifications.accessReadiness")))
      {
        ForEach(current.rows) { row in permissionRow(row).id(row.id) }
        if current.needsRestart {
          Button(
            OJDLocalized.string("ui.permissions.restartApplication"),
            action: restartApplication
          )
          .ojdAccessibilityLabel(OJDLocalized.string("a11y.access.restart"))
        }
      }
    }

    /// Returns the row for a permission, with a button when the permission is missing.
    private func permissionRow(_ row: AccessPermissionRow) -> some View {
      let title = OJDLocalized.string(row.titleKey)
      return OJDLabeledRow(title) {
        HStack {
          Text(row.status.value)
          if let key = row.actionTitleKey {
            Button(OJDLocalized.string(key)) { requestPermission(row.kind) }
              .ojdAccessibilityLabel(
                OJDLocalized.formatted("ui.settings.notifications.requestAccess", title)
              )
              .ojdAccessibilityValue(row.status.value)
          }
        }
      }
    }

    /// Asks macOS for the permission that the row stands for.
    private func requestPermission(_ kind: AccessPermissionRow.Kind) {
      switch kind {
      case .inputRead:
        PermissionAccessActions.requestControllerAccess(viewModel: runtime, requirement: .inputRead)
      case .inputInject:
        PermissionAccessActions.requestControllerAccess(
          viewModel: runtime,
          requirement: .inputInject
        )
      case .postEvent: PermissionAccessActions.requestPostEventAccess(viewModel: runtime)
      case .notification: notificationPermission.requestOrOpenSettings()
      }
    }

    // MARK: Endpoints

    /// Returns the section of the local endpoint toggle, the WebSocket toggle and the port field.
    private func endpointsSection(_ status: AccessStatusPayload) -> some View {
      Section {
        Toggle(
          OJDLocalized.string("ui.access.endpoint"),
          isOn: Binding(
            get: { status.enabled },
            set: { isOn in
              if isOn {
                model.requestEnableEndpoint()
              } else {
                Task { await model.disableEndpoint() }
              }
            }
          )
        ).disabled(model.busy).help(OJDLocalized.formatted("ui.access.socket", status.socketPath))
          .contextMenu { copySocketPathButton(status) }
        if status.enabled { copySocketPathButton(status) }
        Toggle(
          OJDLocalized.string("ui.access.web"),
          isOn: Binding(
            get: { status.web.enabled },
            set: { isOn in
              if isOn { model.requestEnableWeb() } else { Task { await model.disableWeb() } }
            }
          )
        ).disabled(model.busy).help(
          OJDLocalized.formatted(
            "ui.access.web.pages",
            AccessPresentation.location(status.web.pagesPath)
          )
        )
        if status.web.enabled {
          Text(AccessPresentation.web(status.web)).font(.caption).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          ).textSelection(.enabled)
        } else {
          OJDLabeledRow(OJDLocalized.string("ui.access.web.port")) {
            HStack {
              if model.canChooseAutomaticPort {
                Button(OJDLocalized.string("ui.access.web.port.choose")) {
                  model.chooseAutomaticPort()
                }.ojdAccessibilityLabel(OJDLocalized.string("ui.access.web.port.choose"))
              }
              portField.labelsHidden().textFieldStyle(RoundedBorderTextFieldStyle())
                .multilineTextAlignment(.trailing).frame(width: 120)
                .ojdAccessibilityLabel(OJDLocalized.string("a11y.access.webPort"))
            }
          }
        }
      }
    }

    /// The port field: its placeholder is the saved port that an empty field keeps, or
    /// "Automatic" when enabling the WebSocket picks a free port.
    @ViewBuilder
    private var portField: some View {
      if #available(macOS 13, *) {
        TextField(
          OJDLocalized.string("ui.access.web.port"),
          text: $model.portText,
          prompt: Text(model.portPlaceholder)
        )
      } else {
        TextField(model.portPlaceholder, text: $model.portText)
      }
    }

    /// Returns a button that copies the endpoint's socket path.
    private func copySocketPathButton(_ status: AccessStatusPayload) -> some View {
      Button(OJDLocalized.string("ui.access.socket.copy")) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(status.socketPath, forType: .string)
      }.ojdAccessibilityLabel(OJDLocalized.string("ui.access.socket.copy"))
    }
  }

#endif
