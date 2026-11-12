#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The override of one controller model's virtual gamepad kind, matching
  /// `ojd virtual set|reset`: Automatic clears the override.
  struct VirtualHIDProfileOverrideView: View {
    /// The model of the app's view of the service, which sends the override.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The controller.
    let device: ApplicationServiceDeviceDescription
    /// How much of the interface shows: the identifier of a kind shows only in Advanced.
    @Environment(\.ojdInterfaceLevel)
    private var interfaceLevel
    /// The scope of the override: the model or only this controller.
    @State
    private var scope: VirtualHIDProfileScopeChoice

    /// Creates the view with the scope of the stored override.
    ///
    /// - Parameters:
    ///   - viewModel: The model of the app's view of the service.
    ///   - device: The controller.
    init(viewModel: RuntimeViewModel, device: ApplicationServiceDeviceDescription) {
      self.viewModel = viewModel
      self.device = device
      _scope = State(initialValue: VirtualHIDProfileScopeChoice.initial(for: device))
    }

    /// The profile picker, the scope picker, the progress and the problems.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Picker(
          OJDLocalized.string("ui.virtualProfile.title"),
          selection: overrideBinding
        ) {
          Text(ControllerDetailFacts.automaticProfileLabel(device)).tag(
            VirtualHIDProfileID?.none
          )
          ForEach(VirtualHIDProfileKinds.offered(for: device), id: \.self) { profile in
            Text(VirtualHIDProfileKinds.optionTitle(for: profile, level: interfaceLevel)).tag(
              VirtualHIDProfileID?.some(profile)
            )
          }
        }.disabled(overrideState.inFlight)
        if let text = VirtualHIDProfileKinds.inForceText(for: device) {
          Text(text).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
        }
        if VirtualHIDProfileScopeChoice.offered(for: device).count > 1 {
          Picker(OJDLocalized.string("ui.controllers.virtual.scope"), selection: $scope) {
            ForEach(VirtualHIDProfileScopeChoice.offered(for: device), id: \.self) { choice in
              Text(OJDLocalized.string(choice.titleKey)).tag(choice)
            }
          }.disabled(overrideState.inFlight)
          if let holder = VirtualHIDProfileOverrideDecision.currentScope(for: device),
            holder != scope
          {
            Text(
              OJDLocalized.formatted(
                "ui.controllers.virtual.currentScope",
                OJDLocalized.string(holder.titleKey)
              )
            ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        }
        if overrideState.inFlight {
          HStack(spacing: OJDSpacing.small) {
            ProgressView()
            Text(updatingLabel).foregroundColor(Color(NSColor.secondaryLabelColor))
          }.ojdAccessibilityLabel(updatingLabel)
        }
        if let notice = overrideState.notice {
          Text(notice).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(problems, id: \.self) { message in
          HStack(alignment: .top, spacing: OJDSpacing.small) {
            OJDSystemSymbol(
              name: SemanticState.failure.presentation.symbolName,
              fallback: OJDLocalized.string("status.needsAttention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }.ojdAccessibilityLabel(
            OJDLocalized.string("status.needsAttention")
          ).ojdAccessibilityValue(message)
        }
      }
    }

    /// Shared by every connected controller of this model, like the override itself.
    private var overrideState: RuntimeVirtualHIDProfileOverrideState {
      viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(device)]
        ?? RuntimeVirtualHIDProfileOverrideState()
    }

    /// The binding to the override that is shown, which is the pending choice until the status
    /// reports it; choosing one sends the change, or shows why nothing is sent.
    private var overrideBinding: Binding<VirtualHIDProfileID?> {
      Binding(
        get: {
          // Show the pending choice until the refreshed status reports the stored override.
          if let request = overrideState.request { return request.requested }
          return device.virtualHIDProfile?.override
        },
        set: { profile in
          let target = device
          let selectedScope = scope
          Task { @MainActor in
            await viewModel.chooseVirtualHIDProfile(profile, scope: selectedScope, for: target)
          }
        }
      )
    }

    /// The text of the progress.
    private var updatingLabel: String {
      OJDLocalized.string("ui.virtualProfile.updating")
    }

    /// The message of the failed override; the override store's messages show in the main window
    /// banner.
    private var problems: [String] { overrideState.failure.map { [$0] } ?? [] }
  }

#endif
