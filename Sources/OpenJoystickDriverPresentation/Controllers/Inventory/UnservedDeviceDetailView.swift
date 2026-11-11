#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The detail of a connected device that OJD does not serve: the reason, the next step, and for
  /// a HID pad the Draft Record action.
  struct UnservedDeviceDetailView: View {
    /// The device that OJD does not serve.
    let device: RuntimeUnservedDevice
    /// The state and results of the draft.
    @StateObject
    private var actions = ControllerDetailActions()

    /// The reason, the next step, and the action.
    var body: some View {
      Form {
        Section {
          Text(device.explanation).fixedSize(horizontal: false, vertical: true)
          VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
            Text(OJDLocalized.string("ui.controllers.unserved.nextStepLabel")).font(.caption)
              .foregroundColor(Color(NSColor.secondaryLabelColor))
            Text(device.nextStep).fixedSize(horizontal: false, vertical: true)
          }
        } header: {
          VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
            Text(device.title)
            Text("\(device.identity)  \(device.connection)").font(.caption)
              .foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        }
        if device.offersDraft {
          Section {
            Button(OJDLocalized.string("ui.controllers.draftRecord")) {
              actions.clearNotice()
              actions.draftUnserved(model: device.modelID)
            }
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
