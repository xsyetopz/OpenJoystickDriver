#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct ControllerIdentityView: View {
    @ObservedObject var viewModel: RuntimeViewModel
    let embedded: Bool
    // Retain a failed request only so Try again can repeat it. The Picker must show the
    // authoritative runtime value, never an identity whose update failed.
    @State private var retryIdentity: CompatibilityIdentity?

    private let outputIdentities: [CompatibilityIdentity] = [
      .automatic, .genericHID, .xbox360HID, .sdl2_3, .appleGameController
    ]

    init(viewModel: RuntimeViewModel, embedded: Bool = false) {
      self.viewModel = viewModel
      self.embedded = embedded
    }

    @ViewBuilder var body: some View {
      if embedded { content } else { GroupBox { content.padding(4) } }
    }

    private var content: some View {
      VStack(alignment: .leading, spacing: 10) {
        Text(OJDLocalized.string("common.controllerIdentity", fallback: "Controller identity"))
          .font(.headline)
        if let outputError {
          HStack(alignment: .top, spacing: 8) {
            OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
              Color(NSColor.systemRed)
            )
            VStack(alignment: .leading, spacing: 4) {
              Text(OJDLocalized.string("common.needsAttention", fallback: "Needs attention")).font(
                .subheadline.weight(.semibold)
              )
              Text(outputError).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
                horizontal: false,
                vertical: true
              )
              Button(OJDLocalized.string("common.tryAgain", fallback: "Try again")) {
                retryOutput()
              }
            }
          }.ojdAccessibilityLabel(
            OJDLocalized.string("identity.error", fallback: "Controller identity error")
          ).ojdAccessibilityValue(outputError)
        }
        VStack(alignment: .leading, spacing: 8) {
          identityRow(Array(outputIdentities.prefix(2)))
          identityRow(Array(outputIdentities.dropFirst(2)))
        }.frame(maxWidth: .infinity, alignment: .leading).ojdAccessibilityLabel(
          OJDLocalized.string("common.controllerIdentity", fallback: "Controller identity")
        ).ojdAccessibilityValue(selectedIdentityAccessibilityValue)
        if isOutputBusy {
          HStack(spacing: 8) {
            OJDLoadingIndicator()
            Text(
              OJDLocalized.string("identity.updating", fallback: "Updating controller identity...")
            ).foregroundColor(Color(NSColor.secondaryLabelColor))
          }.ojdAccessibilityLabel(
            OJDLocalized.string("identity.updating", fallback: "Updating controller identity...")
          )
        }
        Button(OJDLocalized.string("identity.reset", fallback: "Reset to recommended")) {
          // Keep the request scoped so a retry repeats the same identity mutation.
          retryIdentity = .automatic
          Task { @MainActor in await viewModel.resetCompatibilityIdentity() }
        }.disabled(isOutputBusy)
      }.onReceive(viewModel.$compatibilityState) { state in
        if case .available = state { retryIdentity = nil }
      }
    }

    private var currentIdentity: CompatibilityIdentity? {
      guard case .available(let identity) = viewModel.compatibilityState else { return nil }
      return identity
    }

    private var selectedIdentityBinding: Binding<String?> {
      Binding(
        get: { currentIdentity?.rawValue },
        set: { rawValue in
          guard let rawValue, let identity = CompatibilityIdentity(rawValue: rawValue) else {
            return
          }
          selectIdentity(identity)
        }
      )
    }

    private func identityRow(_ identities: [CompatibilityIdentity]) -> some View {
      HStack(spacing: 18) {
        ForEach(identities, id: \.rawValue) { identity in
          IdentityRadioButton(
            title: RuntimePresentation.compatibilityLabel(identity),
            value: identity.rawValue,
            selection: selectedIdentityBinding,
            isEnabled: !isOutputBusy
          ).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
      }
    }

    private var selectedIdentityAccessibilityValue: String {
      if let selectedIdentity = currentIdentity {
        return RuntimePresentation.compatibilityLabel(selectedIdentity)
      }
      switch viewModel.compatibilityState {
      case .loading: return OJDLocalized.string("status.checking", fallback: "Checking")
      case .error, .unavailable:
        return OJDLocalized.string("common.unavailable", fallback: "Unavailable")
      case .available: return OJDLocalized.string("common.notSelected", fallback: "Not selected")
      }
    }

    private var isOutputBusy: Bool {
      if case .loading = viewModel.compatibilityState { return true }
      return false
    }

    private var outputError: String? {
      switch viewModel.compatibilityState {
      case .error(let message), .unavailable(let message): return message
      case .loading: return nil
      case .available: return viewModel.compatibilityError
      }
    }

    private func selectIdentity(_ identity: CompatibilityIdentity) {
      retryIdentity = identity
      Task { @MainActor in await viewModel.setCompatibilityIdentity(identity) }
    }

    private func retryOutput() {
      if let retryIdentity {
        selectIdentity(retryIdentity)
      } else {
        Task { @MainActor in await viewModel.loadCompatibilityIdentity() }
      }
    }
  }

  private struct IdentityRadioButton: NSViewRepresentable {
    let title: String
    let value: String
    let selection: Binding<String?>
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSButton {
      NSButton(
        radioButtonWithTitle: title,
        target: context.coordinator,
        action: #selector(Coordinator.select(_:))
      )
    }

    func updateNSView(_ button: NSButton, context: Context) {
      context.coordinator.parent = self
      button.title = title
      button.state = selection.wrappedValue == value ? .on : .off
      button.isEnabled = isEnabled
      button.setAccessibilityLabel(title)
    }

    final class Coordinator: NSObject {
      var parent: IdentityRadioButton

      init(parent: IdentityRadioButton) { self.parent = parent }

      @objc func select(_ sender: NSButton) { parent.selection.wrappedValue = parent.value }
    }
  }

#endif
