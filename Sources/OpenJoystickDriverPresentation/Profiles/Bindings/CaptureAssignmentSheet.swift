#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  /// The sheet that adds an assignment: the person presses a control of a connected controller
  /// or picks one, and picks what it does.
  struct CaptureAssignmentSheet: View {
    /// The model whose input capture and status the sheet reads.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// What the controller has, which decides the sources and destinations that can be chosen.
    let capabilities: ControllerProfileCapabilities
    /// The macros of the profile, which the destination picker offers.
    let macros: [RemappingMacro]
    /// Receives the source and destination when the person chooses Add Assignment.
    let onAdd: (RemappingSource, RemappingDestination) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    var presentationMode
    /// The source of the assignment.
    @State
    var source: RemappingSource = .button(.south)
    /// The destination of the assignment.
    @State
    var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])
    /// Whether the person cleared the key of the keyboard destination.
    @State
    var keyboardDestinationCleared = false
    /// Whether the keyboard destination waits for a key press.
    @State
    var keyboardCaptureActive = false
    /// The session token of the controller to listen to, or nil before one is selected.
    @State
    var selectedSessionToken: String?
  }

#endif
