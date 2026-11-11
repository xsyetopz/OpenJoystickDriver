#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  /// The detail of one controller in the Controllers area of the main window.
  struct ControllerDetailView: View {
    /// The controller.
    let device: ApplicationServiceDeviceDescription
    /// The profile that is active for the controller.
    let activeProfile: RuntimeActiveProfileState
    /// Reloads the status after a failed load.
    let retry: () -> Void
    /// The model of the app's view of the service.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// Opens the Input Test window for the controller.
    let openInputTest: @MainActor (ApplicationServiceDeviceDescription) -> Void
    /// Whether the serial number shows.
    @State
    var serialVisibility = SerialNumberVisibility()
    /// Whether the Advanced section is open.
    @State
    var showsAdvanced = false
    /// Whether the Tuning section is open.
    @State
    var showsTuning = false
    /// The effective record of the controller's model, read from the record files.
    @State
    var record: ControllerRecord?
    /// Whether the record has been read once, so a missing record is not reported while it loads.
    @State
    var hasLoadedRecord = false
    /// The state and results of the longer actions.
    @StateObject
    var actions = ControllerDetailActions()
  }

#endif
