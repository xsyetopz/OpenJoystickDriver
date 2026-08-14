#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Profile editor

  struct ProfileEditorView: View {
    let profile: RemappingProfile
    @ObservedObject var viewModel: RuntimeViewModel
    let isActive: Bool
    let onDelete: () -> Void
    let onEditingStateChanged: (Bool) -> Void

    @State private var draft: RuntimeProfileDraft
    @State private var expectedCurrent: RemappingProfile
    @State private var activeSheet: ProfileEditorSheet?
    @State private var showingConflict = false
    @State private var localError: String?
    @State private var saveError: String?
    @State private var saveInFlight = false
    @State private var pendingUpdateOperation: RuntimeMutationOperation?

    init(
      profile: RemappingProfile,
      viewModel: RuntimeViewModel,
      isActive: Bool,
      onDelete: @escaping () -> Void,
      onEditingStateChanged: @escaping (Bool) -> Void
    ) {
      self.profile = profile
      self.viewModel = viewModel
      self.isActive = isActive
      self.onDelete = onDelete
      self.onEditingStateChanged = onEditingStateChanged
      _draft = State(initialValue: RuntimeProfileDraft(profile: profile))
      _expectedCurrent = State(initialValue: profile)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        editorHeader
        Divider()
        assignmentContent
        Divider()
        editorFooter
      }.sheet(item: $activeSheet) { sheet in
        switch sheet {
        case .capture:
          CaptureAssignmentSheet(viewModel: viewModel) { source, destination in
            addBinding(source: source, destination: destination)
          }
        case .adjustment(let binding):
          AxisAdjustmentSheet(binding: binding) { tuning in
            updateAxisTuning(tuning, for: binding.id)
          }
        }
      }.onReceive(viewModel.$mutationState) { mutation in handleMutation(mutation) }.onAppear {
        reportEditingState()
      }
    }

    private var editorHeader: some View {
      VStack(alignment: .leading, spacing: 10) {
        TextField(
          OJDLocalized.string("common.profileName", fallback: "Profile name"),
          text: nameBinding
        ).font(.headline.weight(.semibold)).textFieldStyle(PlainTextFieldStyle()).frame(
          maxWidth: .infinity,
          alignment: .leading
        ).ojdAccessibilityLabel(OJDLocalized.string("common.profileName", fallback: "Profile name"))
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Button(OJDLocalized.string("common.duplicate", fallback: "Duplicate")) {
            duplicateProfile()
          }.disabled(isMutationActive)
          if isActive {
            Button(OJDLocalized.string("common.deactivate", fallback: "Deactivate")) {
              guard !isMutationActive else { return }
              Task { @MainActor in await viewModel.deactivateRemappingProfile(profileID: profile.id)
              }
            }.disabled(isMutationActive)
          } else {
            Button(OJDLocalized.string("common.setActive", fallback: "Set active")) {
              guard !isMutationActive else { return }
              Task { @MainActor in await viewModel.activateRemappingProfile(id: profile.id) }
            }.disabled(isMutationActive)
          }
          Spacer(minLength: 0)
        }
        HStack(spacing: 12) {
          Text(RuntimePresentation.profileScopeLabel(profile.applicationScope)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          Text("·").foregroundColor(Color(NSColor.tertiaryLabelColor))
          Text(
            isActive
              ? OJDLocalized.string("profiles.active", fallback: "Active")
              : OJDLocalized.string("profiles.notActive", fallback: "Not active")
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        if showingConflict {
          ConflictBanner(
            reload: {
              showingConflict = false
              Task { @MainActor in
                await viewModel.refresh()
                if case .available(let snapshot) = viewModel.remappingState,
                  let latest = snapshot.profiles.first(where: { $0.id == profile.id })
                {
                  expectedCurrent = latest
                  draft = RuntimeProfileDraft(profile: latest)
                  saveError = nil
                  reportEditingState()
                }
              }
            },
            keepEditing: { showingConflict = false }
          )
        }
      }.padding(28)
    }

    private var assignmentContent: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .firstTextBaseline) {
            Text(OJDLocalized.string("common.assignments", fallback: "Assignments")).font(.headline)
            Spacer()
            Button(OJDLocalized.string("common.addAssignment", fallback: "Add assignment")) {
              activeSheet = .capture
            }
          }
          if draft.profile.bindings.isEmpty {
            EmptyStateView(
              symbol: "plus.circle",
              title: OJDLocalized.string("profiles.noAssignments", fallback: "No assignments yet"),
              message: OJDLocalized.string(
                "profiles.assignmentInstructions",
                fallback:
                  "Add a controller control, then choose its keyboard or pointer destination."
              )
            )
          } else {
            ForEach(bindingGroups, id: \.title) { group in
              AssignmentGroupView(
                title: group.title,
                bindings: group.bindings,
                draft: $draft,
                onRemove: removeBinding,
                onError: { localError = $0 },
                onAdjust: { activeSheet = .adjustment($0) },
                onEditingStateChanged: {
                  localError = nil
                  saveError = nil
                  reportEditingState()
                }
              )
            }
          }
          if let error = draftError {
            Text(error).foregroundColor(Color(NSColor.systemRed)).fixedSize(
              horizontal: false,
              vertical: true
            ).ojdAccessibilityLabel(
              OJDLocalized.string("profiles.assignmentError", fallback: "Assignment error")
            )
          }
        }.padding(28)
      }
    }

    private var editorFooter: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let localError {
          Text(localError).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack(spacing: 10) {
          OJDDestructiveButton(action: onDelete) {
            Text(OJDLocalized.string("common.delete", fallback: "Delete"))
          }.disabled(isMutationActive)
          Spacer(minLength: 8)
          saveStatusView
          Button(OJDLocalized.string("common.save", fallback: "Save")) { save() }.disabled(
            draft.profile == expectedCurrent || saveInFlight || isMutationActive
          )
        }
      }.padding(.horizontal, 28).padding(.vertical, 14)
    }

    @ViewBuilder private var saveStatusView: some View {
      HStack(spacing: 6) {
        if saveStatus == .saving { OJDLoadingIndicator() }
        Text(saveStatus.label).foregroundColor(saveStatus.color)
      }.frame(minHeight: 28).ojdAccessibilityLabel(
        OJDLocalized.string("profiles.saveStatus", fallback: "Profile save status")
      ).ojdAccessibilityValue(saveStatus.accessibilityValue)
    }

    private var isMutationActive: Bool {
      if saveInFlight { return true }
      if viewModel.activeMutationOperation != nil { return true }
      if case .saving = viewModel.mutationState { return true }
      return false
    }

    private var saveStatus: ProfileSaveStatus {
      if saveInFlight { return .saving }
      if saveError != nil { return .error }
      if draft.profile != expectedCurrent { return .unsaved }
      return .saved
    }

    private var nameBinding: Binding<String> {
      Binding(
        get: { draft.profile.name },
        set: { newValue in
          draft = replacingName(newValue)
          saveError = nil
          reportEditingState()
        }
      )
    }

    private var draftError: String? { localError }

    private var bindingGroups: [BindingGroup] {
      let grouped = Dictionary(grouping: draft.profile.bindings) { sourceGroup(for: $0.source) }
      return BindingGroup.Order.allCases.compactMap { order in
        guard let bindings = grouped[order.title], !bindings.isEmpty else { return nil }
        return BindingGroup(title: order.title, bindings: bindings)
      }
    }

    private func sourceGroup(for source: RemappingSource) -> String {
      switch source {
      case .button(let button):
        switch button {
        case .leftShoulder, .rightShoulder:
          return OJDLocalized.string("profiles.sectionShoulders", fallback: "Shoulders")
        case .leftStick, .rightStick:
          return OJDLocalized.string("profiles.sectionStickClicks", fallback: "Stick clicks")
        case .start, .back, .guide, .share, .options, .touchpad, .auxiliary1, .auxiliary2,
          .auxiliary3, .auxiliary4, .auxiliary5, .auxiliary6, .auxiliary7, .auxiliary8:
          return OJDLocalized.string("profiles.sectionSystemControls", fallback: "System controls")
        default: return OJDLocalized.string("profiles.sectionFaceButtons", fallback: "Face buttons")
        }
      case .dpad: return OJDLocalized.string("profiles.sectionDpad", fallback: "D-pad")
      case .axis, .axisDirection:
        switch source {
        case .axis(.leftTrigger), .axis(.rightTrigger), .axisDirection(.leftTrigger, _),
          .axisDirection(.rightTrigger, _):
          return OJDLocalized.string("profiles.sectionTriggers", fallback: "Triggers")
        default: return OJDLocalized.string("profiles.sectionSticks", fallback: "Sticks")
        }
      }
    }

    private func replacingName(_ name: String) -> RuntimeProfileDraft {
      let value = RemappingProfile(
        schemaVersion: draft.profile.schemaVersion,
        id: draft.profile.id,
        name: name,
        device: draft.profile.device,
        applicationScope: draft.profile.applicationScope,
        bindings: draft.profile.bindings,
        chords: draft.profile.chords,
        sequences: draft.profile.sequences,
        layers: draft.profile.layers
      )
      return RuntimeProfileDraft(profile: value)
    }

    private func addBinding(source: RemappingSource, destination: RemappingDestination) {
      do {
        draft = try draft.addingBinding(source: source, destination: destination)
        activeSheet = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private func removeBinding(_ id: UUID) {
      do {
        draft = try draft.removingBinding(id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private func updateAxisTuning(_ tuning: RemappingAxisTuning, for id: UUID) {
      do {
        draft = try draft.settingAxisTuning(tuning, for: id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private func save() {
      guard draft.profile != expectedCurrent, !saveInFlight, !isMutationActive else { return }
      let operation = RuntimeMutationOperation.update(profileID: profile.id)
      pendingUpdateOperation = operation
      saveInFlight = true
      saveError = nil
      localError = nil
      reportEditingState()
      Task { @MainActor in
        await viewModel.updateRemappingProfile(draft.profile, expectedCurrent: expectedCurrent)
        reconcileSave(operation: operation)
      }
    }

    private func duplicateProfile() {
      guard !isMutationActive else { return }
      let source = draft.profile
      let duplicate = RemappingProfile(
        schemaVersion: source.schemaVersion,
        name: OJDLocalized.formatted("profiles.copyName", fallback: "%@ Copy", source.name),
        device: source.device,
        applicationScope: source.applicationScope,
        bindings: source.bindings,
        chords: source.chords,
        sequences: source.sequences,
        layers: source.layers
      )
      Task { @MainActor in await viewModel.createRemappingProfile(duplicate) }
    }

    private func reportEditingState() {
      onEditingStateChanged(saveInFlight || draft.profile != expectedCurrent)
    }

    private func handleMutation(_ mutation: RuntimeMutationState) {
      guard saveInFlight, pendingUpdateOperation == .update(profileID: profile.id),
        viewModel.lastMutationOperation == pendingUpdateOperation
      else { return }

      // ``updateRemappingProfile`` can be rejected before it starts when another profile action
      // wins the serialization race. That rejection is still this editor's result, even though
      // the unrelated operation remains active; do not leave the save spinner stuck. A rejection
      // for a different operation has a different lastMutationOperation and is ignored here.
      if let activeOperation = viewModel.activeMutationOperation,
        activeOperation != .update(profileID: profile.id)
      {
        guard case .error(let message) = mutation else { return }
        finishSave()
        localError = message
        saveError = message
        reportEditingState()
        return
      }
      guard viewModel.activeMutationOperation == nil else { return }

      switch mutation {
      case .conflict(let profileID) where profileID == profile.id:
        finishSave()
        showingConflict = true
        saveError = OJDLocalized.string(
          "profiles.changedElsewhere",
          fallback: "The profile changed elsewhere."
        )
      case .error(let message):
        finishSave()
        localError = message
        saveError = message
      case .succeeded(let profileID) where profileID == profile.id:
        finishSave()
        saveError = nil
        guard case .available(let snapshot) = viewModel.remappingState,
          let latest = snapshot.profiles.first(where: { $0.id == profile.id })
        else {
          localError = OJDLocalized.string(
            "profiles.savedButUnavailable",
            fallback: "The profile was saved, but its latest state is unavailable."
          )
          saveError = localError
          reportEditingState()
          return
        }
        expectedCurrent = latest
        draft = RuntimeProfileDraft(profile: latest)
      default: return
      }
      reportEditingState()
    }

    private func finishSave() {
      saveInFlight = false
      pendingUpdateOperation = nil
    }

    private func reconcileSave(operation: RuntimeMutationOperation) {
      guard saveInFlight, pendingUpdateOperation == operation else { return }
      guard viewModel.lastMutationOperation == operation else {
        // A same-profile overlap rejection belongs to another editor and must not clear this
        // editor's in-flight save. Leave reconciliation to the operation that owns this editor;
        // if no mutation is active, report the unexpected result instead of silently dropping it.
        guard viewModel.activeMutationOperation == nil else { return }
        finishSave()
        localError = OJDLocalized.string(
          "profiles.saveUnavailable",
          fallback: "The profile could not be saved. Finish the current action and try again."
        )
        saveError = localError
        reportEditingState()
        return
      }
      // Our own request may have been rejected while a different operation is still active. Its
      // correlated error is actionable now; waiting for the unrelated operation would overwrite
      // lastMutationOperation and strand this editor in a saving state.
      if let activeOperation = viewModel.activeMutationOperation, activeOperation != operation {
        guard case .error(let message) = viewModel.mutationState else { return }
        finishSave()
        localError = message
        saveError = message
        reportEditingState()
        return
      }
      guard viewModel.activeMutationOperation == nil else { return }
      handleMutation(viewModel.mutationState)
      guard saveInFlight else { return }
      finishSave()
      localError = OJDLocalized.string(
        "profiles.saveIncomplete",
        fallback: "The profile save did not finish. Try again."
      )
      saveError = localError
      reportEditingState()
    }
  }

  private enum ProfileEditorSheet: Identifiable {
    case capture
    case adjustment(RemappingBinding)

    var id: String {
      switch self {
      case .capture: return "capture"
      case .adjustment(let binding): return "adjustment-\(binding.id.uuidString)"
      }
    }
  }

  private enum ProfileSaveStatus: Equatable {
    case unsaved
    case saving
    case saved
    case error

    var label: String {
      switch self {
      case .unsaved: return OJDLocalized.string("profiles.unsaved", fallback: "Unsaved changes")
      case .saving: return OJDLocalized.string("profiles.saving", fallback: "Saving...")
      case .saved: return OJDLocalized.string("profiles.saved", fallback: "Saved")
      case .error: return OJDLocalized.string("profiles.saveFailed", fallback: "Save failed")
      }
    }

    var accessibilityValue: String { label }

    var color: Color {
      switch self {
      case .unsaved, .saving: return Color(NSColor.secondaryLabelColor)
      case .saved: return Color(NSColor.systemGreen)
      case .error: return Color(NSColor.systemRed)
      }
    }
  }

  private struct BindingGroup {
    let title: String
    let bindings: [RemappingBinding]

    enum Order: CaseIterable {
      case face
      case shoulders
      case dpad
      case sticks
      case triggers
      case clicks
      case system

      var title: String {
        switch self {
        case .face:
          return OJDLocalized.string("profiles.sectionFaceButtons", fallback: "Face buttons")
        case .shoulders:
          return OJDLocalized.string("profiles.sectionShoulders", fallback: "Shoulders")
        case .dpad: return OJDLocalized.string("profiles.sectionDpad", fallback: "D-pad")
        case .sticks: return OJDLocalized.string("profiles.sectionSticks", fallback: "Sticks")
        case .triggers: return OJDLocalized.string("profiles.sectionTriggers", fallback: "Triggers")
        case .clicks:
          return OJDLocalized.string("profiles.sectionStickClicks", fallback: "Stick clicks")
        case .system:
          return OJDLocalized.string("profiles.sectionSystemControls", fallback: "System controls")
        }
      }
    }
  }

  private struct AssignmentGroupView: View {
    let title: String
    let bindings: [RemappingBinding]
    @Binding var draft: RuntimeProfileDraft
    let onRemove: (UUID) -> Void
    let onError: (String) -> Void
    let onAdjust: (RemappingBinding) -> Void
    let onEditingStateChanged: () -> Void

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.subheadline.weight(.semibold)).padding(.bottom, 5)
          ForEach(bindings) { binding in
            AssignmentRow(
              binding: binding,
              draft: $draft,
              onRemove: onRemove,
              onError: onError,
              onAdjust: onAdjust,
              onEditingStateChanged: onEditingStateChanged
            )
            if binding.id != bindings.last?.id { Divider().padding(.leading, 2) }
          }
        }.padding(4)
      }
    }
  }

  private struct AssignmentRow: View {
    let binding: RemappingBinding
    @Binding var draft: RuntimeProfileDraft
    let onRemove: (UUID) -> Void
    let onError: (String) -> Void
    let onAdjust: (RemappingBinding) -> Void
    let onEditingStateChanged: () -> Void

    // Keep source and destination controls in separate full-width fields.  The profile detail
    // column is only about 500 points wide at the supported minimum once the profile list and
    // editor insets are accounted for; a two-picker row cannot safely fit there with Adjust... and
    // Remove controls, especially with larger text.
    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        Text(OJDLocalized.string("capture.controllerControl", fallback: "Controller control")).font(
          .caption
        ).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker("", selection: sourceBinding) {
          ForEach(SourceOption.options(including: binding.source), id: \.source) { option in
            Text(option.title).tag(option.source)
          }
        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).ojdAccessibilityLabel(
          OJDLocalized.string("capture.controllerControl", fallback: "Controller control")
        ).ojdAccessibilityValue(RuntimePresentation.sourceLabel(binding.source))

        HStack(alignment: .firstTextBaseline, spacing: 7) {
          OJDSystemSymbol(name: "arrow.right", fallback: "→").foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          Text(OJDLocalized.string("common.destination", fallback: "Destination")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Picker("", selection: destinationBinding) {
          ForEach(
            DestinationOption.options(for: binding.source, including: binding.destination),
            id: \.destination
          ) { option in Text(option.title).tag(option.destination) }
        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).ojdAccessibilityLabel(
          OJDLocalized.string("common.destination", fallback: "Destination")
        ).ojdAccessibilityValue(RuntimePresentation.destinationLabel(binding.destination))

        HStack(spacing: 8) {
          if binding.axisTuning != nil {
            Button(OJDLocalized.string("common.adjust", fallback: "Adjust...")) {
              onAdjust(binding)
            }.ojdAccessibilityLabel(
              OJDLocalized.formatted(
                "capture.adjust",
                fallback: "Adjust %@",
                RuntimePresentation.sourceLabel(binding.source)
              )
            )
          }
          Spacer(minLength: 0)
          Button(
            action: { onRemove(binding.id) },
            label: {
              OJDSystemSymbol(name: "minus.circle", fallback: "−").ojdAccessibilityHidden(true)
                .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
            }
          ).buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
            OJDLocalized.string("common.removeAssignment", fallback: "Remove assignment")
          ).ojdHelp(OJDLocalized.string("common.removeAssignment", fallback: "Remove assignment"))
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).ojdAccessibilityLabel(
        OJDLocalized.string("common.assignment", fallback: "Assignment")
      ).ojdAccessibilityValue(assignmentAccessibilityValue)
    }

    private var assignmentAccessibilityValue: String {
      let source = RuntimePresentation.sourceLabel(binding.source)
      let destination = RuntimePresentation.destinationLabel(binding.destination)
      if binding.axisTuning == nil {
        return OJDLocalized.formatted(
          "profiles.assignmentSummary",
          fallback: "%@ to %@",
          source,
          destination
        )
      }
      return OJDLocalized.formatted(
        "profiles.assignmentAdjustSummary",
        fallback: "%@ to %@, Adjust available",
        source,
        destination
      )
    }

    private var sourceBinding: Binding<RemappingSource> {
      Binding(get: { binding.source }, set: { setSource($0) })
    }

    private var destinationBinding: Binding<RemappingDestination> {
      Binding(
        get: { binding.destination },
        set: { destination in
          do {
            draft = try draft.settingDestination(destination, for: binding.id)
            onEditingStateChanged()
          } catch { onError(RuntimePresentation.userFacingError(error)) }
        }
      )
    }

    private func setSource(_ source: RemappingSource) {
      do {
        draft = try draft.settingSource(source, for: binding.id)
        onEditingStateChanged()
      } catch { onError(RuntimePresentation.userFacingError(error)) }
    }
  }

#endif
