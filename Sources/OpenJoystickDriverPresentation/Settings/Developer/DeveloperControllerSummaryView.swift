#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Controller section of the developer tools: the controller picker and Refresh.
  ///
  /// Raw Packet Capture and Extra Buttons read the picked controller. Its facts are in its
  /// Controllers detail and its live input is in Input Test.
  struct DeveloperControllerSummaryView: View {
    /// The state of the developer tools.
    @ObservedObject
    var model: DeveloperToolsViewModel
    /// The section of the controller picker and Refresh, with no heading because the picker's
    /// label already names it Controller.
    var body: some View {
      Section {
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
        .disabled(model.controllerPickerUnavailableReason != nil)
        .help(
          model.controllerPickerUnavailableReason ?? OJDLocalized.string("ui.help.controllerPicker")
        )
        if let reason = model.controllerPickerUnavailableReason {
          Text(reason).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Button(OJDLocalized.string("action.refresh"), action: model.requestRefresh)
          .disabled(model.isCapturing).help(OJDLocalized.string("ui.help.refreshControllers"))
      }
    }
  }

#endif
