#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {

    /// A binding to the list selection: a damaged entry wins over the selected profile.
    var profileListSelection: Binding<ProfileListSelection?> {
      Binding(
        get: {
          if let selectedRecoveryIssueID { return .issue(selectedRecoveryIssueID) }
          return selectedProfileID.map(ProfileListSelection.profile)
        },
        set: { selection in
          switch selection {
          case .profile(let profileID):
            selectedRecoveryIssueID = nil
            selectProfile(profileID)
          case .issue(let issueID): selectedRecoveryIssueID = issueID
          case nil: break
          }
        }
      )
    }

    /// The detail of the selection: the recovery detail of a damaged entry, the editor of a
    /// profile, or the state of the load.
    @ViewBuilder
    var profileDetail: some View {
      if let selectedRecoveryIssue {
        profileRecoveryDetail(selectedRecoveryIssue)
      } else if let selectedProfile {
        VStack(alignment: .leading, spacing: OJDSpacing.none) {
          refreshStatus
          if selectedProfile.joyConPair != nil { joyConPairControls(selectedProfile) }
          ProfileEditorView(
            profile: selectedProfile,
            capabilities: ProfileCapabilityResolver.resolve(
              profile: selectedProfile,
              connectedDevices: connectedDevices,
              registry: screen.capabilityRegistry
            ) ?? .unknown,
            editor: screen.editor(
              for: selectedProfile,
              discardGeneration: navigation.discardGeneration
            ),
            viewModel: viewModel,
            library: library,
            isActive: isActive(selectedProfile),
            isEditingBlocked: profileEditorTransition.isEditingBlocked
              || profileLibraryNeedsRecovery,
            selectedSection: $screen.selectedEditorSection,
            onEditingStateChanged: { setEditorDirty($0) },
            onMutationStarted: { beginProfileMutation($0) },
            onMutationResult: { handleProfileMutationResult($0) }
          ).id(
            selectedProfile.id.uuidString + "-\(navigation.discardGeneration)"
              + "-\(profileEditorGeneration)"
          )
        }
      } else {
        switch viewModel.remappingState {
        case .loading:
          LoadingStateView(
            message: OJDLocalized.string("ui.profiles.loading")
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string("ui.profiles.unavailable"),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "ui.profiles.loadError"
            ),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .available: noProfilesState
        }
      }
    }

    /// The Delete or Reset Library detail of a damaged entry.
    ///
    /// - Parameter issue: The damaged profile or unusable library.
    /// - Returns: The detail of the entry.
    private func profileRecoveryDetail(
      _ issue: ApplicationServiceRemappingProfileIssue
    ) -> some View {
      let presentation = ProfileIssuePresentation(issue)
      return Form {
        Section(header: Text(presentation.titleWithCode)) {
          Text(presentation.message).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
            .ojdAccessibilityLabel(presentation.title)
            .ojdAccessibilityValue(presentation.accessibilityValue)
          if presentation.offersMigration {
            Button(OJDLocalized.string("ui.migrate.action")) { migrateStoredDocuments() }
              .disabled(library.profileRecoveryInFlight)
          }
          Button(
            OJDLocalized.string(
              issue.kind == .damagedProfile
                ? "ui.profiles.deleteDamagedButton" : "ui.profiles.resetLibraryButton"
            )
          ) {
            activeAlert =
              issue.kind == .damagedProfile
              ? .deleteDamagedProfile(issue.id) : .resetLibrary(issue.id)
          }.disabled(library.profileRecoveryInFlight)
        }
      }.ojdGroupedForm()
    }

    /// The Joy-Con pair row of a profile: Pair Joy-Cons, or Unpair Joy-Cons for each active pair.
    ///
    /// - Parameter profile: The profile that pairs Joy-Con controllers.
    /// - Returns: The row.
    @ViewBuilder
    func joyConPairControls(_ profile: RemappingProfile) -> some View {
      let sessions = currentSnapshot?.joyConPairs.filter { $0.profileID == profile.id } ?? []
      HStack(spacing: OJDSpacing.medium) {
        Text(OJDLocalized.string("ui.profiles.joyConPair")).font(
          .body.weight(.semibold)
        )
        if sessions.isEmpty {
          Button(
            OJDLocalized.string("ui.profiles.pairJoyCons")
          ) { pairingProfile = profile }.disabled(!hasAvailableJoyConPair || isProfileActionBlocked)
        } else {
          Text(OJDLocalized.string("ui.profiles.joyConPairActive")).font(
            .caption
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
          ForEach(sessions, id: \.sessionID) { session in
            Button(OJDLocalized.string("ui.profiles.unpairJoyCons")) {
              Task { @MainActor in
                profileActionError = await viewModel.unpairRemappingJoyCons(
                  sessionID: session.sessionID
                )
              }
            }.disabled(isProfileActionBlocked)
          }
        }
        if sessions.isEmpty, !hasAvailableJoyConPair {
          Text(OJDLocalized.string("ui.profiles.joyConPairNeedsBoth")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer()
      }.padding(.horizontal, 28).padding(.top, 10)
    }

    /// The snapshot of the available state, or the last snapshot.
    var currentSnapshot: ApplicationServiceRemappingSnapshotPayload? {
      if case .available(let snapshot) = viewModel.remappingState { return snapshot }
      return lastKnownSnapshot
    }

    /// Whether a left and a right Joy-Con are connected.
    var hasAvailableJoyConPair: Bool {
      connectedDevices.contains {
        JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .left
      }
        && connectedDevices.contains {
          JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .right
        }
    }

    /// The state that says there are no profiles.
    var noProfilesState: some View {
      EmptyStateView(
        symbol: "slider.horizontal.3",
        title: OJDLocalized.string("ui.profiles.none"),
        message: OJDLocalized.string("ui.profiles.createMessage")
      )
    }

    /// Returns the text for the number of assignments.
    ///
    /// - Parameter count: The number of assignments.
    /// - Returns: The text for the number of assignments.
    func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("ui.profiles.assignments", count: count)
    }

    /// Returns the text VoiceOver reads after a profile's name: the assignment count, with the
    /// active state for an active profile.
    ///
    /// - Parameter profile: The profile in the list.
    /// - Returns: The text VoiceOver reads after a profile's name: the assignment count, with the
    ///   active state for an active profile.
    func profileAccessibilityValue(_ profile: RemappingProfile) -> String {
      let count = assignmentCountLabel(profile.bindings.count)
      guard isActive(profile) else { return count }
      return OJDLocalized.formatted("ui.profiles.activeAssignmentCount", count)
    }

    /// The banner that says the profiles are refreshing, or that the state is unavailable or failed
    /// to refresh and the draft is kept.
    @ViewBuilder
    var refreshStatus: some View {
      switch viewModel.remappingState {
      case .loading:
        HStack(spacing: OJDSpacing.small) {
          ProgressView()
          Text(OJDLocalized.string("ui.profiles.refreshing"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(.horizontal, 28).padding(.top, 14)
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "ui.profiles.stateUnavailable"
          ),
          message: OJDLocalized.formatted(
            "ui.profiles.draftPreserved",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .error(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "ui.profiles.refreshError"
          ),
          message: OJDLocalized.formatted(
            "ui.profiles.draftPreserved",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .available: EmptyView()
      }
    }

  }

#endif
