#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI
  import UniformTypeIdentifiers

  extension ProfilesView {

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

    @ViewBuilder
    var profileDetail: some View {
      if let selectedRecoveryIssue {
        profileRecoveryDetail(selectedRecoveryIssue).padding(28)
      } else if let selectedProfile {
        VStack(alignment: .leading, spacing: 0) {
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
            onDelete: { activeAlert = .delete(selectedProfile.id) },
            onExport: { exportProfile($0) },
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
            message: OJDLocalized.string("profiles.loading")
          ).padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string("profiles.unavailable"),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: OJDLocalized.string(
              "profiles.loadError"
            ),
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .available: noProfilesState.padding(28)
        }
      }
    }

    private func profileRecoveryDetail(
      _ issue: ApplicationServiceRemappingProfileIssue
    ) -> some View {
      VStack(alignment: .leading, spacing: 14) {
        OJDSystemSymbol(
          name: issue.kind == .damagedProfile
            ? "exclamationmark.triangle.fill" : "xmark.octagon.fill",
          fallback: OJDLocalized.string("common.needsAttention")
        ).font(.largeTitle).foregroundColor(
          Color(
            (issue.kind == .damagedProfile ? SemanticState.attention : .failure).presentation.tone
              .color
          )
        ).accessibilityHidden(true)
        Text(
          OJDLocalized.string(
            issue.kind == .damagedProfile ? "profiles.damagedProfile" : "profiles.damagedLibrary"
          )
        ).font(.title.weight(.semibold))
        Text(profileIssueMessage(issue)).foregroundColor(Color(NSColor.secondaryLabelColor))
          .fixedSize(horizontal: false, vertical: true)
        Button(
          OJDLocalized.string(
            issue.kind == .damagedProfile
              ? "profiles.deleteDamagedButton" : "profiles.resetLibraryButton"
          )
        ) {
          activeAlert =
            issue.kind == .damagedProfile
            ? .deleteDamagedProfile(issue.id) : .resetLibrary(issue.id)
        }.disabled(library.profileRecoveryInFlight)
        Spacer()
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ojdAccessibilityLabel(
          OJDLocalized.string(
            issue.kind == .damagedProfile ? "profiles.damagedProfile" : "profiles.damagedLibrary"
          )
        ).ojdAccessibilityValue(profileIssueMessage(issue))
    }

    func profileIssueMessage(_ issue: ApplicationServiceRemappingProfileIssue) -> String {
      OJDLocalized.string(
        issue.kind == .damagedProfile
          ? "profiles.damagedProfileMessage" : "profiles.damagedSelectionsMessage"
      )
    }

    @ViewBuilder
    func joyConPairControls(_ profile: RemappingProfile) -> some View {
      let sessions = currentSnapshot?.joyConPairs.filter { $0.profileID == profile.id } ?? []
      HStack(spacing: 10) {
        Text(OJDLocalized.string("profiles.joyConPair")).font(
          .caption.weight(.semibold)
        )
        if sessions.isEmpty {
          Button(
            OJDLocalized.string("profiles.pairJoyCons")
          ) { pairingProfile = profile }.disabled(!hasAvailableJoyConPair || isProfileActionBlocked)
        } else {
          Text(OJDLocalized.string("profiles.joyConPairActive")).font(
            .caption
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
          ForEach(sessions, id: \.sessionID) { session in
            Button(OJDLocalized.string("profiles.unpairJoyCons")) {
              Task { @MainActor in
                profileActionError = await viewModel.unpairRemappingJoyCons(
                  sessionID: session.sessionID
                )
              }
            }.disabled(isProfileActionBlocked)
          }
        }
        Spacer()
      }.padding(.horizontal, 28).padding(.top, 10)
    }

    var currentSnapshot: ApplicationServiceRemappingSnapshotPayload? {
      if case .available(let snapshot) = viewModel.remappingState { return snapshot }
      return lastKnownSnapshot
    }

    var hasAvailableJoyConPair: Bool {
      connectedDevices.contains {
        JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .left
      }
        && connectedDevices.contains {
          JoyConHalf(vendorID: $0.vendorID, productID: $0.productID) == .right
        }
    }

    var noProfilesState: some View {
      VStack(alignment: .leading, spacing: 12) {
        EmptyStateView(
          symbol: "plus.circle",
          title: OJDLocalized.string("profiles.none"),
          message: OJDLocalized.string(
            "profiles.createMessage"
          )
        )
        Button(OJDLocalized.string("profiles.create")) {
          isCreatingProfile = true
        }.disabled(isProfileActionBlocked)
      }
    }

    func assignmentCountLabel(_ count: Int) -> String {
      OJDLocalized.plural("profiles.assignments", count: count)
    }

    func profileAccessibilityValue(_ profile: RemappingProfile) -> String {
      let count = assignmentCountLabel(profile.bindings.count)
      guard isActive(profile) else { return count }
      return OJDLocalized.formatted("profiles.activeAssignmentCount", count)
    }

    @ViewBuilder
    var refreshStatus: some View {
      switch viewModel.remappingState {
      case .loading:
        HStack(spacing: 8) {
          ProgressView()
          Text(OJDLocalized.string("profiles.refreshing"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(.horizontal, 28).padding(.top, 14)
      case .unavailable(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "profiles.stateUnavailable"
          ),
          message: OJDLocalized.formatted(
            "profiles.draftPreserved",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .error(let message):
        ServiceFailureStateView(
          title: OJDLocalized.string(
            "profiles.refreshError"
          ),
          message: OJDLocalized.formatted(
            "profiles.draftPreserved",
            message
          ),
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .available: EmptyView()
      }
    }

  }

#endif
