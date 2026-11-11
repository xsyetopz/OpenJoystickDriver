#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Controller section of the developer tools: a picker of the connected controllers, Refresh
  /// and the facts of the selected controller.
  struct DeveloperControllerSummaryView: View {
    /// The state of the developer tools.
    @ObservedObject
    var model: DeveloperToolsViewModel
    /// The Controller details section: the controller picker, the facts of the selected controller
    /// and Refresh.
    var body: some View {
      Section(OJDLocalized.string("ui.developer.controllerDetails")) {
        Picker(
          OJDLocalized.string("ui.developer.controller"),
          selection: Binding(
            get: { model.selectedDevice?.sessionToken.rawValue ?? "" },
            set: { model.selectDevice(sessionToken: $0) }
          )
        ) {
          ForEach(model.devices, id: \.sessionToken) { device in
            Text(device.name).tag(device.sessionToken.rawValue)
          }
        }
        if let device = model.selectedDevice { controllerFacts(device) }
        Button(OJDLocalized.string("action.refresh"), action: model.requestRefresh)
          .disabled(model.isCapturing)
      }
    }

    /// Returns the rows that describe `device` and its latest input.
    @ViewBuilder
    private func controllerFacts(_ device: ApplicationServiceDeviceDescription) -> some View {
      OJDLabeledValue(
        OJDLocalized.string("ui.developer.usbID"),
        OJDValue.usbIdentifier(vendorID: device.vendorID, productID: device.productID)
      )
      OJDLabeledValue(
        OJDLocalized.string("term.protocol"),
        "\(device.protocolBinding.protocolID.displayName) "
          + "(\(device.protocolBinding.commandLineName))"
      )
      DeveloperSerialRow(serial: OJDValue.reported(device.serialNumber)).id(
        device.sessionToken.rawValue
      )
      OJDLabeledValue(OJDLocalized.string("ui.developer.route"), routeName(device.discoverySource))
      OJDLabeledValue(OJDLocalized.string("ui.developer.connection"), device.connection)
      OJDLabeledValue(
        OJDLocalized.string("ui.developer.usbEndpoints"),
        String(
          format: "%@ 0x%02X · %@ 0x%02X",
          OJDLocalized.string("term.inputEndpoint"),
          device.inputEndpoint,
          OJDLocalized.string("term.outputEndpoint"),
          device.outputEndpoint
        )
      )
      OJDLabeledValue(
        OJDLocalized.string("ui.developer.buttons"),
        buttonValue(model.latestInput?.pressed)
      )
      OJDLabeledValue(
        OJDLocalized.string("ui.developer.leftStick"),
        stickValue(model.latestInput?.leftStick)
      )
      OJDLabeledValue(
        OJDLocalized.string("ui.developer.rightStick"),
        stickValue(model.latestInput?.rightStick)
      )
    }

    /// Returns the raw x and y values of the stick, or the centered position for nil; y points
    /// down.
    private func stickValue(_ stick: StickPosition?) -> String {
      let stick = stick ?? .center
      return "\(stick.x.rawValue), \(stick.y.rawValue)"
    }

    /// Returns the names of the pressed controls, or None when nothing is pressed.
    private func buttonValue(_ pressed: Set<Control>?) -> String {
      guard let pressed, !pressed.isEmpty else {
        return OJDLocalized.string("status.none")
      }
      return Control.allCases.filter(pressed.contains).map(\.rawValue).joined(separator: ", ")
    }

    /// Returns the name of the route the controller is discovered on.
    private func routeName(_ value: DeviceDiscoverySource) -> String {
      switch value {
      case .hid: return OJDLocalized.string("ui.developer.hid")
      case .rawUSB: return OJDLocalized.string("ui.developer.rawUSB")
      }
    }
  }

  /// The serial number row; it is blurred until revealed, and starts blurred for each controller.
  private struct DeveloperSerialRow: View {
    /// The serial number to show.
    let serial: OJDValue
    /// Whether the serial number is blurred or revealed.
    @State
    private var visibility = SerialNumberVisibility()

    /// The Serial number row with the visibility of the serial number.
    var body: some View {
      SerialNumberRow(
        label: OJDLocalized.string("term.serialNumber"),
        serial: serial,
        visibility: $visibility
      )
    }
  }

#endif
