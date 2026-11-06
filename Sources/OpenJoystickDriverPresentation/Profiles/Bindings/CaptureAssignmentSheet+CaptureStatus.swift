#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension CaptureAssignmentSheet {

    /// The capture status as VoiceOver reads it.
    private var captureStatusAccessibilityValue: String {
      switch viewModel.inputCaptureState {
      case .idle: return OJDLocalized.string("ui.capture.ready")
      case .listening:
        return OJDLocalized.string(
          "ui.capture.listening"
        )
      case .received(_, let state):
        if let detected = RuntimePresentation.detectedSource(from: state) {
          return OJDLocalized.formatted(
            "ui.capture.detected",
            RuntimePresentation.sourceLabel(detected)
          )
        }
        return OJDLocalized.string(
          "ui.capture.noSupported"
        )
      case .detected(_, _, let detected):
        return OJDLocalized.formatted(
          "ui.capture.detectedWithDestination",
          RuntimePresentation.sourceLabel(detected),
          OJDLocalized.string(
            "ui.capture.destinationReady"
          )
        )
      case .unavailable(_, let message), .error(_, let message): return message
      }
    }

    /// Announces the capture state to VoiceOver: the start of listening, the detected control, or
    /// the failure.
    ///
    /// A detection on another controller than the selected one is not announced.
    func announceCaptureState(_ captureState: RuntimeInputCaptureState) {
      let message: String
      switch captureState {
      case .idle, .received: return
      case .listening:
        message = OJDLocalized.string(
          "ui.capture.listeningCancel"
        )
      case .detected(let selector, _, let detected):
        guard selectedDeviceSelector == selector else { return }
        message = OJDLocalized.formatted(
          "ui.capture.detectedWithDestination",
          RuntimePresentation.sourceLabel(detected),
          OJDLocalized.string(
            "ui.capture.destinationReady"
          )
        )
      case .unavailable(_, let detail): message = detail
      case .error(_, let detail):
        message = OJDLocalized.formatted("ui.capture.error", detail)
      }
      NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }

    /// The capture status line: the progress, the detected control with the held buttons, or the
    /// failure in red.
    @ViewBuilder
    var captureStatus: some View {
      Group {
        switch viewModel.inputCaptureState {
        case .idle: EmptyView()
        case .listening:
          Text(
            OJDLocalized.string(
              "ui.capture.listeningEllipsis"
            )
          )
        case .received(_, let state):
          VStack(alignment: .leading, spacing: 3) {
            if let detected = RuntimePresentation.detectedSource(from: state) {
              Text(
                OJDLocalized.formatted(
                  "ui.capture.detectedNoPeriod",
                  RuntimePresentation.sourceLabel(detected)
                )
              ).font(.subheadline.weight(.semibold))
            } else {
              Text(
                OJDLocalized.string(
                  "ui.capture.noSupported"
                )
              ).font(.subheadline.weight(.semibold))
            }
            Text(heldControlsText(state))
          }
        case .detected(_, let state, let detected):
          VStack(alignment: .leading, spacing: 3) {
            Text(
              OJDLocalized.formatted(
                "ui.capture.detectedNoPeriod",
                RuntimePresentation.sourceLabel(detected)
              )
            ).font(.subheadline.weight(.semibold))
            Text(heldControlsText(state))
          }
        case .unavailable(_, let message), .error(_, let message):
          Text(message).foregroundColor(Color(NSColor.systemRed))
        }
      }.ojdAccessibilityLabel(OJDLocalized.string("ui.capture.status"))
        .ojdAccessibilityValue(captureStatusAccessibilityValue)
    }
    /// Returns the buttons held in `state`, or the text that says none is.
    private func heldControlsText(_ state: ControllerState) -> String {
      let held = Control.allCases.filter(state.pressed.contains)
      guard !held.isEmpty else {
        return OJDLocalized.string("ui.capture.noButton")
      }
      return OJDLocalized.formatted(
        "ui.capture.buttonsHeld",
        held.map(\.rawValue).joined(separator: ", ")
      )
    }
  }

#endif
