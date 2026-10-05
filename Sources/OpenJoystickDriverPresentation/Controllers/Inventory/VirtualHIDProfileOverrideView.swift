#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Advanced override of one controller model's virtual HID profile, matching
  /// `ojd virtual set|reset`: Automatic clears the override.
  struct VirtualHIDProfileOverrideView: View {
    @ObservedObject
    var viewModel: RuntimeViewModel
    let device: ApplicationServiceDeviceDescription

    var body: some View {
      DisclosureGroup(advancedTitle) { content.padding(.top, 8) }
    }

    private var advancedTitle: String {
      OJDLocalized.string("virtualProfile.advanced")
    }

    private var content: some View {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          OJDLocalized.string("virtualProfile.title"),
          selection: overrideBinding
        ) {
          Text(OJDLocalized.string("mapping.automatic")).tag(
            VirtualHIDProfileID?.none
          )
          ForEach(VirtualHIDProfileID.allCases, id: \.self) { profile in
            Text("\(profile.identity.productName) (\(profile.rawValue))").tag(
              VirtualHIDProfileID?.some(profile)
            )
          }
        }.disabled(overrideState.inFlight)
        Text(
          OJDLocalized.string(
            "virtualProfile.modelScope"
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        KeyValueRow(
          label: OJDLocalized.string("virtualProfile.live"),
          value: liveProfileLabel
        )
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
              fallback: OJDLocalized.string("common.needsAttention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }.ojdAccessibilityLabel(
            OJDLocalized.string("common.needsAttention")
          ).ojdAccessibilityValue(message)
        }
      }
    }

    /// Shared by every connected controller of this model, like the override itself.
    private var overrideState: RuntimeVirtualHIDProfileOverrideState {
      viewModel.virtualHIDProfileOverrideStates[RuntimeControllerModel(device)]
        ?? RuntimeVirtualHIDProfileOverrideState()
    }

    private var overrideBinding: Binding<VirtualHIDProfileID?> {
      Binding(
        get: {
          // Show the pending choice until the refreshed status reports the stored override.
          if let request = overrideState.request { return request.requested }
          return device.virtualHIDProfile?.override
        },
        set: { profile in
          guard profile != device.virtualHIDProfile?.override else { return }
          let device = device
          Task { @MainActor in await viewModel.setVirtualHIDProfileOverride(profile, for: device) }
        }
      )
    }

    private var liveProfileLabel: String {
      guard let status = device.virtualHIDProfile else {
        return RuntimePresentation.noVirtualHIDProfileLabel
      }
      if status.unavailable {
        return OJDLocalized.string(
          "virtualProfile.unavailable"
        )
      }
      guard let profile = status.profile else {
        return RuntimePresentation.noVirtualHIDProfileLabel
      }
      let source = status.source.map(RuntimePresentation.virtualHIDProfileSourceLabel)
      return [profile.identity.publishedUSBIdentityLabel, source].compactMap { $0 }.joined(
        separator: " · "
      )
    }

    private var updatingLabel: String {
      OJDLocalized.string("virtualProfile.updating")
    }

    private var problems: [String] {
      var messages = overrideState.failure.map { [$0] } ?? []
      if case .available(let status) = viewModel.statusState {
        messages += status.virtualHIDProfileOverrideStoreMessages
      }
      return messages
    }
  }

#endif
