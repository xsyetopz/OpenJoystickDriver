#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct DeveloperControllerSummaryView: View {
    @ObservedObject
    var model: DeveloperToolsViewModel
    let compact: Bool

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
            controllerFacts(device)
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("developer.controllerDetails", fallback: "Controller")).font(
          .headline
        )
      }
    }

    private func controllerFacts(_ device: ApplicationServiceDeviceDescription) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        factRow(
          DeveloperValueRow(
            label: OJDLocalized.string("developer.usbID", fallback: "USB ID"),
            value: String(format: "%04X:%04X", device.vendorID, device.productID)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("common.parser", fallback: "Parser"),
            value: device.parser
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("common.protocol", fallback: "Protocol"),
            value: protocolName(device.protocolVariant)
          )
        )
        factRow(
          DeveloperValueRow(
            label: OJDLocalized.string("developer.route", fallback: "Route"),
            value: routeName(device.discoverySource)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.connection", fallback: "Connection"),
            value: device.connection
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.usbEndpoints", fallback: "USB endpoints"),
            value: String(
              format: "Input 0x%02X · Output 0x%02X",
              device.inputEndpoint,
              device.outputEndpoint
            )
          )
        )
        factRow(
          DeveloperValueRow(
            label: OJDLocalized.string("developer.buttons", fallback: "Buttons"),
            value: buttonValue(model.latestInput?.pressedButtons)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.leftStick", fallback: "Left stick"),
            value: stickValue(x: model.latestInput?.leftStickX, y: model.latestInput?.leftStickY)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.rightStick", fallback: "Right stick"),
            value: stickValue(x: model.latestInput?.rightStickX, y: model.latestInput?.rightStickY)
          )
        )
      }
    }

    private func factRow<First: View, Second: View, Third: View>(
      _ first: First,
      _ second: Second,
      _ third: Third
    ) -> some View {
      HStack(alignment: .top, spacing: compact ? 10 : 24) {
        first.frame(maxWidth: .infinity, alignment: .leading)
        second.frame(maxWidth: .infinity, alignment: .leading)
        third.frame(maxWidth: .infinity, alignment: .leading)
      }
    }

    private func stickValue(x: Float?, y: Float?) -> String {
      String(format: "%.3f, %.3f", x ?? 0, y ?? 0)
    }

    private func buttonValue(_ buttons: [String]?) -> String {
      guard let buttons, !buttons.isEmpty else {
        return OJDLocalized.string("common.none", fallback: "None")
      }
      return buttons.sorted().joined(separator: ", ")
    }

    private func protocolName(_ value: ControllerProtocolVariant) -> String {
      switch value {
      case .xid: return OJDLocalized.string("controller.originalXbox", fallback: "Original Xbox")
      case .xbox360: return OJDLocalized.string("controller.xbox360", fallback: "Xbox 360")
      case .xbox360Wireless:
        return OJDLocalized.string(
          "controller.xbox360WirelessDeveloper",
          fallback: "Xbox 360 Wireless"
        )
      case .xboxOne: return OJDLocalized.string("controller.xboxOne", fallback: "Xbox One")
      case .xboxBluetoothHID:
        return OJDLocalized.string("controller.xboxBluetoothHID", fallback: "Xbox (Bluetooth)")
      case .dualShock3: return OJDLocalized.string("controller.dualShock3", fallback: "DualShock 3")
      case .dualShock4: return OJDLocalized.string("controller.dualShock4", fallback: "DualShock 4")
      case .dualSense: return OJDLocalized.string("controller.dualSense", fallback: "DualSense")
      case .steamController:
        return OJDLocalized.string("controller.steamController", fallback: "Steam Controller")
      case .flydigi: return OJDLocalized.string("controller.flydigi", fallback: "Flydigi")
      case .flydigiVendor:
        return OJDLocalized.string("controller.flydigiVendor", fallback: "Flydigi (dongle)")
      case .gameSirG7ProUSB: return "GameSir G7 Pro USB"
      case .gameSirEnhancedHID: return "GameSir enhanced HID"
      case .switchPro:
        return OJDLocalized.string(
          "controller.switchProController",
          fallback: "Switch Pro Controller"
        )
      case .xboxAdaptiveJoystick:
        return OJDLocalized.string(
          "controller.xboxAdaptiveJoystick",
          fallback: "Xbox Adaptive Joystick"
        )
      case .genericHID:
        return OJDLocalized.string("controller.standardHID", fallback: "Standard HID")
      case .unknown: return OJDLocalized.string("common.unknown", fallback: "Unknown")
      }
    }

    private func routeName(_ value: ApplicationServiceDeviceDiscoverySource) -> String {
      switch value {
      case .hid: return OJDLocalized.string("developer.hid", fallback: "HID")
      case .rawUSB: return OJDLocalized.string("developer.rawUSB", fallback: "Raw USB")
      case .unknown: return OJDLocalized.string("common.unknown", fallback: "Unknown")
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
