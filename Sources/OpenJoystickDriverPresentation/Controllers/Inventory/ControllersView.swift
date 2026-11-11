#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Controllers

  /// The Controllers area of the main window: the list of connected controllers and the detail of
  /// the selected one.
  struct ControllersView: View {
    /// The state of the Controllers list.
    @ObservedObject
    private var screen: ControllersViewModel
    /// The column of the main window that the view fills.
    let column: MainWindowColumn
    /// Opens the Input Test window for a controller.
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
    /// The Bluetooth link closure that waits for confirmation, or nil.
    @State
    private var wirelessDisconnectRequest: WirelessDisconnectRequest?

    /// Creates the view.
    ///
    /// - Parameters:
    ///   - screen: The state of the Controllers list.
    ///   - column: The column of the main window that the view fills.
    ///   - openInputTest: Opens the Input Test window for a controller.
    init(
      screen: ControllersViewModel,
      column: MainWindowColumn,
      openInputTest: @escaping @MainActor (ApplicationServiceDeviceDescription) -> Void
    ) {
      self.screen = screen
      self.column = column
      self.openInputTest = openInputTest
    }

    /// The model of the app's view of the service.
    private var viewModel: RuntimeViewModel { screen.runtime }

    /// The controller list or the detail column.
    var body: some View {
      switch column {
      case .list: controllerList
      case .detail:
        controllerDetail.frame(maxWidth: .infinity, maxHeight: .infinity).onAppear {
          screen.refresh()
        }.onReceive(viewModel.$controllerInventoryGeneration) { _ in
          screen.synchronizeSelection()
        }
      }
    }

    /// The connected controllers.
    private var devices: [ApplicationServiceDeviceDescription] { screen.devices }

    /// The selected controller, or nil.
    private var selectedDevice: ApplicationServiceDeviceDescription? { screen.selectedDevice }

    /// The list column: the loading state, the failure with Try Again, or the rows.
    private var controllerList: some View {
      VStack(alignment: .leading, spacing: 8) {
        switch viewModel.statusState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string(
              "status.checkingControllers"
            )
          ).padding(.horizontal, 14)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.controllers.unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.controllers.loadError"
            ),
            message: message,
            retry: refresh
          ).padding(.horizontal, 14)
        case .available:
          if let liveStatusError = screen.liveStatusError {
            ServiceFailureStateView(
              title: OJDLocalized.string(
                "ui.controllers.loadError"
              ),
              message: liveStatusError,
              retry: refresh
            ).padding(.horizontal, 14)
          }
          if devices.isEmpty && screen.unservedDevices.isEmpty {
            EmptyView()
          } else {
            controllerListRows
          }
        }
        Spacer(minLength: 0)
      }
    }

    /// The rows of the connected controllers, then those of the controllers OJD does not serve.
    private var controllerListRows: some View {
      List(selection: selectedDeviceIdentifier) {
        ForEach(devices, id: \.sessionToken) { device in
          let presentation = device.publishedIdentityPresentation
          HStack(spacing: 8) {
            OJDListGlyphSlot {
              OJDSystemSymbol(
                name: presentation.controllerSymbolName,
                fallback: nil,
                fallbackSymbolName: presentation.controllerSymbolFallback
              ).foregroundColor(presentation.glyphFamily.controllerSymbolColor)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(device.name).lineLimit(1)
              Text(
                device.isHeldByAppleDriver
                  ? OJDLocalized.string("platform.macos.ui.controllers.servedByMacOS")
                  : device.protocolBinding.displayName
              ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if device.isHeldByAppleDriver { ControllerClaimButton(viewModel: viewModel) }
          }.padding(.vertical, 4).tag(device.sessionToken.rawValue).ojdAccessibilityLabel(
            device.name
          )
          .ojdAccessibilityValue(device.protocolBinding.displayName)
          .contextMenu { sessionCommands(for: device) }
        }
        ForEach(screen.unservedDevices) { unserved in
          VStack(alignment: .leading, spacing: 2) {
            Text("\(unserved.identity)  \(unserved.connection)").lineLimit(1)
            Text(unserved.explanation).font(.caption).foregroundColor(
              Color(NSColor.secondaryLabelColor)
            )
          }.padding(.vertical, 4).ojdAccessibilityLabel(unserved.identity)
            .ojdAccessibilityValue(unserved.explanation)
        }
      }.listStyle(InsetListStyle()).alert(item: $wirelessDisconnectRequest) { request in
        wirelessDisconnectAlert(for: request)
      }
    }

    /// The Controller menu's session commands for one controller.
    ///
    /// - Parameter device: The controller.
    /// - Returns: The buttons for the session state of the controller.
    @ViewBuilder
    private func sessionCommands(for device: ApplicationServiceDeviceDescription) -> some View {
      if device.sessionState == .suspended {
        Button(OJDLocalized.string("ui.menu.controller.resume")) {
          Task { @MainActor in await viewModel.resumeController(device) }
        }
      } else {
        Button(OJDLocalized.string("ui.menu.controller.suspend")) {
          Task { @MainActor in await viewModel.suspendController(device) }
        }
      }
      if device.supportsWirelessDisconnect {
        Button(OJDLocalized.string("ui.menu.controller.disconnectWirelessLink")) {
          wirelessDisconnectRequest = WirelessDisconnectRequest(device: device)
        }
      }
    }

    /// Returns the alert that confirms closing a controller's Bluetooth link.
    ///
    /// - Parameter request: The pending closure.
    /// - Returns: The alert that confirms closing a controller's Bluetooth link.
    private func wirelessDisconnectAlert(for request: WirelessDisconnectRequest) -> Alert {
      let confirmation = request.confirmation
      let device = request.device
      return Alert(
        title: Text(confirmation.title),
        message: Text(confirmation.message),
        primaryButton: .destructive(Text(confirmation.confirmTitle)) {
          Task { @MainActor in await viewModel.disconnectWirelessController(device) }
        },
        secondaryButton: .cancel()
      )
    }

    /// The binding between the list selection and the selected controller's session token.
    private var selectedDeviceIdentifier: Binding<String?> {
      Binding(
        get: { selectedDevice?.sessionToken.rawValue },
        set: { identifier in
          guard let identifier,
            let device = devices.first(where: { $0.sessionToken.rawValue == identifier })
          else { return }
          screen.select(device)
        }
      )
    }

    /// The detail of the selected controller, or the state of the load.
    @ViewBuilder
    private var controllerDetail: some View {
      if let selectedDevice {
        ControllerDetailView(
          device: selectedDevice,
          activeProfile: activeProfileState(for: selectedDevice),
          retry: refresh,
          viewModel: viewModel,
          openInputTest: openInputTest
        ).id(selectedDevice.sessionToken.rawValue)
      } else {
        switch viewModel.statusState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string(
              "status.checkingControllers"
            )
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.controllers.unavailable"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.controllers.loadError"
            ),
            message: message,
            retry: refresh
          ).padding(28)
        case .available:
          EmptyStateView(
            symbol: "gamecontroller",
            title: OJDLocalized.string(
              "ui.controllers.emptyTitle"
            ),
            message: OJDLocalized.string(
              "ui.controllers.emptyMessage"
            )
          )
        }
      }
    }

    /// Refreshes the controller inventory.
    private func refresh() { screen.refresh() }

    /// Returns the profile that is active for the controller, or why none shows.
    ///
    /// - Parameter device: The controller.
    /// - Returns: The profile that is active for the controller, or why none shows.
    private func activeProfileState(
      for device: ApplicationServiceDeviceDescription
    ) -> RuntimeActiveProfileState { screen.activeProfileState(for: device) }
  }

  extension VirtualIdentityGlyphFamily {
    /// The color of the controller's glyph: the Xbox brand green for the Xbox family, else the
    /// secondary label color.
    var controllerSymbolColor: Color {
      switch self {
      case .xbox: return Color(Self.xboxBrandColor)
      case .generic: return Color(NSColor.secondaryLabelColor)
      }
    }

    /// The Xbox brand green, lighter in the dark appearance.
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
  }

  extension ApplicationServiceDeviceDescription {
    /// The identity of the virtual HID profile this controller publishes; nil when none is live.
    var publishedVirtualProfile: VirtualDeviceProfile? {
      servingDecision.selection?.profileID.identity
    }

    /// The identity shown for this controller, computed once so icon and caption always agree.
    var presentedIdentity: PresentedControllerIdentity {
      guard publication?.state == .published, let identity = publishedVirtualProfile else {
        return PresentedControllerIdentity(
          publishesVirtualDevice: false,
          presentation: protocolBinding.protocolID.physicalPresentation,
          label: physicalOwnership.isServedBySystem
            ? OJDLocalized.string("platform.macos.ui.controllers.systemGamepadNotPublished")
            : RuntimePresentation.noVirtualHIDProfileLabel
        )
      }
      return PresentedControllerIdentity(
        publishesVirtualDevice: true,
        presentation: identity.presentation,
        label: identity.publishedUSBIdentityLabel
      )
    }

    /// The glyphs of the identity shown for this controller.
    var publishedIdentityPresentation: VirtualIdentityPresentation {
      presentedIdentity.presentation
    }

    /// The caption of the identity shown for this controller.
    var publishedIdentityLabel: String { presentedIdentity.label }

    /// The serving route of ``servingDecision``, the same route `ojd controller show` prints
    /// as `serving.route`.
    var servingRouteLabel: String {
      switch servingDecision.route {
      case .nativePassThrough:
        OJDLocalized.string("platform.macos.ui.controllers.serving.nativePassThrough")
      case .virtualHID: OJDLocalized.string("ui.controllers.serving.virtualHID")
      case .extensionOwned: OJDLocalized.string("ui.controllers.serving.extensionOwned")
      case .outputDisabled: OJDLocalized.string("ui.controllers.serving.outputDisabled")
      }
    }
  }

  /// Icon and caption of one controller: the virtual identity when OJD publishes a virtual
  /// device for it, else the physical family.
  struct PresentedControllerIdentity: Equatable {
    /// Whether OJD publishes a virtual device for the controller.
    let publishesVirtualDevice: Bool
    /// The glyphs of the identity.
    let presentation: VirtualIdentityPresentation
    /// The caption of the identity.
    let label: String
  }

#endif
