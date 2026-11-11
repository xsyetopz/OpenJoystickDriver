#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that asks to confirm an access operation, with the scope toggles of a program grant.
  struct AccessConfirmationSheet: View {
    /// The state and actions of the Access area.
    @ObservedObject
    var model: AccessViewModel
    /// The operation to confirm.
    let pending: AccessPending

    /// The title and lines of the confirmation, with scope toggles for a client grant.
    var body: some View {
      let confirmation = model.confirmation(for: pending)
      VStack(alignment: .leading, spacing: 14) {
        Text(confirmation.title).font(.headline).fixedSize(horizontal: false, vertical: true)
        if case .grantClient = pending { scopeToggles(scopes: $model.grantScopes) }
        ForEach(confirmation.lines, id: \.self) { line in
          Text(line).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { model.cancelSheet() }.keyboardShortcut(
            .cancelAction
          ).ojdAccessibilityLabel(OJDLocalized.string("a11y.access.cancel"))
          Button(confirmation.confirmTitle) { Task { await model.confirm(pending) } }
            .keyboardShortcut(.defaultAction).disabled(grantsNothing)
            .ojdAccessibilityLabel(confirmation.confirmTitle)
        }
      }.padding(20).frame(width: 440)
    }

    /// Whether a program grant has no scope chosen, which disables the confirm button.
    private var grantsNothing: Bool {
      if case .grantClient = pending { return model.grantScopes.isEmpty }
      return false
    }
  }

  /// The sheet with the form that creates a token: a name, web origins and scopes.
  struct AccessTokenFormSheet: View {
    /// The state and actions of the Access area, which hold the draft.
    @ObservedObject
    var model: AccessViewModel

    /// The token name, origins and scopes, a failure if any, and the Cancel and Continue buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text(OJDLocalized.string("ui.access.token.form.title")).font(.headline)
        TextField(OJDLocalized.string("ui.access.token.name"), text: $model.tokenDraft.name)
          .ojdAccessibilityLabel(OJDLocalized.string("a11y.access.tokenName"))
        Text(OJDLocalized.string("ui.access.token.origins")).font(.body)
        TextEditor(text: $model.tokenDraft.originsText).font(.body).frame(height: 70)
          .ojdAccessibilityLabel(OJDLocalized.string("a11y.access.tokenOrigins"))
        scopeToggles(scopes: $model.tokenDraft.scopes)
        if let failure = model.failure {
          Text(failure.message).foregroundColor(Color(SemanticTone.failure.color))
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { model.cancelSheet() }.keyboardShortcut(
            .cancelAction
          ).ojdAccessibilityLabel(OJDLocalized.string("a11y.access.cancel"))
          Button(OJDLocalized.string("ui.access.token.continue")) { model.requestGrantToken() }
            .keyboardShortcut(.defaultAction).ojdAccessibilityLabel(
              OJDLocalized.string("a11y.access.tokenContinue")
            )
        }
      }.padding(20).frame(width: 440)
    }
  }

  /// The sheet that shows a created token once, with a Copy button.
  struct AccessIssuedTokenSheet: View {
    /// The token that was created.
    let issued: AccessIssuedToken
    /// Closes the sheet.
    let close: () -> Void

    /// The issued token with its message, a Copy button and a Done button.
    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text(OJDLocalized.formatted("ui.access.token.issued.title", issued.name)).font(.headline)
        Text(OJDLocalized.string("ui.access.token.issued.message")).foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
        Text(issued.token).font(.system(.body, design: .monospaced)).textSelection(.enabled)
          .ojdAccessibilityLabel(OJDLocalized.string("a11y.access.tokenValue"))
        HStack {
          Button(OJDLocalized.string("ui.access.token.copy")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(issued.token, forType: .string)
          }.ojdAccessibilityLabel(OJDLocalized.string("a11y.access.copyToken"))
          Spacer()
          Button(OJDLocalized.string("ui.access.done"), action: close).keyboardShortcut(
            .defaultAction
          ).ojdAccessibilityLabel(OJDLocalized.string("a11y.access.done"))
        }
      }.padding(20).frame(width: 440)
    }
  }

  /// One toggle per scope.
  @MainActor
  @ViewBuilder
  private func scopeToggles(scopes: Binding<Set<EndpointScope>>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(EndpointScope.allCases, id: \.self) { scope in
        Toggle(
          AccessPresentation.scope(scope),
          isOn: Binding(
            get: { scopes.wrappedValue.contains(scope) },
            set: { isOn in
              if isOn {
                scopes.wrappedValue.insert(scope)
              } else {
                scopes.wrappedValue.remove(scope)
              }
            }
          )
        ).ojdAccessibilityLabel(
          OJDLocalized.formatted("a11y.access.scope", AccessPresentation.scope(scope))
        )
      }
    }
  }

  /// Opens the file panel for choosing a program.
  @MainActor
  enum AccessFilePicker {
    /// A program or app bundle that is to be granted access.
    static func chooseProgram() -> URL? {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseFiles = true
      panel.canChooseDirectories = false
      panel.treatsFilePackagesAsDirectories = false
      panel.message = OJDLocalized.string("ui.access.grant.pick")
      panel.prompt = OJDLocalized.string("ui.access.choose")
      return panel.runModal() == .OK ? panel.url : nil
    }
  }

#endif
