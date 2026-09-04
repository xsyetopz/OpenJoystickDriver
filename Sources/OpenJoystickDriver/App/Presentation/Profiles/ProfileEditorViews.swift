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
    let isEditingBlocked: Bool
    let onDelete: () -> Void
    let onExport: (RemappingProfile) -> Void
    let onEditingStateChanged: (Bool) -> Void
    let onMutationStarted: (RuntimeMutationRequest) -> Bool
    let onMutationResult: (RuntimeMutationResult) -> Void

    @State private var draft: RuntimeProfileDraft
    @State private var expectedCurrent: RemappingProfile
    @State private var activeSheet: ProfileEditorSheet?
    @State private var showingConflict = false
    @State private var localError: String?
    @State private var saveError: String?
    @State private var saveState = ProfileEditorSaveState()

    init(
      profile: RemappingProfile,
      viewModel: RuntimeViewModel,
      isActive: Bool,
      isEditingBlocked: Bool,
      onDelete: @escaping () -> Void,
      onExport: @escaping (RemappingProfile) -> Void,
      onEditingStateChanged: @escaping (Bool) -> Void,
      onMutationStarted: @escaping (RuntimeMutationRequest) -> Bool,
      onMutationResult: @escaping (RuntimeMutationResult) -> Void
    ) {
      self.profile = profile
      self.viewModel = viewModel
      self.isActive = isActive
      self.isEditingBlocked = isEditingBlocked
      self.onDelete = onDelete
      self.onExport = onExport
      self.onEditingStateChanged = onEditingStateChanged
      self.onMutationStarted = onMutationStarted
      self.onMutationResult = onMutationResult
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
      }.disabled(isEditingDisabled).sheet(item: $activeSheet) { sheet in
        Group {
          switch sheet {
          case .metadata: ProfileMetadataSheet(profile: draft.profile) { updateMetadata($0) }
          case .capture:
            CaptureAssignmentSheet(viewModel: viewModel) { source, destination in
              addBinding(source: source, destination: destination)
            }
          case .adjustment(let binding):
            AxisAdjustmentSheet(binding: binding) { tuning in
              updateAxisTuning(tuning, for: binding.id)
            }
          case .behavior(let binding):
            BindingBehaviorSheet(binding: binding) { turbo, longHold, doubleTap in
              updateBindingBehaviors(
                turbo: turbo,
                longHold: longHold,
                doubleTap: doubleTap,
                for: binding.id
              )
            }
          case .chord:
            ProfileCombinationSheet(kind: .chord) { sources, _, destination in
              addChord(sources: sources, destination: destination)
            }
          case .sequence:
            ProfileCombinationSheet(kind: .sequence) { sources, windowMs, destination in
              addSequence(sources: sources, windowMs: windowMs, destination: destination)
            }
          case .layer:
            ProfileLayerSheet { name, activator, mode in
              addLayer(name: name, activator: activator, mode: mode)
            }
          case .layerBinding(let layer):
            ProfileLayerBindingSheet(layer: layer) { source, destination in
              setLayerBinding(layerID: layer.id, source: source, destination: destination)
            }
          case .layerAdjustment(let layerID, let binding):
            AxisAdjustmentSheet(binding: binding) { tuning in
              updateLayerAxisTuning(tuning, layerID: layerID, bindingID: binding.id)
            }
          case .layerBehavior(let layerID, let binding):
            BindingBehaviorSheet(binding: binding) { turbo, longHold, doubleTap in
              updateLayerBindingBehaviors(
                layerID: layerID,
                bindingID: binding.id,
                turbo: turbo,
                longHold: longHold,
                doubleTap: doubleTap
              )
            }
          }
        }.disabled(isEditingDisabled)
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
          Button(OJDLocalized.string("profiles.export", fallback: "Export")) {
            do { onExport(try draft.validatedProfile()) } catch {
              localError = RuntimePresentation.userFacingError(error)
            }
          }.disabled(isMutationActive)
          Button(OJDLocalized.string("profiles.details", fallback: "Details")) {
            activeSheet = .metadata
          }.disabled(isMutationActive)
          if isActive {
            Button(OJDLocalized.string("common.deactivate", fallback: "Deactivate")) {
              guard !isMutationActive else { return }
              let request = RuntimeMutationRequest(operation: .deactivate(profileID: profile.id))
              guard onMutationStarted(request) else { return }
              Task { @MainActor in
                let result = await viewModel.deactivateRemappingProfile(
                  profileID: profile.id,
                  request: request
                )
                onMutationResult(result)
              }
            }.disabled(isMutationActive)
            Button(OJDLocalized.string("profiles.deactivateController", fallback: "Deactivate all"))
            {
              guard !isMutationActive else { return }
              let request = RuntimeMutationRequest(operation: .deactivate(profileID: nil))
              guard onMutationStarted(request) else { return }
              Task { @MainActor in
                let result = await viewModel.deactivateRemappingProfile(
                  vendorID: profile.device.vendorID,
                  productID: profile.device.productID,
                  request: request
                )
                onMutationResult(result)
              }
            }.disabled(isMutationActive)
          } else {
            Button(OJDLocalized.string("common.setActive", fallback: "Set active")) {
              guard !isMutationActive else { return }
              let request = RuntimeMutationRequest(operation: .activate(profileID: profile.id))
              guard onMutationStarted(request) else { return }
              Task { @MainActor in
                let result = await viewModel.activateRemappingProfile(
                  id: profile.id,
                  request: request
                )
                onMutationResult(result)
              }
            }.disabled(isMutationActive)
          }
          Spacer(minLength: 0)
        }
        HStack(spacing: 12) {
          Text(RuntimePresentation.profileScopeLabel(draft.profile.applicationScope))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
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
                isEditingDisabled: isEditingDisabled,
                onRemove: removeBinding,
                onError: { localError = $0 },
                onAdjust: { activeSheet = .adjustment($0) },
                onBehavior: { activeSheet = .behavior($0) },
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
          chordSection
          sequenceSection
          layerSection
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

    private var isEditingDisabled: Bool { isEditingBlocked || isMutationActive }

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
          guard !isEditingDisabled else { return }
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
        case .start, .back, .guide, .share, .options, .touchpad, .mute, .leftTriggerClick,
          .rightTriggerClick:
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
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.addingBinding(source: source, destination: destination)
        activeSheet = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private func removeBinding(_ id: UUID) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.removingBinding(id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private func updateAxisTuning(_ tuning: RemappingAxisTuning, for id: UUID) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.settingAxisTuning(tuning, for: id)
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private func updateMetadata(_ profile: RemappingProfile) {
      guard !isEditingDisabled else { return }
      draft = RuntimeProfileDraft(profile: profile)
      localError = nil
      saveError = nil
      reportEditingState()
    }

    private func updateBindingBehaviors(
      turbo: RemappingTurbo?,
      longHold: RemappingLongHold?,
      doubleTap: RemappingDoubleTap?,
      for id: UUID
    ) {
      applyDraftChange {
        try draft.settingBindingBehaviors(
          turbo: turbo,
          longHold: longHold,
          doubleTap: doubleTap,
          for: id
        )
      }
    }

    private func addChord(sources: [RemappingSource], destination: RemappingDestination) {
      applyDraftChange { try draft.addingChord(sources: Set(sources), destination: destination) }
    }

    private func removeChord(_ id: UUID) { applyDraftChange { try draft.removingChord(id) } }

    private func addSequence(
      sources: [RemappingSource],
      windowMs: Double,
      destination: RemappingDestination
    ) {
      applyDraftChange {
        try draft.addingSequence(sources: sources, windowMs: windowMs, destination: destination)
      }
    }

    private func removeSequence(_ id: UUID) { applyDraftChange { try draft.removingSequence(id) } }

    private func addLayer(name: String, activator: RemappingSource, mode: RemappingLayerActivation)
    {
      applyDraftChange {
        try draft.addingLayer(name: name, activator: activator, activationMode: mode)
      }
    }

    private func removeLayer(_ id: UUID) { applyDraftChange { try draft.removingLayer(id) } }

    private func setLayerBinding(
      layerID: UUID,
      source: RemappingSource,
      destination: RemappingDestination
    ) {
      applyDraftChange {
        try draft.settingLayerBinding(layerID: layerID, source: source, destination: destination)
      }
    }

    private func removeLayerBinding(layerID: UUID, bindingID: UUID) {
      applyDraftChange { try draft.removingLayerBinding(layerID: layerID, bindingID: bindingID) }
    }

    private func updateLayerAxisTuning(
      _ tuning: RemappingAxisTuning,
      layerID: UUID,
      bindingID: UUID
    ) {
      applyDraftChange {
        try draft.settingLayerBindingAxisTuning(
          layerID: layerID,
          bindingID: bindingID,
          axisTuning: tuning
        )
      }
    }

    private func updateLayerBindingBehaviors(
      layerID: UUID,
      bindingID: UUID,
      turbo: RemappingTurbo?,
      longHold: RemappingLongHold?,
      doubleTap: RemappingDoubleTap?
    ) {
      applyDraftChange {
        try draft.settingLayerBindingBehaviors(
          layerID: layerID,
          bindingID: bindingID,
          turbo: turbo,
          longHold: longHold,
          doubleTap: doubleTap
        )
      }
    }

    private func applyDraftChange(_ change: () throws -> RuntimeProfileDraft) {
      guard !isEditingDisabled else { return }
      do {
        draft = try change()
        localError = nil
        saveError = nil
        reportEditingState()
      } catch { localError = RuntimePresentation.userFacingError(error) }
    }

    private var chordSection: some View {
      VStack(alignment: .leading, spacing: 10) {
        Divider()
        HStack {
          Text(OJDLocalized.string("profiles.chords", fallback: "Chords")).font(.headline)
          Spacer()
          Button(OJDLocalized.string("profiles.addChord", fallback: "Add chord")) {
            activeSheet = .chord
          }
        }
        if draft.profile.chords.isEmpty {
          Text(OJDLocalized.string("profiles.noChords", fallback: "No chords configured."))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        } else {
          ForEach(draft.profile.chords) { chord in
            HStack {
              Text(
                chord.sources.map(RuntimePresentation.sourceLabel).sorted().joined(separator: " + ")
              )
              OJDSystemSymbol(name: "arrow.right", fallback: "→")
              Text(RuntimePresentation.destinationLabel(chord.destination))
              Spacer()
              removeButton { removeChord(chord.id) }
            }
          }
        }
      }
    }

    private var sequenceSection: some View {
      VStack(alignment: .leading, spacing: 10) {
        Divider()
        HStack {
          Text(OJDLocalized.string("profiles.sequences", fallback: "Sequences")).font(.headline)
          Spacer()
          Button(OJDLocalized.string("profiles.addSequence", fallback: "Add sequence")) {
            activeSheet = .sequence
          }
        }
        if draft.profile.sequences.isEmpty {
          Text(OJDLocalized.string("profiles.noSequences", fallback: "No sequences configured."))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        } else {
          ForEach(draft.profile.sequences) { sequence in
            HStack {
              Text(sequence.sources.map(RuntimePresentation.sourceLabel).joined(separator: " → "))
              Text(String(format: "(%.0f ms)", sequence.windowMs)).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              )
              OJDSystemSymbol(name: "arrow.right", fallback: "→")
              Text(RuntimePresentation.destinationLabel(sequence.destination))
              Spacer()
              removeButton { removeSequence(sequence.id) }
            }
          }
        }
      }
    }

    private var layerSection: some View {
      VStack(alignment: .leading, spacing: 10) {
        Divider()
        HStack {
          Text(OJDLocalized.string("profiles.layers", fallback: "Layers")).font(.headline)
          Spacer()
          Button(OJDLocalized.string("profiles.addLayer", fallback: "Add layer")) {
            activeSheet = .layer
          }
        }
        if draft.profile.layers.isEmpty {
          Text(OJDLocalized.string("profiles.noLayers", fallback: "No layers configured."))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        } else {
          ForEach(draft.profile.layers) { layer in
            GroupBox {
              VStack(alignment: .leading, spacing: 8) {
                HStack {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(layer.name).font(.subheadline.weight(.semibold))
                    Text(layerDescription(layer)).font(.caption).foregroundColor(
                      Color(NSColor.secondaryLabelColor)
                    )
                  }
                  Spacer()
                  Button(OJDLocalized.string("common.addAssignment", fallback: "Add assignment")) {
                    activeSheet = .layerBinding(layer)
                  }
                  removeButton { removeLayer(layer.id) }
                }
                ForEach(layer.bindings) { binding in
                  HStack {
                    Text(RuntimePresentation.sourceLabel(binding.source))
                    OJDSystemSymbol(name: "arrow.right", fallback: "→")
                    Text(RuntimePresentation.destinationLabel(binding.destination))
                    Spacer()
                    if binding.axisTuning != nil {
                      Button(OJDLocalized.string("common.adjust", fallback: "Adjust...")) {
                        activeSheet = .layerAdjustment(layer.id, binding)
                      }
                    }
                    Button(OJDLocalized.string("profiles.behavior", fallback: "Behavior...")) {
                      activeSheet = .layerBehavior(layer.id, binding)
                    }
                    removeButton { removeLayerBinding(layerID: layer.id, bindingID: binding.id) }
                  }
                }
              }.padding(4)
            }
          }
        }
      }
    }

    private func layerDescription(_ layer: RemappingLayer) -> String {
      let mode =
        layer.activationMode == .hold
        ? OJDLocalized.string("profiles.hold", fallback: "Hold")
        : OJDLocalized.string("profiles.toggle", fallback: "Toggle")
      return "\(mode): \(RuntimePresentation.sourceLabel(layer.activator))"
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
      Button(action: action) {
        OJDSystemSymbol(name: "minus.circle", fallback: "Remove").frame(minWidth: 28, minHeight: 28)
          .contentShape(Rectangle())
      }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
        OJDLocalized.string("common.remove", fallback: "Remove")
      )
    }

    private func save() {
      guard draft.profile != expectedCurrent, !saveInFlight, !isEditingDisabled else { return }
      let operation = RuntimeMutationOperation.update(profileID: profile.id)
      let request = RuntimeMutationRequest(operation: operation)
      guard saveState.begin(request) else { return }
      saveError = nil
      localError = nil
      guard onMutationStarted(request) else {
        finishSave()
        return
      }
      reportEditingState()
      Task { @MainActor in
        let result = await viewModel.updateRemappingProfile(
          draft.profile,
          expectedCurrent: expectedCurrent,
          request: request
        )
        reconcileSave(request: request, result: result)
        onMutationResult(result)
      }
    }

    private func duplicateProfile() {
      guard !isEditingDisabled else { return }
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
      let request = RuntimeMutationRequest(operation: .create(profileID: duplicate.id))
      guard onMutationStarted(request) else { return }
      Task { @MainActor in
        let result = await viewModel.createRemappingProfile(duplicate, request: request)
        onMutationResult(result)
      }
    }

    private func reportEditingState() {
      onEditingStateChanged(saveInFlight || draft.profile != expectedCurrent)
    }

    private func handleMutation(_ mutation: RuntimeMutationState) {
      guard saveInFlight, pendingUpdateOperation == .update(profileID: profile.id),
        viewModel.lastMutationOperation == pendingUpdateOperation,
        viewModel.lastMutationID == pendingUpdateMutationID
      else { return }

      switch mutation {
      case .conflict(let profileID) where profileID == profile.id: applySaveConflict()
      case .error(let message):
        finishSave()
        localError = message
        saveError = message
      case .succeeded(let profileID) where profileID == profile.id: applySaveSuccess()
      default: return
      }
      reportEditingState()
    }

    private func finishSave() { saveState.cancel() }

    private func reconcileSave(request: RuntimeMutationRequest, result: RuntimeMutationResult) {
      guard saveInFlight, pendingUpdateOperation == request.operation,
        pendingUpdateMutationID == request.id
      else { return }
      switch saveState.resolve(result) {
      case .succeeded: applySaveSuccess()
      case .conflict: applySaveConflict()
      case .failed(let message):
        finishSave()
        localError = message
        saveError = message
      case .ignored: return
      }
      reportEditingState()
    }

    private func applySaveConflict() {
      finishSave()
      showingConflict = true
      saveError = OJDLocalized.string(
        "profiles.changedElsewhere",
        fallback: "The profile changed elsewhere."
      )
    }

    private func applySaveSuccess() {
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
        return
      }
      expectedCurrent = latest
      draft = RuntimeProfileDraft(profile: latest)
    }

    private var saveInFlight: Bool { saveState.isInFlight }

    private var pendingUpdateOperation: RuntimeMutationOperation? { saveState.operation }

    private var pendingUpdateMutationID: UUID? { saveState.mutationID }
  }

  private enum ProfileEditorSheet: Identifiable {
    case metadata
    case capture
    case adjustment(RemappingBinding)
    case behavior(RemappingBinding)
    case chord
    case sequence
    case layer
    case layerBinding(RemappingLayer)
    case layerAdjustment(UUID, RemappingBinding)
    case layerBehavior(UUID, RemappingBinding)

    var id: String {
      switch self {
      case .metadata: return "metadata"
      case .capture: return "capture"
      case .adjustment(let binding): return "adjustment-\(binding.id.uuidString)"
      case .behavior(let binding): return "behavior-\(binding.id.uuidString)"
      case .chord: return "chord"
      case .sequence: return "sequence"
      case .layer: return "layer"
      case .layerBinding(let layer): return "layer-binding-\(layer.id.uuidString)"
      case .layerAdjustment(let layerID, let binding):
        return "layer-adjustment-\(layerID.uuidString)-\(binding.id.uuidString)"
      case .layerBehavior(let layerID, let binding):
        return "layer-behavior-\(layerID.uuidString)-\(binding.id.uuidString)"
      }
    }
  }

#endif
