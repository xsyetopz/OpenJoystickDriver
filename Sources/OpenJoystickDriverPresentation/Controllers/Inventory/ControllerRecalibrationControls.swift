#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The recalibration controls of one controller: the instructions, a button for each step and for
  /// Reset, and the result of the latest request.
  struct ControllerRecalibrationControls: View {
    /// The controller, or nil while none is selected.
    let selector: ControllerReference?
    /// The state of the requests.
    @StateObject
    private var model: ControllerRecalibrationViewModel

    /// Creates the controls on `gateway` for the controller.
    init(gateway: any ControllerRecalibrationGateway, selector: ControllerReference?) {
      self.selector = selector
      _model = StateObject(wrappedValue: ControllerRecalibrationViewModel(gateway: gateway))
    }

    /// The instructions, the step and Reset buttons, and the message.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(OJDLocalized.string("ui.controllers.recalibrate.instructions")).font(.body)
          .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        Text(OJDLocalized.string("ui.controllers.recalibrate.gyroInstructions")).font(.body)
          .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        HStack {
          button("ui.controllers.recalibrate.rest", .rest)
          button("ui.controllers.recalibrate.circle", .circle)
          button("ui.controllers.recalibrate.triggers", .triggers)
          button("ui.controllers.recalibrate.gyro", .gyro)
          button("action.reset", .reset)
          if model.isBusy {
            ProgressView().controlSize(.small)
            Text(OJDLocalized.string("ui.controllers.recalibrate.running"))
          }
        }.disabled(selector == nil || model.isBusy)
        if let message = model.message {
          Text(message).font(.body).foregroundColor(model.isFailure ? .red : .primary)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    /// A button that runs `action` on the controller.
    private func button(_ title: String, _ action: ControllerRecalibrationAction) -> some View {
      Button(OJDLocalized.string(title)) {
        guard let selector else { return }
        Task { await model.run(action, for: selector) }
      }
    }
  }
#endif
