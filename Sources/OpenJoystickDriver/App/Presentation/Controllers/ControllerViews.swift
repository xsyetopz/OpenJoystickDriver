#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Controllers

  struct ControllersView: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @State private var selectedRuntimeIdentifier: String?

    var body: some View {
      GeometryReader { proxy in
        HStack(spacing: 0) {
          controllerList.frame(width: controllerListWidth(for: proxy.size.width)).frame(
            maxHeight: .infinity,
            alignment: .topLeading
          )
          Divider()
          controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }.onAppear { selectFirstControllerIfNeeded() }.onReceive(viewModel.$statusState) { state in
        guard case .available(let status) = state else { return }
        if let selectedRuntimeIdentifier,
          status.devices.contains(where: { $0.runtimeIdentifier == selectedRuntimeIdentifier })
        {
          return
        }
        self.selectedRuntimeIdentifier = status.devices.first?.runtimeIdentifier
      }
    }

    private var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }

    private var selectedDevice: ApplicationServiceDeviceDescription? {
      if let selectedRuntimeIdentifier,
        let selected = devices.first(where: { $0.runtimeIdentifier == selectedRuntimeIdentifier })
      {
        return selected
      }
      return devices.first
    }

    private func controllerListWidth(for availableWidth: CGFloat) -> CGFloat {
      min(220, max(168, availableWidth * 0.25))
    }

    private func reportedValue(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported", fallback: "Not reported") : trimmed
    }

    private var controllerList: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(OJDLocalized.string("common.controllers", fallback: "Controllers")).font(.headline)
          Spacer()
          Button(action: refresh) {
            OJDSystemSymbol(
              name: "arrow.clockwise",
              fallback: OJDLocalized.string("common.refresh", fallback: "Refresh")
            )
          }.buttonStyle(.plain).ojdAccessibilityLabel(
            OJDLocalized.string("controllers.refreshAccessibility", fallback: "Refresh controllers")
          )
        }.padding(.horizontal, 14).padding(.top, 18)

        switch viewModel.statusState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string(
              "status.checkingControllers",
              fallback: "Checking connected controllers..."
            )
          ).padding(.horizontal, 14)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.unavailable",
              fallback: "Controllers unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.loadError",
              fallback: "Could not load controllers"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .available: if devices.isEmpty { EmptyView() } else { controllerListRows }
        }
        Spacer(minLength: 0)
      }.background(Color(NSColor.controlBackgroundColor))
    }

    private var controllerListRows: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(devices, id: \.runtimeIdentifier) { device in
            Button(
              action: { selectedRuntimeIdentifier = device.runtimeIdentifier },
              label: {
                HStack(spacing: 8) {
                  OJDSystemSymbol(
                    name: device.protocolVariant.controllerSymbolName,
                    fallback: OJDLocalized.string("common.controller", fallback: "Controller"),
                    fallbackSymbolName: "gamecontroller"
                  ).foregroundColor(device.protocolVariant.controllerSymbolColor)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).lineLimit(1)
                    Text(reportedValue(device.connection)).font(.caption).foregroundColor(
                      Color(NSColor.secondaryLabelColor)
                    ).lineLimit(1)
                  }
                  Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
              }
            ).buttonStyle(
              ProfileListButtonStyle(
                selected: selectedDevice?.runtimeIdentifier == device.runtimeIdentifier
              )
            ).ojdAccessibilityLabel(device.name).ojdAccessibilityValue(
              "\(reportedValue(device.connection)). \(device.protocolVariant.displayLabel)"
            ).ojdAccessibilitySelection(
              selectedDevice?.runtimeIdentifier == device.runtimeIdentifier
            )
          }
        }.padding(.horizontal, 8)
      }
    }

    @ViewBuilder private var controllerDetail: some View {
      if let selectedDevice {
        ControllerDetailView(
          device: selectedDevice,
          activeProfile: activeProfileState(for: selectedDevice),
          retry: refresh,
          viewModel: viewModel
        )
      } else {
        switch viewModel.statusState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string(
              "status.checkingControllers",
              fallback: "Checking connected controllers..."
            )
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.unavailable",
              fallback: "Controllers unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "controllers.loadError",
              fallback: "Could not load controllers"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .available:
          EmptyStateView(
            symbol: "gamecontroller",
            title: OJDLocalized.string(
              "controllers.emptyTitle",
              fallback: "No controller connected"
            ),
            message: OJDLocalized.string(
              "controllers.emptyMessage",
              fallback: "Connect a controller, then choose Refresh."
            )
          ).padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }

    private func selectFirstControllerIfNeeded() {
      guard selectedRuntimeIdentifier == nil else { return }
      selectedRuntimeIdentifier = devices.first?.runtimeIdentifier
    }

    private func refresh() { Task { @MainActor in await viewModel.refresh() } }

    private func activeProfileState(for device: ApplicationServiceDeviceDescription)
      -> RuntimeActiveProfileState
    {
      switch viewModel.remappingState {
      case .loading: return .loading
      case .unavailable(let message): return .unavailable(message)
      case .error(let message): return .error(message)
      case .available(let snapshot):
        guard
          let activeProfile = snapshot.activeProfiles.first(where: {
            $0.vendorID == device.vendorID && $0.productID == device.productID
          })
        else { return .noProfile }
        return .profile(activeProfile.profileName)
      }
    }
  }

  private struct ControllerDetailView: View {
    let device: ApplicationServiceDeviceDescription
    let activeProfile: RuntimeActiveProfileState
    let retry: () -> Void
    @ObservedObject var viewModel: RuntimeViewModel

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          controllerHeader
          activeProfileRow
          Divider()
          controllerDetails
          Divider()
          ControllerIdentityView(viewModel: viewModel)
        }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
      }.ojdAccessibilityLabel(device.name).ojdAccessibilityValue(accessibilityValue)
    }

    private var controllerHeader: some View {
      HStack(alignment: .center, spacing: 10) {
        OJDSystemSymbol(
          name: device.protocolVariant.controllerSymbolName,
          fallback: OJDLocalized.string("common.controller", fallback: "Controller"),
          fallbackSymbolName: "gamecontroller"
        ).font(.title).foregroundColor(device.protocolVariant.controllerSymbolColor)
          .ojdAccessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(device.name).font(.headline.weight(.semibold)).lineLimit(1)
          Text(reportedValue(device.connection)).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer(minLength: 0)
      }
    }

    @ViewBuilder private var activeProfileRow: some View {
      switch activeProfile {
      case .loading:
        KeyValueRow(
          label: OJDLocalized.string("controllers.activeProfile", fallback: "Active profile"),
          value: OJDLocalized.string("status.checking", fallback: "Checking...")
        )
      case .noProfile:
        KeyValueRow(
          label: OJDLocalized.string("controllers.activeProfile", fallback: "Active profile"),
          value: OJDLocalized.string("common.none", fallback: "None")
        )
      case .profile(let name):
        KeyValueRow(
          label: OJDLocalized.string("controllers.activeProfile", fallback: "Active profile"),
          value: name
        )
      case .unavailable(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "controllers.profileUnavailable",
            fallback: "Active profile unavailable"
          ),
          message: message
        )
      case .error(let message):
        profileFailureRow(
          label: OJDLocalized.string(
            "controllers.profileLoadError",
            fallback: "Active profile could not be loaded"
          ),
          message: message
        )
      }
    }

    private func profileFailureRow(label: String, message: String) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(OJDLocalized.string("controllers.activeProfile", fallback: "Active profile"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          Spacer()
          Text(OJDLocalized.string("common.needsAttention", fallback: "Needs attention"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Text(label).font(.caption.weight(.semibold))
        Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        Button(OJDLocalized.string("common.tryAgain", fallback: "Try again"), action: retry)
      }
    }

    private var controllerDetails: some View {
      VStack(alignment: .leading, spacing: 6) {
        KeyValueRow(
          label: OJDLocalized.string("common.protocol", fallback: "Protocol"),
          value: device.protocolVariant.displayLabel
        )
        KeyValueRow(
          label: OJDLocalized.string("common.parser", fallback: "Parser"),
          value: reportedValue(device.parser)
        )
        KeyValueRow(
          label: OJDLocalized.string("common.serialNumber", fallback: "Serial number"),
          value: serialNumberLabel
        )
        KeyValueRow(
          label: OJDLocalized.string("controllers.usbIdentifier", fallback: "USB VID/PID"),
          value: usbIdentifier
        )
        KeyValueRow(
          label: OJDLocalized.string("common.inputEndpoint", fallback: "Input endpoint"),
          value: endpointLabel(device.inputEndpoint)
        )
        KeyValueRow(
          label: OJDLocalized.string("common.outputEndpoint", fallback: "Output endpoint"),
          value: endpointLabel(device.outputEndpoint)
        )
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serialNumberLabel: String {
      guard let serialNumber = device.serialNumber else {
        return OJDLocalized.string("controllers.notReported", fallback: "Not reported")
      }
      return reportedValue(serialNumber)
    }

    private var usbIdentifier: String {
      guard device.vendorID != 0 || device.productID != 0 else {
        return OJDLocalized.string("controllers.notReported", fallback: "Not reported")
      }
      return String(format: "%04X:%04X", device.vendorID, device.productID)
    }

    private func reportedValue(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported", fallback: "Not reported") : trimmed
    }

    private func endpointLabel(_ endpoint: UInt8) -> String {
      endpoint == 0
        ? OJDLocalized.string("controllers.notReported", fallback: "Not reported")
        : String(format: "0x%02X", endpoint)
    }

    private var accessibilityValue: String {
      OJDLocalized.formatted(
        "controllers.accessibilityDetails",
        fallback: "%@. %@. Protocol: %@. Parser: %@. Serial number: %@. "
          + "USB VID/PID: %@. Input endpoint: %@. Output endpoint: %@.",
        reportedValue(device.connection),
        profileAccessibilityValue,
        device.protocolVariant.displayLabel,
        reportedValue(device.parser),
        serialNumberLabel,
        usbIdentifier,
        endpointLabel(device.inputEndpoint),
        endpointLabel(device.outputEndpoint)
      )
    }

    private var profileAccessibilityValue: String {
      switch activeProfile {
      case .loading:
        return OJDLocalized.string(
          "controllers.profileCheckingSentence",
          fallback: "Active profile is being checked."
        )
      case .noProfile:
        return OJDLocalized.string(
          "controllers.noActiveProfileSentence",
          fallback: "No active profile."
        )
      case .profile(let name):
        return OJDLocalized.formatted(
          "controllers.activeProfileSentence",
          fallback: "Active profile: %@.",
          name
        )
      case .unavailable(let message):
        return OJDLocalized.formatted(
          "controllers.profileUnavailableSentence",
          fallback: "Active profile unavailable: %@",
          message
        )
      case .error(let message):
        return OJDLocalized.formatted(
          "controllers.profileErrorSentence",
          fallback: "Active profile error: %@",
          message
        )
      }
    }
  }

  extension ControllerProtocolVariant {
    var controllerSymbolName: String {
      switch self {
      case .xboxOriginal, .xbox360, .xbox360Wireless, .xboxOne, .xboxAdaptiveJoystick:
        return "xbox.logo"
      case .dualShock3, .dualShock4, .dualSense: return "playstation.logo"
      case .steamController, .switchPro, .genericHID, .unknown: return "gamecontroller"
      }
    }

    var controllerSymbolColor: Color {
      switch self {
      case .xboxOriginal, .xbox360, .xbox360Wireless, .xboxOne, .xboxAdaptiveJoystick:
        return Color(Self.xboxBrandColor)
      case .dualShock3, .dualShock4, .dualSense: return Color(Self.playStationBrandColor)
      case .steamController, .switchPro, .genericHID, .unknown:
        return Color(NSColor.secondaryLabelColor)
      }
    }

    private static let xboxBrandColor = NSColor(name: nil) { appearance in
      let isDark =
        appearance.bestMatch(from: [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua])
        == .darkAqua
      return NSColor(
        srgbRed: (isDark ? 155.0 : 16.0) / 255.0,
        green: (isDark ? 240.0 : 124.0) / 255.0,
        blue: (isDark ? 11.0 : 16.0) / 255.0,
        alpha: 1
      )
    }

    private static let playStationBrandColor = NSColor(name: nil) { appearance in
      let isDark =
        appearance.bestMatch(from: [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua])
        == .darkAqua
      return NSColor(
        srgbRed: 0,
        green: (isDark ? 112.0 : 55.0) / 255.0,
        blue: (isDark ? 204.0 : 145.0) / 255.0,
        alpha: 1
      )
    }

    var displayLabel: String {
      switch self {
      case .xboxOriginal: return "Xbox (original)"
      case .xbox360: return "Xbox 360"
      case .xbox360Wireless: return "Xbox 360 wireless"
      case .xboxOne: return "Xbox One"
      case .dualShock3: return "DualShock 3"
      case .dualShock4: return "DualShock 4"
      case .dualSense: return "DualSense"
      case .steamController: return "Steam Controller"
      case .switchPro: return "Switch Pro"
      case .xboxAdaptiveJoystick: return "Xbox Adaptive Joystick"
      case .genericHID: return "Generic HID"
      case .unknown: return "Unknown"
      }
    }
  }

#endif
