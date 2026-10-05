#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {

    var selectedProfileID: UUID? {
      get { screen.selectedProfileID }
      nonmutating set { screen.selectedProfileID = newValue }
    }
    var selectedRecoveryIssueID: UUID? {
      get { screen.selectedRecoveryIssueID }
      nonmutating set { screen.selectedRecoveryIssueID = newValue }
    }
    var isCreatingProfile: Bool {
      get { screen.isCreatingProfile }
      nonmutating set { screen.isCreatingProfile = newValue }
    }
    var profileEditorTransition: ProfileEditorTransitionState {
      get { screen.editorTransition }
      nonmutating set { screen.editorTransition = newValue }
    }
    var activeAlert: ProfilesAlert? {
      get { screen.activeAlert }
      nonmutating set { screen.activeAlert = newValue }
    }
    var profileActionError: String? {
      get { screen.profileActionError }
      nonmutating set { screen.profileActionError = newValue }
    }
    var observedDiscardGeneration: Int {
      get { screen.observedDiscardGeneration }
      nonmutating set { screen.observedDiscardGeneration = newValue }
    }
    var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload? {
      get { screen.lastKnownSnapshot }
      nonmutating set { screen.lastKnownSnapshot = newValue }
    }
    var preservedEditorProfile: RemappingProfile? {
      get { screen.preservedEditorProfile }
      nonmutating set { screen.preservedEditorProfile = newValue }
    }
    var profileEditorGeneration: Int {
      get { screen.editorGeneration }
      nonmutating set { screen.editorGeneration = newValue }
    }
    var pairingProfile: RemappingProfile? {
      get { screen.pairingProfile }
      nonmutating set { screen.pairingProfile = newValue }
    }
    var selectedEditorSection: ProfileEditorSection {
      get { screen.selectedEditorSection }
      nonmutating set { screen.selectedEditorSection = newValue }
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        if let profileActionError {
          ProfileActionErrorBanner(message: profileActionError) { self.profileActionError = nil }
        }
        GeometryReader { proxy in
          if WorkspaceListDetailPolicy.layout(for: proxy.size.width) == .stacked {
            VStack(spacing: 0) {
              profileList.frame(
                height: WorkspaceListDetailPolicy.compactListHeight(
                  itemCount: profiles.count + (currentSnapshot?.profileIssues.count ?? 0),
                  availableHeight: proxy.size.height
                )
              )
              Divider()
              profileDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          } else {
            HStack(spacing: 0) {
              profileList.frame(width: WorkspaceListDetailPolicy.listWidth(for: proxy.size.width))
                .frame(maxHeight: .infinity, alignment: .topLeading)
              Divider()
              profileDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
      }
      // Older macOS presents only the last of several sheets attached to one view (unverified on
      // macOS 12), so each sheet hangs off its own sibling background view.
      .background(
        EmptyView().sheet(isPresented: $screen.isCreatingProfile) {
          ProfileNameSheet(
            title: OJDLocalized.string("profiles.new"),
            initialName: OJDLocalized.string("profiles.defaultName"),
            devices: connectedDevices
          ) { name, device, scope in createProfile(named: name, for: device, scope: scope) }
        }
      ).background(
        EmptyView().sheet(item: $screen.pairingProfile) { profile in
          ProfileJoyConPairSheet(profile: profile, devices: connectedDevices) { left, right in
            Task { @MainActor in
              profileActionError = await viewModel.pairRemappingJoyCons(
                left: left,
                right: right,
                profileID: profile.id
              )
            }
          }
        }
      ).alert(item: $screen.activeAlert) { alert in
        switch alert {
        case .delete(let id):
          Alert(
            title: Text(OJDLocalized.string("profiles.deleteTitle")),
            message: Text(
              OJDLocalized.string(
                "profiles.deleteMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("common.delete"))
            ) { deleteProfile(id) },
            secondaryButton: .cancel { activeAlert = nil }
          )
        case .discard:
          Alert(
            title: Text(
              OJDLocalized.string("settings.discardTitle")
            ),
            message: Text(
              OJDLocalized.string(
                "profiles.discardMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("settings.discardAction"))
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
              OJDLocalized.string("profiles.damagedProfile")
            ),
            message: Text(
              OJDLocalized.string(
                "profiles.recoveryBackupMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("common.delete"))
            ) { recoverProfileIssue(issueID, resetLibrary: false) },
            secondaryButton: .cancel { activeAlert = nil }
          )
        case .resetLibrary(let issueID):
          Alert(
            title: Text(
              OJDLocalized.string(
                "profiles.damagedLibrary"
              )
            ),
            message: Text(
              OJDLocalized.string(
                "profiles.recoveryBackupMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("profiles.resetLibraryAction"))
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

    var profiles: [RemappingProfile] {
      switch viewModel.remappingState {
      case .available(let snapshot): return snapshot.profiles
      case .loading, .unavailable, .error: return lastKnownSnapshot?.profiles ?? []
      }
    }

    var selectedProfile: RemappingProfile? {
      if let selectedProfileID {
        if let current = profiles.first(where: { $0.id == selectedProfileID }) { return current }
        if let preservedEditorProfile, preservedEditorProfile.id == selectedProfileID {
          return preservedEditorProfile
        }
      }
      return profiles.first
    }

    var selectedRecoveryIssue: ApplicationServiceRemappingProfileIssue? {
      guard let selectedRecoveryIssueID else { return nil }
      return currentSnapshot?.profileIssues.first { $0.id == selectedRecoveryIssueID }
    }

    var profileList: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text(OJDLocalized.string("common.profiles")).font(.headline)
            .lineLimit(1).layoutPriority(1)
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("profiles.new")
          ) { isCreatingProfile = true }.disabled(isProfileActionBlocked)
          OJDCompactSymbolButton(
            symbolName: "square.and.arrow.down",
            label: OJDLocalized.string("profiles.import"),
            action: importProfile
          ).disabled(isProfileActionBlocked)
        }.padding(.horizontal, 14).padding(.top, 18)

        switch viewModel.remappingState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string("profiles.loading")
          ).padding(.horizontal, 14)
        case .unavailable(let message), .error(let message):
          VStack(alignment: .leading, spacing: 6) {
            Text(
              OJDLocalized.string("profiles.loadError")
            ).font(.caption.weight(.semibold))
            Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
              .fixedSize(horizontal: false, vertical: true)
            Button(
              OJDLocalized.string("common.tryAgain"),
              action: refreshProfiles
            )
          }.padding(.horizontal, 14)
        case .available:
          if !profiles.isEmpty || !(currentSnapshot?.profileIssues.isEmpty ?? true) {
            profileListRows
          }
        }
        Spacer(minLength: 0)
      }.background(Color(NSColor.controlBackgroundColor))
    }

    var profileListRows: some View {
      List(selection: profileListSelection) {
        ForEach(profiles) { profile in
          HStack(spacing: 8) {
            OJDListGlyphSlot {
              let semanticState: SemanticState = isActive(profile) ? .active : .inactive
              OJDSystemSymbol(
                name: semanticState.presentation.symbolName,
                fallback: isActive(profile)
                  ? OJDLocalized.string("profiles.active")
                  : OJDLocalized.string("profiles.notActive")
              ).foregroundColor(Color(semanticState.presentation.tone.color))
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(profile.name).lineLimit(1)
              Text(assignmentCountLabel(profile.bindings.count)).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(ProfileListSelection.profile(profile.id))
            .ojdAccessibilityLabel(profile.name).ojdAccessibilityValue(
              profileAccessibilityValue(profile)
            )
        }
        ForEach(currentSnapshot?.profileIssues ?? []) { issue in
          HStack(spacing: 8) {
            OJDListGlyphSlot {
              OJDSystemSymbol(
                name: issue.kind == .damagedProfile
                  ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
                fallback: OJDLocalized.string("common.needsAttention")
              ).foregroundColor(
                Color(
                  (issue.kind == .damagedProfile ? SemanticState.attention : .failure).presentation
                    .tone.color
                )
              )
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(
                OJDLocalized.string(
                  issue.kind == .damagedProfile
                    ? "profiles.damagedProfile" : "profiles.damagedLibrary"
                )
              ).lineLimit(1)
              Text(OJDLocalized.string("common.needsAttention")).font(
                .caption
              ).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
            Spacer(minLength: 0)
          }.padding(.vertical, 4).tag(ProfileListSelection.issue(issue.id)).ojdAccessibilityValue(
            profileIssueMessage(issue)
          )
        }
      }.listStyle(SidebarListStyle()).disabled(isMutationActive || library.profileRecoveryInFlight)
    }
  }

#endif
