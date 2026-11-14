#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The Lookup button of the controller detail: opens the controller's entry in the
  /// supported-controllers list, or a GitHub search for its VID:PID when it has no record.
  struct ControllerLookupButton: View {
    /// The model of the controller.
    let model: ControllerModelID

    /// The effective record of the model, `nil` when it has none.
    let record: ControllerRecord?

    /// The button.
    var body: some View {
      Button(OJDLocalized.string("ui.controllers.lookup")) {
        NSWorkspace.shared.open(ControllerLookup.url(for: model, record: record))
      }.help(OJDLocalized.string("ui.help.lookup"))
    }
  }

#endif
