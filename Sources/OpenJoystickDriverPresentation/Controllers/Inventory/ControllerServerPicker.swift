#if canImport(SwiftUI)

  import Foundation
  import OpenJoystickDriverKit
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

    /// The segmented picker of the two servers.
    var body: some View {
      Picker(OJDLocalized.string("ui.controllers.server.label"), selection: serverBinding) {
        Text(OJDLocalized.string("platform.macos.ui.controllers.server.system")).tag(
          ControllerServer.system
        )
        Text(OJDLocalized.string("ui.controllers.server.ojd")).tag(ControllerServer.ojd)
      }.pickerStyle(.segmented)
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
