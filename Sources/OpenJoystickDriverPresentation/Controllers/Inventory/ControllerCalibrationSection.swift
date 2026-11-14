#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The calibration rows of the controller detail: for each stick and trigger, the raw value, the
  /// value after tuning, with the row that edits the stick dead zone of the controller model.
  struct ControllerCalibrationSection: View {
    /// The model of the app's view of the service.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The controller.
    let device: ApplicationServiceDeviceDescription
    /// The dead zone setting of the controller's model.
    let setting: StickDeadzoneSetting
    /// Reads the record again after the service wrote it.
    let reload: () async -> Void
    /// The values of the last read.
    @StateObject
    private var model = ControllerCalibrationModel()

    /// The dead zone row and a row for each stick and trigger.
    var body: some View {
      Group {
        StickDeadzoneRow(viewModel: viewModel, device: device, setting: setting, reload: reload)
        ForEach(model.rows) { row in
          OJDLabeledValue(Self.label(row.control), Self.text(row))
        }
        OJDLabeledRow(OJDLocalized.string("ui.controllers.recalibrate.title")) {
          ControllerRecalibrationControls(
            gateway: viewModel.gateway,
            selector: .session(device.sessionToken)
          )
        }
      }.task(id: device.sessionToken.rawValue) {
        await model.run(device: device, deadZone: { setting.value }, gateway: viewModel.gateway)
      }
    }

    /// Returns the name of a control.
    static func label(_ control: ControllerCalibrationRow.Control) -> String {
      OJDLocalized.string("ui.controllers.calibration.\(control.rawValue)")
    }

    /// Returns the raw value and the tuned value of a row as text.
    static func text(_ row: ControllerCalibrationRow) -> String {
      let tuned =
        row.tuned.map(percent) ?? OJDLocalized.string("ui.controllers.calibration.noOutput")
      return OJDLocalized.formatted(
        "ui.controllers.calibration.reading",
        percent(row.raw),
        tuned
      )
    }

    /// Returns a `0...1` value as a percentage.
    private static func percent(_ value: Double) -> String {
      value.formatted(.percent.precision(.fractionLength(0)))
    }
  }

#endif
