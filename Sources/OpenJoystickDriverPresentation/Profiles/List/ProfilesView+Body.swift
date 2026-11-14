#if canImport(SwiftUI)

  import Combine
  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {

    /// The selected profile, kept in ``screen``.
    var selectedProfileID: UUID? {
      get { screen.selectedProfileID }
      nonmutating set { screen.selectedProfileID = newValue }
    }
    /// The selected damaged profile or unusable library, kept in ``screen``.
    var selectedRecoveryIssueID: UUID? {
      get { screen.selectedRecoveryIssueID }
      nonmutating set { screen.selectedRecoveryIssueID = newValue }
    }
    /// Whether the profile creation sheet is open, kept in ``screen``.
    var isCreatingProfile: Bool {
      get { screen.isCreatingProfile }
      nonmutating set { screen.isCreatingProfile = newValue }
    }
    /// The editor's dirty state, waiting action and owned request, kept in ``screen``.
    var profileEditorTransition: ProfileEditorTransitionState {
      get { screen.editorTransition }
      nonmutating set { screen.editorTransition = newValue }
    }
    /// The alert that is open, or nil, kept in ``screen``.
    var activeAlert: ProfilesAlert? {
      get { screen.activeAlert }
      nonmutating set { screen.activeAlert = newValue }
    }
    /// The message of the latest failed profile action, or nil, kept in ``screen``.
    var profileActionError: String? {
      get { screen.profileActionError }
      nonmutating set { screen.profileActionError = newValue }
    }
    /// The discard count of the main window that the screen has seen, kept in ``screen``.
    var observedDiscardGeneration: Int {
      get { screen.observedDiscardGeneration }
      nonmutating set { screen.observedDiscardGeneration = newValue }
    }
    /// The latest snapshot the service sent, kept in ``screen``.
    var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload? {
      get { screen.lastKnownSnapshot }
      nonmutating set { screen.lastKnownSnapshot = newValue }
    }
    /// The profile of the editor when the selected profile left the library with unsaved edits,
    /// kept in ``screen``.
    var preservedEditorProfile: RemappingProfile? {
      get { screen.preservedEditorProfile }
      nonmutating set { screen.preservedEditorProfile = newValue }
    }
    /// A count that grows to make the screen build a fresh editor model, kept in ``screen``.
    var profileEditorGeneration: Int {
      get { screen.editorGeneration }
      nonmutating set { screen.editorGeneration = newValue }
    }
    /// The profile whose Joy-Con pair sheet is open, or nil, kept in ``screen``.
    var pairingProfile: RemappingProfile? {
      get { screen.pairingProfile }
      nonmutating set { screen.pairingProfile = newValue }
    }
    /// The section of the profile editor that is shown, kept in ``screen``.
    var selectedEditorSection: ProfileEditorSection {
      get { screen.selectedEditorSection }
      nonmutating set { screen.selectedEditorSection = newValue }
    }

    /// The profile list column, or the detail column, of the Profiles area.
    @ViewBuilder
    var body: some View {
      switch column {
      case .list: profileList
      case .detail: detailColumn
      }
    }

    /// The detail column: the error banner, the profile detail, and the sheets and alerts of the
    /// screen.
    private var detailColumn: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.none) {
        if let commandError = screen.commandActionError {
          ProfileActionErrorBanner(message: commandError) { self.profileActionError = nil }
        }
        if let profileActionBlock {
          Text(profileActionBlock.message).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 28).padding(.vertical, 6)
        }
        profileDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      // Older macOS presents only the last of several sheets attached to one view (unverified on
      // macOS 12), so each sheet hangs off its own sibling background view.
      .background(
        EmptyView().sheet(isPresented: $screen.isCreatingProfile) {
          ProfileNameSheet(
            title: OJDLocalized.string("ui.profiles.new"),
            context: ProfileCreationContext(
              choices: ProfileControllerChoice.choices(
                devices: connectedDevices,
                profiles: profiles,
                catalog: screen.catalogModels,
                names: screen.catalogNames
              ),
              profiles: profiles,
              isLoadingCatalog: screen.isLoadingCatalog,
              unreadableRecordFiles: screen.unreadableRecordFiles
            )
          ) { createProfile($0) }
        }
      ).background(
        EmptyView().sheet(item: $screen.duplicatingProfile) { source in
          ProfileDuplicateSheet(source: source, profiles: profiles) { createProfile($0) }
        }
      ).background(
        EmptyView().sheet(item: $screen.convertingProfile) { source in
          ProfileConversionSheet(
            source: source,
            choices: ProfileControllerChoice.choices(
              devices: connectedDevices,
              profiles: profiles,
              catalog: screen.catalogModels,
              names: screen.catalogNames
            ),
            profiles: profiles,
            isLoadingCatalog: screen.isLoadingCatalog
          ) { convertProfile($0) }
        }
      ).background(
        EmptyView().sheet(item: $screen.conversionReport) { report in
          ProfileConversionReportSheet(report: report)
        }
      ).background(
        EmptyView().sheet(item: $screen.pairingProfile) { profile in
          ProfileJoyConPairSheet(profile: profile, devices: connectedDevices) { left, right in
            Task { @MainActor in
              screen.failProfileAction(
                await viewModel.pairRemappingJoyCons(
                  left: .session(left),
                  right: .session(right),
                  profileID: profile.id
                ),
                beside: .joyCon
              )
            }
          }
        }
      ).background(
        EmptyView().alert(item: $screen.fileValidation) { validation in
          Alert(
            title: Text(validation.title),
            message: Text(validation.message),
            dismissButton: .default(Text(OJDLocalized.string("action.dismiss")))
          )
        }
      ).alert(item: $screen.activeAlert) { alert in
        switch alert {
        case .delete(let id):
          Alert(
            title: Text(OJDLocalized.string("ui.profiles.deleteTitle")),
            message: Text(
              OJDLocalized.string(
                "ui.profiles.deleteMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("action.delete"))
            ) { deleteProfile(id) },
            secondaryButton: .cancel { activeAlert = nil }
          )
        case .discard:
          Alert(
            title: Text(
              OJDLocalized.string("ui.settings.advanced.discardTitle")
            ),
            message: Text(
              OJDLocalized.string(
                "ui.profiles.discardMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("ui.settings.advanced.discardAction"))
            ) {
              guard let action = profileEditorTransition.discardPendingAction() else {
                activeAlert = nil
                return
              }
              setEditorDirty(false)
              activeAlert = nil
              performProfileAction(action)
            },
            secondaryButton: .cancel { cancelPendingProfileAction() }
          )
        case .deleteDamagedProfile(let issueID):
          Alert(
            title: Text(
              OJDLocalized.string("ui.profiles.damagedProfile")
            ),
            message: Text(
              OJDLocalized.string(
                "ui.profiles.recoveryBackupMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("action.delete"))
            ) { recoverProfileIssue(issueID, resetLibrary: false) },
            secondaryButton: .cancel { activeAlert = nil }
          )
        case .resetLibrary(let issueID):
          Alert(
            title: Text(
              OJDLocalized.string(
                "ui.profiles.damagedLibrary"
              )
            ),
            message: Text(
              OJDLocalized.string(
                "ui.profiles.recoveryBackupMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("ui.profiles.resetLibraryAction"))
            ) { recoverProfileIssue(issueID, resetLibrary: true) },
            secondaryButton: .cancel { activeAlert = nil }
          )
        }
      }.onAppear {
        if case .available(let snapshot) = viewModel.remappingState {
          lastKnownSnapshot = snapshot
          screen.reconcileSelection(with: snapshot)
        }
        if observedDiscardGeneration != navigation.discardGeneration {
          profileEditorTransition.setDirty(false)
          observedDiscardGeneration = navigation.discardGeneration
        }
        selectFirstProfileIfNeeded()
        navigation.setProfilesEditorDirty(editorHasUnsavedChanges)
        handleProfileMutation(library.mutationState)
      }.onReceive(library.$mutationState) { handleProfileMutation($0) }.onReceive(
        screen.$chosenImportProfile.compactMap { $0 }
      ) { receiveChosenImportProfile($0) }.onReceive(
        navigation.$discardGeneration
      ) { generation in
        observedDiscardGeneration = generation
        if editorHasUnsavedChanges { setEditorDirty(false) }
      }.onReceive(viewModel.$remappingState) { state in
        if case .available(let snapshot) = state {
          if !editorHasUnsavedChanges, let selectedProfileID,
            lastKnownSnapshot?.profiles.first(where: { $0.id == selectedProfileID })
              != snapshot.profiles.first(where: { $0.id == selectedProfileID })
          {
            profileEditorGeneration += 1
          }
          if editorHasUnsavedChanges, let selectedProfileID,
            !snapshot.profiles.contains(where: { $0.id == selectedProfileID }),
            let previous = lastKnownSnapshot?.profiles.first(where: { $0.id == selectedProfileID })
          {
            preservedEditorProfile = previous
          }
          lastKnownSnapshot = snapshot
          screen.reconcileSelection(with: snapshot)
        }
      }
    }

    /// The profiles of the snapshot, or those of the last snapshot while the state is not
    /// available.
    var profiles: [RemappingProfile] {
      switch viewModel.remappingState {
      case .available(let snapshot): return snapshot.profiles
      case .loading, .unavailable, .error: return lastKnownSnapshot?.profiles ?? []
      }
    }

    /// The profiles in the order that the list shows.
    var sortedProfiles: [RemappingProfile] {
      screen.listSort.sorted(
        profiles,
        lastUsed: ProfileListSort.lastUsed(in: currentSnapshot ?? lastKnownSnapshot)
      )
    }

    /// The selected profile; the first profile when the selection is not in the library, unless the
    /// editor preserves the selected profile after its deletion.
    var selectedProfile: RemappingProfile? {
      if let selectedProfileID {
        if let current = profiles.first(where: { $0.id == selectedProfileID }) { return current }
        if let preservedEditorProfile, preservedEditorProfile.id == selectedProfileID {
          return preservedEditorProfile
        }
      }
      return profiles.first
    }

    /// The selected damaged profile or unusable library, or nil.
    var selectedRecoveryIssue: ApplicationServiceRemappingProfileIssue? {
      guard let selectedRecoveryIssueID else { return nil }
      return currentSnapshot?.profileIssues.first { $0.id == selectedRecoveryIssueID }
    }

    /// The profile list column: the loading state, the load error with Try Again, or the rows.
    var profileList: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        switch viewModel.remappingState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string("ui.profiles.loading")
          ).padding(.horizontal, 14)
        case .unavailable(let message), .error(let message):
          VStack(alignment: .leading, spacing: OJDSpacing.small) {
            Text(
              OJDLocalized.string("ui.profiles.loadError")
            ).font(.caption.weight(.semibold))
            Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
              .fixedSize(horizontal: false, vertical: true)
            Button(
              OJDLocalized.string("action.tryAgain"),
              action: refreshProfiles
            ).help(OJDLocalized.string("ui.profiles.tryAgainHelp"))
          }.padding(.horizontal, 14)
        case .available:
          if !profiles.isEmpty || !(currentSnapshot?.profileIssues.isEmpty ?? true) {
            if profiles.count > 1 {
              Picker(OJDLocalized.string("ui.profiles.sort"), selection: $screen.listSort) {
                ForEach(ProfileListSort.allCases) { sort in
                  Text(OJDLocalized.string(sort.titleKey)).tag(sort)
                }
              }.help(OJDLocalized.string("ui.profiles.sortHelp")).padding(.horizontal, 14)
            }
            profileListRows
          }
        }
        Spacer(minLength: 0)
      }
    }

    /// The rows of the profiles, then those of the damaged entries.
    var profileListRows: some View {
      List(selection: profileListSelection) {
        ForEach(sortedProfiles) { profile in
          HStack(spacing: OJDSpacing.small) {
            OJDListGlyphSlot {
              let semanticState: SemanticState = isActive(profile) ? .active : .inactive
              OJDSystemSymbol(
                name: semanticState.presentation.symbolName,
                fallback: isActive(profile)
                  ? OJDLocalized.string("ui.profiles.active")
                  : OJDLocalized.string("ui.profiles.notActive")
              ).foregroundColor(Color(semanticState.presentation.tone.color))
            }
            VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
              Text(profile.name).lineLimit(1)
              Text(
                ProfileScopeCaption.text(
                  for: profile.applicationScope,
                  assignments: assignmentCountLabel(profile.bindings.count),
                  resolveName: screen.applicationNames.name(for:)
                )
              ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(ProfileListSelection.profile(profile.id))
            .ojdAccessibilityLabel(profile.name).ojdAccessibilityValue(
              profileAccessibilityValue(profile)
            )
        }
        ForEach(currentSnapshot?.profileIssues ?? []) { issue in
          let presentation = ProfileIssuePresentation(issue)
          HStack(spacing: OJDSpacing.small) {
            OJDListGlyphSlot {
              OJDSystemSymbol(
                name: issue.kind == .damagedProfile
                  ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
                fallback: OJDLocalized.string("status.needsAttention")
              ).foregroundColor(
                Color(
                  (issue.kind == .damagedProfile ? SemanticState.attention : .failure).presentation
                    .tone.color
                )
              )
            }
            VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
              Text(presentation.title).lineLimit(1)
              Text(presentation.code).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(ProfileListSelection.issue(issue.id)).ojdAccessibilityValue(
            presentation.accessibilityValue
          )
        }
      }.listStyle(InsetListStyle()).disabled(isMutationActive || library.profileRecoveryInFlight)
    }
  }

#endif
