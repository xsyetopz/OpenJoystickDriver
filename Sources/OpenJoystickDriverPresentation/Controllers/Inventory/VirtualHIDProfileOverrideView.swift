#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The override of one controller model's virtual HID profile, matching
  /// `ojd virtual set|reset`: Automatic clears the override.
  struct VirtualHIDProfileOverrideView: View {
    /// The model of the app's view of the service, which sends the override.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The controller.
    let device: ApplicationServiceDeviceDescription
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

    /// The profile picker, the scope picker or the model-scope note, the progress and the problems.
    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          OJDLocalized.string("ui.virtualProfile.title"),
          selection: overrideBinding
        ) {
          Text(ControllerDetailFacts.automaticProfileLabel(device)).tag(
            VirtualHIDProfileID?.none
          )
          ForEach(VirtualHIDProfileID.allCases, id: \.self) { profile in
            Text("\(profile.identity.productName) (\(profile.rawValue))").tag(
              VirtualHIDProfileID?.some(profile)
            )
          }
        }.disabled(overrideState.inFlight)
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
        } else {
          Text(OJDLocalized.string("ui.virtualProfile.modelScope")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
        }
        if overrideState.inFlight {
          HStack(spacing: 8) {
            ProgressView()
            Text(updatingLabel).foregroundColor(Color(NSColor.secondaryLabelColor))
          }.ojdAccessibilityLabel(updatingLabel)
        }
        ForEach(problems, id: \.self) { message in
          HStack(alignment: .top, spacing: 8) {
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
    /// reports it; choosing one sends the change when it would change anything.
    private var overrideBinding: Binding<VirtualHIDProfileID?> {
      Binding(
        get: {
          // Show the pending choice until the refreshed status reports the stored override.
          if let request = overrideState.request { return request.requested }
          return device.virtualHIDProfile?.override
        },
        set: { profile in
          guard
            VirtualHIDProfileOverrideDecision.decide(profile: profile, scope: scope, for: device)
              == .send
          else { return }
          let device = device
          let scope = scope.scope
          Task { @MainActor in
            await viewModel.setVirtualHIDProfileOverride(profile, for: device, scope: scope)
          }
        }
      )
    }

    /// The text of the progress.
    private var updatingLabel: String {
      OJDLocalized.string("ui.virtualProfile.updating")
    }

    /// The messages of the failed override and of the override store.
    private var problems: [String] {
      var messages = overrideState.failure.map { [$0] } ?? []
      if case .available(let status) = viewModel.statusState {
        messages += status.virtualHIDProfileOverrideStoreMessages
      }
      return messages
    }
  }

#endif
