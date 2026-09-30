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
      if #available(macOS 11.0, *) {
        DisclosureGroup(advancedTitle) { content.padding(.top, 8) }
      } else {
        alwaysExpanded
      }
    }

    private var alwaysExpanded: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(advancedTitle).font(.headline)
        content
      }
    }

    private var advancedTitle: String {
      OJDLocalized.string("virtualProfile.advanced", fallback: "Advanced")
    }

    private var content: some View {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          OJDLocalized.string("virtualProfile.title", fallback: "Virtual HID profile"),
          selection: overrideBinding
        ) {
          Text(OJDLocalized.string("mapping.automatic", fallback: "Automatic")).tag(
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
            "virtualProfile.modelScope",
            fallback: "Applies to every connected controller of this model."
          )
        ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        KeyValueRow(
          label: OJDLocalized.string("virtualProfile.live", fallback: "Live profile"),
          value: liveProfileLabel
        )
        if overrideState.inFlight {
          HStack(spacing: 8) {
            OJDLoadingIndicator()
            Text(updatingLabel).foregroundColor(Color(NSColor.secondaryLabelColor))
          }.ojdAccessibilityLabel(updatingLabel)
        }
        ForEach(problems, id: \.self) { message in
          HStack(alignment: .top, spacing: 8) {
            OJDSystemSymbol(
              name: SemanticState.failure.presentation.symbolName,
              fallback: OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
          }.ojdAccessibilityLabel(
            OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
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
          "virtualProfile.unavailable",
          fallback: "No virtual HID profile can represent this controller."
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
      OJDLocalized.string("virtualProfile.updating", fallback: "Updating virtual HID profile...")
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
