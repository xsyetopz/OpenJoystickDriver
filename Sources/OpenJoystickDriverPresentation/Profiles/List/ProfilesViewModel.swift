#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import UniformTypeIdentifiers

  /// Reads and writes profile files off the main actor.
  actor ProfileDocumentService {
    /// Loads and validates the profile in the file.
    ///
    /// - Parameter url: The file to load.
    /// - Returns: The profile.
    /// - Throws: The loader's error when the file cannot be read or is not a valid profile.
    func load(from url: URL) throws -> RemappingProfile {
      try RemappingProfileFileStore.load(from: url)
    }

    /// Reads the contents of the file.
    ///
    /// - Parameter url: The file to read.
    /// - Returns: The contents of the file.
    /// - Throws: The error of the file read.
    func read(from url: URL) throws -> Data { try Data(contentsOf: url) }

    /// Writes the profile to the file.
    ///
    /// - Parameters:
    ///   - profile: The profile to write.
    ///   - url: The file to write.
    /// - Throws: The writer's error when the file cannot be written.
    func write(_ profile: RemappingProfile, to url: URL) throws {
      try RemappingProfileFileStore.write(profile, to: url)
    }
  }

  /// The state of the Profiles screen: the selection, the sheets and alerts, and the editor.
  @MainActor
  final class ProfilesViewModel: ObservableObject {
    /// Reads and writes the profile files.
    let documents: ProfileDocumentService
    /// The capabilities of the protocol drivers, which the editor uses for controllers that are not
    /// connected.
    let capabilityRegistry = ProtocolDriverRegistry()
    /// The names of the applications that scope profiles.
    let applicationNames = ProfileApplicationNames()
    /// The selected profile.
    @Published
    var selectedProfileID: UUID?
    /// The selected damaged profile or unusable library.
    @Published
    var selectedRecoveryIssueID: UUID?
    /// Whether the profile creation sheet is open.
    @Published
    var isCreatingProfile = false
    /// The alert that is open, or nil.
    @Published
    var activeAlert: ProfilesAlert?
    /// The message of the latest failed profile action, or nil.
    @Published
    var profileActionError: String?
    /// The profile whose Joy-Con pair sheet is open, or nil.
    @Published
    var pairingProfile: RemappingProfile?
    /// The profile whose copy the Duplicate sheet is naming.
    @Published
    var duplicatingProfile: RemappingProfile?
    /// The result of the last Validate Profile File check, shown until dismissed.
    @Published
    var fileValidation: ProfileFileValidation?
    /// A profile read from a file the person chose, waiting for the Profiles screen to import it
    /// through the editor's discard and mutation checks.
    @Published
    var chosenImportProfile: RemappingProfile?
    /// The section of the profile editor that is shown.
    @Published
    var selectedEditorSection = ProfilePresentationPolicy.defaultSection

    /// The editor's dirty state, waiting action and owned request.
    @Published
    var editorTransition = ProfileEditorTransitionState()
    /// The discard count of the main window that the screen has seen.
    var observedDiscardGeneration = 0
    /// The latest snapshot the service sent.
    var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload?
    /// The profile of the editor when the selected profile left the library with unsaved edits.
    var preservedEditorProfile: RemappingProfile?
    /// A count that grows to make the screen build a fresh editor model.
    var editorGeneration = 0
    /// The editor model in use, or nil.
    private var editorViewModel: ProfileEditorViewModel?
    /// The discard count and the refresh count that `editorViewModel` was built for.
    private var editorViewModelGeneration: (discard: Int, refresh: Int)?

    /// Creates the model on `documents`.
    init(documents: ProfileDocumentService = ProfileDocumentService()) {
      self.documents = documents
    }

    /// Returns whether profile creation, import, delete and the like must wait: a request or
    /// recovery runs, the editor is blocked, or the library has damaged entries.
    ///
    /// The Profiles screen and the toolbar share this.
    ///
    /// - Parameters:
    ///   - library: The profile library, whose requests and recovery the check reads.
    ///   - runtime: The model of the app's view of the service, whose snapshot the check reads.
    /// - Returns: Whether profile creation, import, delete and the like must wait: a request or
    ///   recovery runs, the editor is blocked, or the library has damaged entries.
    func isActionBlocked(library: ProfileLibraryModel, runtime: RuntimeViewModel) -> Bool {
      actionBlock(library: library, runtime: runtime) != nil
    }

    /// Returns why profile creation, import, delete and the like must wait, or nil.
    ///
    /// - Parameters:
    ///   - library: The profile library, whose requests and recovery the check reads.
    ///   - runtime: The model of the app's view of the service, whose snapshot the check reads.
    /// - Returns: The reason, or nil when the actions may run.
    func actionBlock(
      library: ProfileLibraryModel,
      runtime: RuntimeViewModel
    ) -> ProfileActionBlock? {
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      if case .available(let current) = runtime.remappingState {
        snapshot = current
      } else {
        snapshot = lastKnownSnapshot
      }
      if library.profileRecoveryInFlight { return .recoveryRunning }
      if library.activeMutationOperation != nil || editorTransition.isEditingBlocked {
        return .changeRunning
      }
      return (snapshot?.profileIssues.isEmpty ?? true) ? nil : .needsRecovery
    }

    /// Asks for a profile file and reads it into ``chosenImportProfile``.
    func chooseProfileToImport() {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = OJDLocalized.string("ui.profiles.import")
      panel.allowedContentTypes = [.propertyList]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          chosenImportProfile = try await documents.load(from: url)
          profileActionError = nil
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    /// The protocol family of every catalog model, read when the profile creation sheet opens.
    ///
    /// The sheet offers these models beyond the connected controllers and those of existing
    /// profiles.
    @Published
    private(set) var catalogModels: [ControllerModelID: PhysicalProtocolID] = [:]
    /// Whether the catalog read of the profile creation sheet is still running.
    @Published
    private(set) var isLoadingCatalog = false
    /// How many user controller record files the last catalog read could not use.
    @Published
    private(set) var unreadableRecordFiles = 0

    /// Opens the profile creation sheet and reads the catalog off the main actor.
    func beginCreatingProfile() {
      catalogModels = [:]
      unreadableRecordFiles = 0
      isLoadingCatalog = true
      isCreatingProfile = true
      Task { @MainActor in
        let (families, unreadable) = await Task.detached {
          let set = ControllerRecordSet.load(userDirectory: ControllerRecordSet.userDirectory)
          return (set.records.mapValues(\.protocolID), set.problems.count)
        }.value
        catalogModels = families
        unreadableRecordFiles = unreadable
        isLoadingCatalog = false
      }
    }

    /// Asks for a profile file and checks it without adding it to the library.
    func validateProfileFile() {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = OJDLocalized.string("ui.profiles.validateFile")
      panel.allowedContentTypes = [.propertyList]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          let data = try await documents.read(from: url)
          fileValidation = ProfileFileValidation.check(data, fileName: url.lastPathComponent)
          profileActionError = nil
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    /// Asks where to save `profile` and writes it there.
    ///
    /// - Parameter profile: The profile to export.
    func exportProfile(_ profile: RemappingProfile) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("ui.profiles.export")
      panel.nameFieldStringValue = "\(profile.name).plist"
      panel.allowedContentTypes = [.propertyList]
      guard panel.runModal() == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          try await documents.write(profile, to: url)
          profileActionError = nil
        } catch { profileActionError = RuntimePresentation.userFacingError(error) }
      }
    }

    /// Returns the editor model of the profile, building a fresh one when the profile, the discard
    /// count or the refresh count differ from those of the model in use.
    ///
    /// - Parameters:
    ///   - profile: The profile to edit.
    ///   - discardGeneration: The discard count of the main window.
    /// - Returns: The editor model of the profile, building a fresh one when the profile, the
    ///   discard count or the refresh count differ from those of the model in use.
    func editor(for profile: RemappingProfile, discardGeneration: Int) -> ProfileEditorViewModel {
      let generation = (discard: discardGeneration, refresh: editorGeneration)
      if let editorViewModel, editorViewModel.expectedCurrent.id == profile.id,
        editorViewModelGeneration?.discard == generation.discard,
        editorViewModelGeneration?.refresh == generation.refresh
      {
        return editorViewModel
      }
      let editor = ProfileEditorViewModel(profile: profile)
      editorViewModel = editor
      editorViewModelGeneration = generation
      return editor
    }

    /// Drops the editor model in use.
    func resetEditor() {
      editorViewModel = nil
      editorViewModelGeneration = nil
    }

    /// Keeps the selection valid for a new snapshot: a vanished selection falls back to the first
    /// profile, else the first damaged entry.
    ///
    /// - Parameter snapshot: The snapshot the service sent.
    func reconcileSelection(with snapshot: ApplicationServiceRemappingSnapshotPayload) {
      if let selectedRecoveryIssueID,
        !snapshot.profileIssues.contains(where: { $0.id == selectedRecoveryIssueID })
      {
        self.selectedRecoveryIssueID = nil
      }
      if let selectedProfileID, !snapshot.profiles.contains(where: { $0.id == selectedProfileID }) {
        self.selectedProfileID = snapshot.profiles.first?.id
      }
      if selectedProfileID == nil, selectedRecoveryIssueID == nil {
        selectedProfileID = snapshot.profiles.first?.id
        if selectedProfileID == nil { selectedRecoveryIssueID = snapshot.profileIssues.first?.id }
      }
    }
  }

  /// The edits of one profile in the editor: the draft, the sheet that is open, the errors and
  /// the save.
  @MainActor
  final class ProfileEditorViewModel: ObservableObject {
    /// The draft being edited.
    @Published
    var draft: RuntimeProfileDraft
    /// The sheet that is open, or nil.
    @Published
    var activeSheet: ProfileEditorSheet?
    /// Whether the conflict banner shows.
    @Published
    var showingConflict = false
    /// The message of the latest refused edit, or nil.
    @Published
    var localError: String?
    /// The message of the latest failed save, or nil.
    @Published
    var saveError: String?

    /// The stored profile that the draft is compared with.
    @Published
    var expectedCurrent: RemappingProfile
    /// The save that is in flight.
    @Published
    var saveState = ProfileEditorSaveState()

    /// Creates the editor model on `profile`.
    ///
    /// - Parameter profile: The profile to edit.
    init(profile: RemappingProfile) {
      draft = RuntimeProfileDraft(profile: profile)
      expectedCurrent = profile
    }
  }

#endif
