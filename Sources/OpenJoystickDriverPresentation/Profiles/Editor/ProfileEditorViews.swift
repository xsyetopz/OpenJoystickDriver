#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Profile editor

  /// The editor of one profile.
  struct ProfileEditorView: View {
    /// The profile as stored.
    let profile: RemappingProfile
    /// What the profile's controller has.
    let capabilities: ControllerProfileCapabilities
    /// The state of the edits.
    @ObservedObject
    var editor: ProfileEditorViewModel
    /// The model of the app's view of the service.
    @ObservedObject
    var viewModel: RuntimeViewModel
    /// The profile library, whose changes the editor starts and follows.
    @ObservedObject
    var library: ProfileLibraryModel
    /// Whether the profile is active.
    let isActive: Bool
    /// Whether another change blocks editing.
    let isEditingBlocked: Bool
    /// The section the editor shows.
    @Binding
    var selectedSection: ProfileEditorSection
    /// Tells the profiles list whether the editor holds unsaved edits.
    let onEditingStateChanged: (Bool) -> Void
    /// Asks the profiles list to start a change; returns whether it may start.
    let onMutationStarted: (RuntimeMutationRequest) -> Bool
    /// Reports the result of a change to the profiles list.
    let onMutationResult: (RuntimeMutationResult) -> Void
    /// The confirmation that is open, or nil.
    @State
    var confirmation: ProfileEditorConfirmation?

    /// Creates the editor of `profile`.
    init(
      profile: RemappingProfile,
      capabilities: ControllerProfileCapabilities,
      editor: ProfileEditorViewModel,
      viewModel: RuntimeViewModel,
      library: ProfileLibraryModel,
      isActive: Bool,
      isEditingBlocked: Bool,
      selectedSection: Binding<ProfileEditorSection>,
      onEditingStateChanged: @escaping (Bool) -> Void,
      onMutationStarted: @escaping (RuntimeMutationRequest) -> Bool,
      onMutationResult: @escaping (RuntimeMutationResult) -> Void
    ) {
      self.profile = profile
      self.capabilities = capabilities
      self.editor = editor
      self.viewModel = viewModel
      self.library = library
      self.isActive = isActive
      self.isEditingBlocked = isEditingBlocked
      _selectedSection = selectedSection
      self.onEditingStateChanged = onEditingStateChanged
      self.onMutationStarted = onMutationStarted
      self.onMutationResult = onMutationResult
    }
  }

  /// The confirmations that the profile editor asks for.
  enum ProfileEditorConfirmation: Identifiable {
    /// Activating a profile that produces no output.
    case activateEmpty
    /// Clearing all input of the profile.
    case clearInputs
    /// Removing every assignment of the profile.
    case removeAllAssignments

    /// A string that tells the confirmations apart.
    var id: String {
      switch self {
      case .activateEmpty: "activate-empty"
      case .clearInputs: "clear-inputs"
      case .removeAllAssignments: "remove-all-assignments"
      }
    }
  }

#endif
