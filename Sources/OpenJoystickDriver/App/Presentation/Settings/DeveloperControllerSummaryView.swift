#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperControllerSummaryView: View {
    @ObservedObject var model: DeveloperToolsViewModel

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            Picker(
              OJDLocalized.string("developer.controller", fallback: "Controller"),
              selection: Binding(
                get: { model.selectedDevice?.runtimeIdentifier ?? "" },
                set: { model.selectDevice(runtimeIdentifier: $0) }
              )
            ) {
              ForEach(model.devices, id: \.runtimeIdentifier) { device in
                Text(device.name).tag(device.runtimeIdentifier)
              }
            }.labelsHidden().frame(maxWidth: 360)
            Spacer()
            Button(
              OJDLocalized.string("common.refresh", fallback: "Refresh"),
              action: model.requestRefresh
            ).disabled(model.isCapturing)
          }

          if let device = model.selectedDevice {
            Divider()
            HStack(alignment: .top, spacing: 24) {
              identityColumn(device)
              transportColumn(device)
              inputColumn
            }
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("developer.controllerDetails", fallback: "Controller")).font(
          .headline
        )
      }
    }

    private func identityColumn(_ device: ApplicationServiceDeviceDescription) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        DeveloperValueRow(
          label: "USB ID",
          value: String(format: "%04X:%04X", device.vendorID, device.productID)
        )
        DeveloperValueRow(label: "Parser", value: device.parser)
        DeveloperValueRow(label: "Protocol", value: protocolName(device.protocolVariant))
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transportColumn(_ device: ApplicationServiceDeviceDescription) -> some View {
      VStack(alignment: .leading, spacing: 6) {
        DeveloperValueRow(label: "Route", value: routeName(device.discoverySource))
        DeveloperValueRow(label: "Connection", value: device.connection)
        DeveloperValueRow(
          label: "USB endpoints",
          value: String(
            format: "Input 0x%02X · Output 0x%02X",
            device.inputEndpoint,
            device.outputEndpoint
          )
        )
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputColumn: some View {
      VStack(alignment: .leading, spacing: 6) {
        DeveloperValueRow(label: "Buttons", value: buttonValue(model.latestInput?.pressedButtons))
        DeveloperValueRow(
          label: "Left stick",
          value: stickValue(x: model.latestInput?.leftStickX, y: model.latestInput?.leftStickY)
        )
        DeveloperValueRow(
          label: "Right stick",
          value: stickValue(x: model.latestInput?.rightStickX, y: model.latestInput?.rightStickY)
        )
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stickValue(x: Float?, y: Float?) -> String {
      String(format: "%.3f, %.3f", x ?? 0, y ?? 0)
    }

    private func buttonValue(_ buttons: [String]?) -> String {
      guard let buttons, !buttons.isEmpty else { return "None" }
      return buttons.sorted().joined(separator: ", ")
    }

    private func protocolName(_ value: ControllerProtocolVariant) -> String {
      switch value {
      case .xboxOriginal: return "Original Xbox"
      case .xbox360: return "Xbox 360"
      case .xbox360Wireless: return "Xbox 360 Wireless"
      case .xboxOne: return "Xbox One"
      case .dualShock3: return "DualShock 3"
      case .dualShock4: return "DualShock 4"
      case .dualSense: return "DualSense"
      case .steamController: return "Steam Controller"
      case .switchPro: return "Switch Pro Controller"
      case .xboxAdaptiveJoystick: return "Xbox Adaptive Joystick"
      case .genericHID: return "Standard HID"
      case .unknown: return "Unknown"
      }
    }

    private func routeName(_ value: ApplicationServiceDeviceDiscoverySource) -> String {
      switch value {
      case .hid: return "HID"
      case .rawUSB: return "Raw USB"
      case .unknown: return "Unknown"
      }
    }
  }

  private struct DeveloperValueRow: View {
    let label: String
    let value: String

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        Text(value).font(.system(.body, design: .monospaced)).lineLimit(2)
          .textSelectionIfAvailable()
      }.accessibilityElement(children: .combine)
    }
  }

#endif
