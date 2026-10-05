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
              OJDLocalized.string("developer.controller"),
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
              OJDLocalized.string("common.refresh"),
              action: model.requestRefresh
            ).disabled(model.isCapturing)
          }

          if let device = model.selectedDevice {
            Divider()
            controllerFacts(device)
          }
        }.padding(4)
      } label: {
        Text(OJDLocalized.string("developer.controllerDetails")).font(
          .headline
        )
      }
    }

    private func controllerFacts(_ device: ApplicationServiceDeviceDescription) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        factRow(
          DeveloperValueRow(
            label: OJDLocalized.string("developer.usbID"),
            value: String(format: "%04X:%04X", device.vendorID, device.productID)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("common.protocol"),
            value: "\(protocolName(device.protocolBinding)) (\(device.protocolBinding))"
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("common.serialNumber"),
            value: device.serialNumber ?? "—"
          )
        )
        factRow(
          DeveloperValueRow(
            label: OJDLocalized.string("developer.route"),
            value: routeName(device.discoverySource)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.connection"),
            value: device.connection
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.usbEndpoints"),
            value: String(
              format: "Input 0x%02X · Output 0x%02X",
              device.inputEndpoint,
              device.outputEndpoint
            )
          )
        )
        factRow(
          DeveloperValueRow(
            label: OJDLocalized.string("developer.buttons"),
            value: buttonValue(model.latestInput?.pressed)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.leftStick"),
            value: stickValue(model.latestInput?.leftStick)
          ),
          DeveloperValueRow(
            label: OJDLocalized.string("developer.rightStick"),
            value: stickValue(model.latestInput?.rightStick)
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

    /// Raw canonical values; Y points up.
    private func stickValue(_ stick: StickPosition?) -> String {
      let stick = stick ?? .center
      return "\(stick.x.rawValue), \(stick.y.rawValue)"
    }

    private func buttonValue(_ pressed: Set<ControlID>?) -> String {
      guard let pressed, !pressed.isEmpty else {
        return OJDLocalized.string("common.none")
      }
      return ControlID.allCases.filter(pressed.contains).map(\.rawValue).joined(separator: ", ")
    }

    /// Family label; transport variants share their family's label.
    private func protocolName(_ value: ProtocolBindingID) -> String {
      switch value.protocolID {
      case .xboxXID: OJDLocalized.string("controller.originalXbox")
      case .xboxXUSB where value.variant == .receiver:
        OJDLocalized.string("controller.xbox360WirelessDeveloper")
      case .xboxXUSB: OJDLocalized.string("controller.xbox360")
      case .xboxGIP: OJDLocalized.string("controller.xboxOne")
      case .sonySixaxis: OJDLocalized.string("controller.dualShock3")
      case .sonyDualShock4: OJDLocalized.string("controller.dualShock4")
      case .sonyDualSense: OJDLocalized.string("controller.dualSense")
      case .valveSteamController:
        OJDLocalized.string("controller.steamController")
      case .vendorFlydigi: OJDLocalized.string("controller.flydigi")
      case .vendorPS3ThirdParty: "Third-party PS3"
      case .vendorNVIDIAShield: "NVIDIA SHIELD"
      case .vendorGameSir where value.variant == .usb: "GameSir G7 Pro USB"
      case .vendorGameSir: "GameSir enhanced HID"
      case .nintendoSwitch1:
        OJDLocalized.string("controller.switchProController")
      case .hidDescriptor, .hidReportLayout:
        OJDLocalized.string("controller.standardHID")
      }
    }

    private func routeName(_ value: DeviceDiscoverySource) -> String {
      switch value {
      case .hid: return OJDLocalized.string("developer.hid")
      case .rawUSB: return OJDLocalized.string("developer.rawUSB")
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
          .textSelection(.enabled)
      }.accessibilityElement(children: .combine)
    }
  }

#endif
