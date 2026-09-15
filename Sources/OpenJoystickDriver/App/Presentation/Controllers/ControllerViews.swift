#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Controllers

  struct ControllersView: View {
    @ObservedObject
    private var screen: ControllersViewModel
    @State
    private var isRefreshing = false
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void

    init(
      screen: ControllersViewModel,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void
    ) {
      self.screen = screen
      self.openInputTest = openInputTest
    }

    private var viewModel: RuntimeViewModel { screen.runtime }

    var body: some View {
      GeometryReader { proxy in
        if WorkspaceListDetailPolicy.layout(for: proxy.size.width) == .stacked {
          VStack(spacing: 0) {
            controllerList.frame(height: min(200, proxy.size.height * 0.34))
            Divider()
            controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        } else {
          HStack(spacing: 0) {
            controllerList.frame(width: WorkspaceListDetailPolicy.listWidth(for: proxy.size.width))
              .frame(maxHeight: .infinity, alignment: .topLeading)
            Divider()
            controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }.onAppear { screen.refresh() }.onReceive(viewModel.$controllerInventoryGeneration) { _ in
        screen.synchronizeSelection()
      }.onReceive(viewModel.scopedRefreshInFlightPublisher.removeDuplicates()) { isRefreshing in
        self.isRefreshing = isRefreshing
      }
    }

    private var devices: [ApplicationServiceDeviceDescription] { screen.devices }

    private var selectedDevice: ApplicationServiceDeviceDescription? { screen.selectedDevice }

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
          OJDCompactSymbolButton(
            symbolName: "arrow.clockwise",
            label: OJDLocalized.string(
              "controllers.refreshAccessibility",
              fallback: "Refresh controllers"
            ),
            action: refresh
          ).disabled(isRefreshing)
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
      List(selection: selectedDeviceIdentifier) {
        ForEach(devices, id: \.runtimeIdentifier) { device in
          let published = PublishedVirtualIdentity.profile(
            for: device,
            requested: viewModel.requestedCompatibilityIdentity
          )
          HStack(spacing: 8) {
            OJDListGlyphSlot {
              OJDSystemSymbol(
                name: published.presentation.controllerSymbolName,
                fallback: OJDLocalized.string("common.controller", fallback: "Controller"),
                fallbackSymbolName: published.presentation.controllerSymbolFallback
              ).foregroundColor(published.presentation.glyphFamily.controllerSymbolColor)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(device.name).lineLimit(1)
              Text(published.publishedUSBIdentityLabel).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              ).lineLimit(1)
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(device.runtimeIdentifier).ojdAccessibilityLabel(device.name)
            .ojdAccessibilityValue(
              "\(published.publishedUSBIdentityLabel). \(device.protocolVariant.displayLabel)"
            )
        }
      }.listStyle(SidebarListStyle())
    }

    private var selectedDeviceIdentifier: Binding<String?> {
      Binding(
        get: { selectedDevice?.runtimeIdentifier },
        set: { identifier in
          guard let identifier,
            let device = devices.first(where: { $0.runtimeIdentifier == identifier })
          else { return }
          screen.select(device)
        }
      )
    }

    @ViewBuilder
    private var controllerDetail: some View {
      if let selectedDevice {
        ControllerDetailView(
          device: selectedDevice,
          activeProfile: activeProfileState(for: selectedDevice),
          retry: refresh,
          viewModel: viewModel,
          openInputTest: openInputTest
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

    private func refresh() { screen.refresh() }

    private func activeProfileState(
      for device: ApplicationServiceDeviceDescription
    ) -> RuntimeActiveProfileState { screen.activeProfileState(for: device) }
  }

  extension VirtualIdentityGlyphFamily {
    var controllerSymbolColor: Color {
      switch self {
      case .xbox: return Color(Self.xboxBrandColor)
      case .playstation: return Color(Self.playStationBrandColor)
      case .nintendo, .steam, .generic: return Color(NSColor.secondaryLabelColor)
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
  }

  extension ControllerProtocolVariant {
    var displayLabel: String {
      switch self {
      case .xid: return OJDLocalized.string("controller.xboxOriginal", fallback: "Xbox (original)")
      case .xbox360: return OJDLocalized.string("controller.xbox360", fallback: "Xbox 360")
      case .xbox360Wireless:
        return OJDLocalized.string("controller.xbox360Wireless", fallback: "Xbox 360 wireless")
      case .xboxOne: return OJDLocalized.string("controller.xboxOne", fallback: "Xbox One")
      case .xboxBluetoothHID:
        return OJDLocalized.string("controller.xboxBluetoothHID", fallback: "Xbox (Bluetooth)")
      case .dualShock3: return OJDLocalized.string("controller.dualShock3", fallback: "DualShock 3")
      case .dualShock4: return OJDLocalized.string("controller.dualShock4", fallback: "DualShock 4")
      case .dualSense: return OJDLocalized.string("controller.dualSense", fallback: "DualSense")
      case .steamController:
        return OJDLocalized.string("controller.steamController", fallback: "Steam Controller")
      case .switchPro: return OJDLocalized.string("controller.switchPro", fallback: "Switch Pro")
      case .flydigi: return OJDLocalized.string("controller.flydigi", fallback: "Flydigi")
      case .flydigiVendor:
        return OJDLocalized.string("controller.flydigiVendor", fallback: "Flydigi (dongle)")
      case .gameSirG7ProUSB: return "GameSir G7 Pro USB"
      case .gameSirEnhancedHID: return "GameSir enhanced HID"
      case .xboxAdaptiveJoystick:
        return OJDLocalized.string(
          "controller.xboxAdaptiveJoystick",
          fallback: "Xbox Adaptive Joystick"
        )
      case .genericHID: return OJDLocalized.string("controller.genericHID", fallback: "Generic HID")
      case .unknown: return OJDLocalized.string("common.unknown", fallback: "Unknown")
      }
    }
  }

#endif
