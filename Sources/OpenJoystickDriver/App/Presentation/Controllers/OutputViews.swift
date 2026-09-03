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
        Text(
          OJDLocalized.string(
            "identity.globalScope",
            fallback: "Applies to all virtual controllers published by OpenJoystickDriver."
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
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
        identityChoices.ojdAccessibilityLabel(
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
        HStack {
          Button(OJDLocalized.string("identity.reset", fallback: "Reset to recommended")) {
            // Keep the request scoped so a retry repeats the same identity mutation.
            retryIdentity = .automatic
            Task { @MainActor in await viewModel.resetCompatibilityIdentity() }
          }.disabled(isOutputBusy)
          Spacer()
        }
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
      case .loading: return OJDLocalized.string("status.checking", fallback: "Checking")
      case .error, .unavailable:
        return OJDLocalized.string("common.unavailable", fallback: "Unavailable")
      case .available: return OJDLocalized.string("common.notSelected", fallback: "Not selected")
      }
    }

    @ViewBuilder private var identityChoices: some View {
      GeometryReader { proxy in
        let spacing: CGFloat = 18
        let columnWidth = max(0, (proxy.size.width - spacing * 2) / 3)
        VStack(alignment: .leading, spacing: 8) {
          ForEach(0..<2, id: \.self) { row in
            HStack(alignment: .top, spacing: spacing) {
              ForEach(0..<3, id: \.self) { column in
                let index = row * 3 + column
                Group {
                  if index < outputIdentities.count {
                    identityChoice(outputIdentities[index])
                  } else {
                    Color.clear.frame(minHeight: 28)
                  }
                }.frame(width: columnWidth, alignment: .leading)
              }
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(height: 64)
    }

    private func identityChoice(_ identity: CompatibilityIdentity) -> some View {
      IdentityRadioButton(
        title: RuntimePresentation.compatibilityLabel(identity),
        value: identity.rawValue,
        selection: selectedIdentityBinding,
        isEnabled: !isOutputBusy && isIdentityAvailable(identity)
      ).frame(minHeight: 28, alignment: .leading)
    }

    private func isIdentityAvailable(_ identity: CompatibilityIdentity) -> Bool {
      if identity == .automatic || identity == .genericHID { return true }
      guard case .available(let status) = viewModel.statusState, !status.devices.isEmpty else {
        return true
      }
      return status.devices.allSatisfy {
        CompatibilityProfileAvailabilityPolicy.decision(for: $0, identity: identity).isAvailable
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

    func makeNSView(context: Context) -> IdentityRadioButtonHostView {
      let button = NSButton(
        radioButtonWithTitle: title,
        target: context.coordinator,
        action: #selector(Coordinator.select(_:))
      )
      return IdentityRadioButtonHostView(button: button)
    }

    func updateNSView(_ hostView: IdentityRadioButtonHostView, context: Context) {
      context.coordinator.parent = self
      let button = hostView.button
      button.title = title
      button.state = selection.wrappedValue == value ? .on : .off
      button.isEnabled = isEnabled
      button.setAccessibilityLabel(title)
      hostView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject {
      var parent: IdentityRadioButton

      init(parent: IdentityRadioButton) { self.parent = parent }

      @objc func select(_ sender: NSButton) { parent.selection.wrappedValue = parent.value }
    }
  }

  private final class IdentityRadioButtonHostView: NSView {
    let button: NSButton

    init(button: NSButton) {
      self.button = button
      super.init(frame: .zero)
      button.translatesAutoresizingMaskIntoConstraints = false
      addSubview(button)
      NSLayoutConstraint.activate([
        button.leadingAnchor.constraint(equalTo: leadingAnchor),
        button.centerYAnchor.constraint(equalTo: centerYAnchor),
        button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
      ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
      NSSize(
        width: button.intrinsicContentSize.width,
        height: max(28, button.intrinsicContentSize.height)
      )
    }
  }

#endif
