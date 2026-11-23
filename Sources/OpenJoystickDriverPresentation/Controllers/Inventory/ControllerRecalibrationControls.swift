#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The recalibration controls of one controller: the instructions, a button for each step and for
  /// Reset, and the result of the latest request.
  struct ControllerRecalibrationControls: View {
    /// The controller, or nil while none is selected.
    let selector: ControllerReference?
    /// Whether the controller sends motion data; without it the gyro step has nothing to measure.
    let hasMotion: Bool
    /// The state of the requests.
    @StateObject
    private var model: ControllerRecalibrationViewModel

    /// Creates the controls on `gateway` for the controller.
    init(
      gateway: any ControllerRecalibrationGateway,
      selector: ControllerReference?,
      hasMotion: Bool
    ) {
      self.selector = selector
      self.hasMotion = hasMotion
      _model = StateObject(wrappedValue: ControllerRecalibrationViewModel(gateway: gateway))
    }

    /// The instructions, the step and Reset buttons, and the message.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(OJDLocalized.string("ui.controllers.recalibrate.instructions")).font(.body)
          .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        if hasMotion {
          Text(OJDLocalized.string("ui.controllers.recalibrate.gyroInstructions")).font(.body)
            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }
        HStack {
          ForEach(Self.actions(hasMotion: hasMotion), id: \.self) { action in
            button(action)
          }
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

    /// The actions with a button, in order; the gyro step shows only for a controller with motion.
    nonisolated static func actions(hasMotion: Bool) -> [ControllerRecalibrationAction] {
      ControllerRecalibrationAction.allCases.filter { hasMotion || $0 != .gyro }
    }

    /// A button that runs `action` on the controller.
    private func button(_ action: ControllerRecalibrationAction) -> some View {
      let keys = Self.keys(action)
      return Button(OJDLocalized.string(keys.title)) {
        guard let selector else { return }
        Task { await model.run(action, for: selector) }
      }.help(OJDLocalized.string(keys.help))
    }

    /// The localization keys of the button title and tooltip for `action`.
    nonisolated static func keys(
      _ action: ControllerRecalibrationAction
    ) -> (title: String, help: String) {
      switch action {
      case .rest: return ("ui.controllers.recalibrate.rest", "ui.help.recalibrate.rest")
      case .circle: return ("ui.controllers.recalibrate.circle", "ui.help.recalibrate.circle")
      case .triggers: return ("ui.controllers.recalibrate.triggers", "ui.help.recalibrate.triggers")
      case .gyro: return ("ui.controllers.recalibrate.gyro", "ui.help.recalibrate.gyro")
      case .reset: return ("action.reset", "ui.help.recalibrate.reset")
      }
    }
  }
#endif
