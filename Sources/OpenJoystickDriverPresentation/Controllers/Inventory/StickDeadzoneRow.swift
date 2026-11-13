#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The stick dead zone of one controller model: a stepper over the value, and a button that
  /// removes the user's value.
  ///
  /// Each change goes to the service, which rewrites the user record. Both controls stay disabled
  /// until the record has been read again.
  struct StickDeadzoneRow: View {
    /// The model of the app's view of the service.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The controller.
    let device: ApplicationServiceDeviceDescription
    /// The dead zone setting.
    let setting: StickDeadzoneSetting
    /// Reads the record again after the service wrote it.
    let reload: () async -> Void
    /// Sends the changes to the service, one at a time.
    @StateObject
    private var editor = StickDeadzoneEditor()

    /// The label, the value, the stepper and Reset.
    var body: some View {
      OJDLabeledRow(OJDLocalized.string("ui.controllers.stickDeadzone.label")) {
        HStack {
          Text(setting.text).foregroundColor(Color(NSColor.secondaryLabelColor))
          Stepper(
            OJDLocalized.string("ui.controllers.stickDeadzone.label"),
            onIncrement: setting.increased.map { value in { change(to: value) } },
            onDecrement: setting.decrementClears
              ? { change(to: nil) } : setting.decreased.map { value in { change(to: value) } }
          ).labelsHidden()
          if setting.canReset {
            Button(OJDLocalized.string("action.reset")) { change(to: nil) }
          }
        }.disabled(editor.isWriting)
      }
    }

    /// Sends a change of the dead zone.
    ///
    /// - Parameter value: The dead zone, or nil to remove the user's value.
    private func change(to value: Double?) {
      Task { @MainActor in
        await editor.change(to: value, for: device, viewModel: viewModel, reload: reload)
      }
    }
  }

#endif
