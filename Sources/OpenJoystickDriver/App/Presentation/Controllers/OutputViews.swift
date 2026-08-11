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
      .genericHID, .x360HID, .xoneHID, .sdl2_3, .appleGameController
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
        Text("Controller identity").font(.headline)
        if let outputError {
          HStack(alignment: .top, spacing: 8) {
            OJDSystemSymbol(name: "exclamationmark.triangle", fallback: "!").foregroundColor(
              Color(NSColor.systemRed)
            )
            VStack(alignment: .leading, spacing: 4) {
              Text("Needs attention").font(.subheadline.weight(.semibold))
              Text(outputError).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
                horizontal: false,
                vertical: true
              )
              Button("Try again") { retryOutput() }
            }
          }.ojdAccessibilityLabel("Controller identity error").ojdAccessibilityValue(outputError)
        }
        Picker("", selection: selectedIdentityBinding) {
          ForEach(outputIdentities, id: \.rawValue) { identity in
            Text(RuntimePresentation.compatibilityLabel(identity))
              // Keep each native radio row comfortable for keyboard and pointer users while
              // allowing long labels to wrap at compact widths and larger text sizes.
              .frame(minHeight: 28, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
              .tag(identity.rawValue as String?)
          }
        }.labelsHidden().pickerStyle(.radioGroup).frame(maxWidth: .infinity, alignment: .leading)
          .ojdAccessibilityLabel("Controller identity").ojdAccessibilityValue(
            selectedIdentityAccessibilityValue
          ).disabled(isOutputBusy)
        if isOutputBusy {
          HStack(spacing: 8) {
            OJDLoadingIndicator()
            Text("Updating controller identity…").foregroundColor(
              Color(NSColor.secondaryLabelColor)
            )
          }.ojdAccessibilityLabel("Updating controller identity")
        }
        Button("Reset to recommended") {
          // Keep the request scoped so a retry repeats the same identity mutation.
          retryIdentity = .sdl2_3
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

    private var selectedIdentityAccessibilityValue: String {
      if let selectedIdentity = currentIdentity {
        return RuntimePresentation.compatibilityLabel(selectedIdentity)
      }
      switch viewModel.compatibilityState {
      case .loading: return "Checking"
      case .error, .unavailable: return "Unavailable"
      case .available: return "Not selected"
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

#endif
