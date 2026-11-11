#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
  import AppKit
  import SwiftUI

  /// Who serves one controller model, macOS natively or OpenJoystickDriver as a virtual controller,
  /// matching `ojd controller claim` and `release`.
  ///
  /// A change goes to the service, which rewrites the user record and re-applies it to the
  /// connected controller.
  struct ControllerServerPicker: View {
    /// The model of the app's view of the service, which applies the change.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The controller.
    let device: ApplicationServiceDeviceDescription
    /// Whether a record describes the controller's model; without one the service refuses a choice.
    let hasRecord: Bool

    /// Returns whether the picker applies to `device`: macOS serves it natively, or its record
    /// already gives it to OpenJoystickDriver, and its family does not use raw USB, which always
    /// belongs to OpenJoystickDriver.
    ///
    /// - Parameter device: The controller.
    /// - Returns: Whether the picker applies to `device`: macOS serves it natively, or its record
    ///   already gives it to OpenJoystickDriver, and its family does not use raw USB, which always
    ///   belongs to OpenJoystickDriver.
    static func isShown(for device: ApplicationServiceDeviceDescription) -> Bool {
      ServingPolicy.offersServerChoice(ServingInput(device))
    }

    /// The segmented picker of the two servers; below it the progress of the request, the reason it
    /// is unavailable, or the service's refusal.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Picker(OJDLocalized.string("ui.controllers.server.label"), selection: serverBinding) {
          Text(OJDLocalized.string("platform.macos.ui.controllers.server.system")).tag(
            ControllerServer.system
          )
          Text(OJDLocalized.string("ui.controllers.server.ojd")).tag(ControllerServer.ojd)
        }.pickerStyle(.segmented).disabled(isRunning || unavailableReason != nil)
        if isRunning {
          HStack(spacing: OJDSpacing.small) {
            ProgressView().controlSize(.small)
            Text(OJDLocalized.string("ui.controllers.server.updating")).font(.caption)
              .foregroundColor(Color(NSColor.secondaryLabelColor))
          }
        } else if let message = unavailableReason ?? refusal {
          Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    /// Whether the service is applying a choice.
    private var isRunning: Bool { viewModel.isControllerServerRequestRunning(for: device) }

    /// Why no choice is offered, or nil.
    private var unavailableReason: String? {
      viewModel.controllerServerUnavailableReason(hasRecord: hasRecord)
    }

    /// Why the service refused the latest choice, or nil.
    private var refusal: String? {
      viewModel.controllerServerFailures[RuntimeControllerModel(device)]
    }

    /// The binding to the server that is shown; choosing the other one sends the change to the
    /// service.
    private var serverBinding: Binding<ControllerServer> {
      Binding(
        get: { viewModel.shownControllerServer(for: device) },
        set: { server in
          guard server != viewModel.shownControllerServer(for: device) else { return }
          let device = device
          Task { @MainActor in await viewModel.setControllerServer(server, for: device) }
        }
      )
    }
  }

#endif
