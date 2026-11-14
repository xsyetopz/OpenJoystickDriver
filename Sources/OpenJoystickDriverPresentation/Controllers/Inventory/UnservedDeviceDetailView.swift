#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The detail of a connected device that OJD does not serve: its state, and for a HID pad the
  /// Draft Record action.
  ///
  /// The list row beside it shows the name, identity, reason and next step.
  struct UnservedDeviceDetailView: View {
    /// The device that OJD does not serve.
    let device: RuntimeUnservedDevice
    /// Runs the button of the device's state.
    let perform: @MainActor (ControllerReadinessAction) -> Void
    /// The state and results of the draft.
    @StateObject
    private var actions = ControllerDetailActions()

    /// The state and the action.
    var body: some View {
      Form {
        Section { ControllerReadinessCard(readiness: device.readiness, perform: perform) }
        if device.offersDraft {
          Section {
            Button(OJDLocalized.string("ui.controllers.draftRecord")) {
              actions.clearNotice()
              actions.draftUnserved(model: device.modelID)
            }.help(OJDLocalized.string("ui.help.draftRecord"))
            if let notice = actions.notice {
              ControllerNoticeText(text: notice.text, isError: notice.isError)
            }
          }
        }
      }.onReceive(actions.$pendingSave) { request in
        guard let request else { return }
        ControllerFilePanels.save(request) { actions.finishSave(to: $0) }
      }.ojdGroupedForm().accessibilityElement(children: .contain)
        .ojdAccessibilityLabel(device.title).ojdAccessibilityValue(
          "\(device.explanation) \(device.nextStep)"
        )
    }
  }

#endif
