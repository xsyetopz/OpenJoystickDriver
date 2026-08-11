#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfilesView: View {
    @ObservedObject var viewModel: RuntimeViewModel
    @ObservedObject var navigation: SettingsNavigationModel
    @State private var selectedProfileID: UUID?
    @State private var isCreatingProfile = false
    @State private var editorHasUnsavedChanges = false
    @State private var activeAlert: ProfilesAlert?
    @State private var profileActionError: String?
    @State private var observedDiscardGeneration = 0
    @State private var lastKnownSnapshot: ApplicationServiceRemappingSnapshotPayload?
    @State private var preservedEditorProfile: RemappingProfile?

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        if let profileActionError {
          ProfileActionErrorBanner(message: profileActionError) { self.profileActionError = nil }
        }
        GeometryReader { proxy in
          HStack(spacing: 0) {
            profileList.frame(width: profileListWidth(for: proxy.size.width)).frame(
              maxHeight: .infinity,
              alignment: .topLeading
            )
            Divider()
            profileDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }.sheet(isPresented: $isCreatingProfile) {
        ProfileNameSheet(
          title: "New profile",
          initialName: "My controller",
          devices: connectedDevices
        ) { name, device in createProfile(named: name, for: device) }
      }.alert(item: $activeAlert) { alert in
        switch alert {
        case .delete(let id):
          Alert(
            title: Text("Delete profile?"),
            message: Text("This removes the profile from OpenJoystickDriver."),
            primaryButton: .destructive(Text("Delete")) {
              Task { @MainActor in await viewModel.deleteRemappingProfile(id: id) }
              activeAlert = nil
            },
            secondaryButton: .cancel { activeAlert = nil }
          )
        case .discard(let id):
          Alert(
            title: Text("Discard unsaved changes?"),
            message: Text("Your changes to this profile have not been saved."),
            primaryButton: .destructive(Text("Discard Changes")) {
              setEditorDirty(false)
              activeAlert = nil
              selectedProfileID = id
            },
            secondaryButton: .cancel { activeAlert = nil }
          )
        }
      }.onAppear {
        if case .available(let snapshot) = viewModel.remappingState { lastKnownSnapshot = snapshot }
        if observedDiscardGeneration != navigation.discardGeneration {
          editorHasUnsavedChanges = false
          observedDiscardGeneration = navigation.discardGeneration
        }
        selectFirstProfileIfNeeded()
        navigation.setProfilesEditorDirty(editorHasUnsavedChanges)
      }.onReceive(viewModel.$mutationState) { handleProfileMutation($0) }.onReceive(
        navigation.$discardGeneration
      ) { generation in
        observedDiscardGeneration = generation
        if editorHasUnsavedChanges { setEditorDirty(false) }
      }.onReceive(viewModel.$remappingState) { state in
        if case .available(let snapshot) = state {
          if editorHasUnsavedChanges, let selectedProfileID,
            !snapshot.profiles.contains(where: { $0.id == selectedProfileID }),
            let previous = lastKnownSnapshot?.profiles.first(where: { $0.id == selectedProfileID })
          {
            preservedEditorProfile = previous
          }
          lastKnownSnapshot = snapshot
          selectFirstProfileIfNeeded()
        }
      }
    }

    private var profiles: [RemappingProfile] {
      switch viewModel.remappingState {
      case .available(let snapshot): return snapshot.profiles
      case .loading, .unavailable, .error: return lastKnownSnapshot?.profiles ?? []
      }
    }

    private func profileListWidth(for availableWidth: CGFloat) -> CGFloat {
      min(220, max(168, availableWidth * 0.25))
    }

    private var selectedProfile: RemappingProfile? {
      if let selectedProfileID {
        if let current = profiles.first(where: { $0.id == selectedProfileID }) { return current }
        if let preservedEditorProfile, preservedEditorProfile.id == selectedProfileID {
          return preservedEditorProfile
        }
      }
      return profiles.first
    }

    private var profileList: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Profiles").font(.headline)
          Spacer()
          Button(
            action: { isCreatingProfile = true },
            label: {
              OJDSystemSymbol(name: "plus", fallback: "+").ojdAccessibilityLabel("New profile")
                .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
            }
          ).buttonStyle(BorderlessButtonStyle()).disabled(
            connectedDevices.isEmpty || isMutationActive
          )
        }.padding(.horizontal, 14).padding(.top, 18)

        switch viewModel.remappingState {
        case .loading: LoadingStateView(message: "Loading profiles…").padding(.horizontal, 14)
        case .unavailable(let message), .error(let message):
          VStack(alignment: .leading, spacing: 6) {
            Text("Profiles could not be loaded.").font(.caption.weight(.semibold))
            Text(message).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
              .fixedSize(horizontal: false, vertical: true)
            Button("Try again", action: refreshProfiles)
          }.padding(.horizontal, 14)
        case .available:
          if profiles.isEmpty { noProfilesState.padding(.horizontal, 14) } else { profileListRows }
        }
        Spacer(minLength: 0)
      }.background(Color(NSColor.controlBackgroundColor))
    }

    private var profileListRows: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(profiles) { profile in
            Button(
              action: { selectProfile(profile.id) },
              label: {
                HStack(spacing: 8) {
                  OJDSystemSymbol(
                    name: isActive(profile) ? "checkmark.circle.fill" : "circle",
                    fallback: isActive(profile) ? "Active" : "○"
                  ).foregroundColor(Color(NSColor.controlAccentColor))
                  VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).lineLimit(1)
                    Text("\(profile.bindings.count) assignments").font(.caption).foregroundColor(
                      Color(NSColor.secondaryLabelColor)
                    )
                  }
                  Spacer(minLength: 0)
                }.padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
              }
            ).buttonStyle(ProfileListButtonStyle(selected: selectedProfile?.id == profile.id))
              .ojdAccessibilityLabel(profile.name).ojdAccessibilitySelection(
                selectedProfile?.id == profile.id
              ).ojdAccessibilityValue(
                "\(profile.bindings.count) assignments\(isActive(profile) ? ", active" : "")"
              )
          }
        }.padding(.horizontal, 8)
      }
    }

    @ViewBuilder private var profileDetail: some View {
      if let selectedProfile {
        VStack(alignment: .leading, spacing: 0) {
          refreshStatus
          ProfileEditorView(
            profile: selectedProfile,
            viewModel: viewModel,
            isActive: isActive(selectedProfile),
            onDelete: { activeAlert = .delete(selectedProfile.id) },
            onEditingStateChanged: { setEditorDirty($0) }
          ).id("\(selectedProfile.id.uuidString)-\(navigation.discardGeneration)")
        }
      } else {
        switch viewModel.remappingState {
        case .loading: LoadingStateView(message: "Loading profiles…").padding(28)
        case .unavailable(let message):
          ServiceFailureStateView(
            title: "Profiles unavailable",
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .error(let message):
          ServiceFailureStateView(
            title: "Could not load profiles",
            message: message,
            retry: refreshProfiles
          ).padding(28)
        case .available: noProfilesState.padding(28)
        }
      }
    }

    private var noProfilesState: some View {
      VStack(alignment: .leading, spacing: 12) {
        EmptyStateView(
          symbol: "plus.circle",
          title: "No profiles",
          message: connectedDevices.isEmpty
            ? "Connect a controller to create a profile."
            : "Create a profile to start assigning controls."
        )
        Button("Create profile…") { isCreatingProfile = true }.disabled(
          connectedDevices.isEmpty || isMutationActive
        )
      }
    }

    @ViewBuilder private var refreshStatus: some View {
      switch viewModel.remappingState {
      case .loading:
        HStack(spacing: 8) {
          OJDLoadingIndicator()
          Text("Refreshing profile state…").foregroundColor(Color(NSColor.secondaryLabelColor))
        }.padding(.horizontal, 28).padding(.top, 14)
      case .unavailable(let message):
        ServiceFailureStateView(
          title: "Profile state is unavailable",
          message: "Your current draft is preserved. \(message)",
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .error(let message):
        ServiceFailureStateView(
          title: "Could not refresh profile state",
          message: "Your current draft is preserved. \(message)",
          retry: refreshProfiles
        ).padding(.horizontal, 28).padding(.top, 14)
      case .available: EmptyView()
      }
    }

    private func selectFirstProfileIfNeeded() {
      if selectedProfileID == nil { selectedProfileID = profiles.first?.id }
    }

    private func refreshProfiles() { Task { @MainActor in await viewModel.refresh() } }

    private func selectProfile(_ profileID: UUID) {
      guard profileID != selectedProfileID else { return }
      guard editorHasUnsavedChanges else {
        preservedEditorProfile = nil
        selectedProfileID = profileID
        return
      }
      activeAlert = .discard(profileID)
    }

    private func setEditorDirty(_ dirty: Bool) {
      editorHasUnsavedChanges = dirty
      if !dirty { preservedEditorProfile = nil }
      navigation.setProfilesEditorDirty(dirty)
    }

    private func isActive(_ profile: RemappingProfile) -> Bool {
      let snapshot: ApplicationServiceRemappingSnapshotPayload?
      switch viewModel.remappingState {
      case .available(let current): snapshot = current
      case .loading, .unavailable, .error: snapshot = lastKnownSnapshot
      }
      guard let snapshot else { return false }
      return snapshot.activeProfiles.contains { $0.profileID == profile.id }
    }

    private func createProfile(named name: String, for device: ApplicationServiceDeviceDescription)
    {
      let profile = RemappingProfile(
        name: name,
        device: RemappingDeviceScope(vendorID: device.vendorID, productID: device.productID),
        applicationScope: .global,
        bindings: []
      )
      Task { @MainActor in await viewModel.createRemappingProfile(profile) }
    }

    private func handleProfileMutation(_ mutation: RuntimeMutationState) {
      guard let operation = viewModel.lastMutationOperation else { return }
      switch mutation {
      case .completed(let completedOperation) where completedOperation == operation:
        profileActionError = nil
        switch completedOperation {
        case .create(let profileID): selectProfile(profileID)
        case .delete(let profileID) where selectedProfileID == profileID:
          selectedProfileID = profiles.first?.id
        default: break
        }
      case .error(let message) where isProfileAction(operation): profileActionError = message
      case .conflict where isProfileAction(operation):
        profileActionError =
          viewModel.lastError ?? "This profile action could not be completed. Try again."
      default: break
      }
    }

    private func isProfileAction(_ operation: RuntimeMutationOperation) -> Bool {
      switch operation {
      case .create, .delete, .activate, .deactivate: return true
      case .update, .importProfile: return false
      }
    }

    private var isMutationActive: Bool {
      if viewModel.activeMutationOperation != nil { return true }
      if case .saving = viewModel.mutationState { return true }
      return false
    }

    private var connectedDevices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }
  }

  private enum ProfilesAlert: Identifiable {
    case delete(UUID)
    case discard(UUID)

    var id: String {
      switch self {
      case .delete(let profileID): return "delete-\(profileID.uuidString)"
      case .discard(let profileID): return "discard-\(profileID.uuidString)"
      }
    }
  }

#endif
