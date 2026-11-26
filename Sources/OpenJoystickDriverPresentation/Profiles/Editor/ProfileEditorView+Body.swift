#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ProfileEditorView {

    /// The draft being edited, kept in ``editor``.
    var draft: RuntimeProfileDraft {
      get { editor.draft }
      nonmutating set { editor.draft = newValue }
    }
    /// The stored profile that the draft is compared with, kept in ``editor``.
    var expectedCurrent: RemappingProfile {
      get { editor.expectedCurrent }
      nonmutating set { editor.expectedCurrent = newValue }
    }
    /// The sheet that is open, or nil, kept in ``editor``.
    var activeSheet: ProfileEditorSheet? {
      get { editor.activeSheet }
      nonmutating set { editor.activeSheet = newValue }
    }
    /// Whether the conflict banner shows, kept in ``editor``.
    var showingConflict: Bool {
      get { editor.showingConflict }
      nonmutating set { editor.showingConflict = newValue }
    }
    /// The message of the latest refused edit, or nil, kept in ``editor``.
    var localError: String? {
      get { editor.localError }
      nonmutating set { editor.localError = newValue }
    }
    /// The message of the latest failed save, or nil, kept in ``editor``.
    var saveError: String? {
      get { editor.saveError }
      nonmutating set { editor.saveError = newValue }
    }
    /// The save that is in flight, kept in ``editor``.
    var saveState: ProfileEditorSaveState {
      get { editor.saveState }
      nonmutating set { editor.saveState = newValue }
    }

    /// The profile editor: the header, the section navigation, the section content and the footer,
    /// with the sheets and confirmations it opens.
    var body: some View {
      GeometryReader { proxy in
        VStack(alignment: .leading, spacing: OJDSpacing.none) {
          editorHeader
          Divider()
          sectionNavigation(width: proxy.size.width)
          Divider()
          editorContent
          Divider()
          editorFooter
        }
      }.disabled(isEditingDisabled).sheet(item: $editor.activeSheet) { sheet in
        Group { editorSheet(sheet) }.disabled(isEditingDisabled)
      }.alert(item: $confirmation) { confirmation in confirmationAlert(confirmation) }
        .onReceive(library.$mutationState) { mutation in handleMutation(mutation) }.onAppear {
          reportEditingState()
        }
    }

    /// The sheet that ``activeSheet`` names.
    @ViewBuilder
    private func editorSheet(_ sheet: ProfileEditorSheet) -> some View {
      switch sheet {
      case .metadata: metadataSheet()
      case .sticks: sticksSheet()
      case .triggers: triggersSheet()
      case .touch: touchSheet()
      case .regions: regionsSheet()
      case .pointerSpeed: pointerSpeedSheet()
      case .motion: motionSheet()
      case .layerMotion(let layer): layerMotionSheet(layer)
      case .capture: captureSheet()
      case .adjustment(let binding): adjustmentSheet(binding)
      case .behavior(let binding): behaviorSheet(binding)
      case .chord: chordSheet()
      case .sequence: sequenceSheet()
      case .layer: layerCreationSheet()
      case .macro(let macro): macroSheet(macro)
      case .layerBinding(let layer): layerBindingSheet(layer)
      case .layerAdjustment(let layerID, let binding): layerAdjustmentSheet(layerID, binding)
      case .layerBehavior(let layerID, let binding): layerBehaviorSheet(layerID, binding)
      }
    }

    /// The `metadata` sheet.
    @ViewBuilder
    private func metadataSheet() -> some View {
      ProfileMetadataSheet(profile: draft.profile) { updateMetadata($0) }
    }

    /// The `sticks` sheet.
    @ViewBuilder
    private func sticksSheet() -> some View {
      ProfileStickSheet(mappings: draft.profile.stickMappings) { mappings in
        draft = try draft.settingStickMappings(mappings)
        localError = nil
        saveError = nil
        reportEditingState()
      }
    }

    /// The `triggers` sheet.
    @ViewBuilder
    private func triggersSheet() -> some View {
      ProfileTriggerSheet(mappings: draft.profile.triggerMappings) { mappings in
        draft = try draft.settingTriggerMappings(mappings)
        localError = nil
        saveError = nil
        reportEditingState()
      }
    }

    /// The `touch` sheet.
    @ViewBuilder
    private func touchSheet() -> some View {
      ProfileTouchSheet(mappings: draft.profile.touchMappings, capabilities: capabilities) {
        mappings in applyDraftChange { try draft.settingTouchMappings(mappings) }
      }
    }

    /// The `regions` sheet.
    @ViewBuilder
    private func regionsSheet() -> some View {
      ProfileRegionSheet(viewModel: viewModel, stickMappings: draft.profile.stickMappings) {
        source,
        destination in
        draft = try draft.addingBinding(source: source, destination: destination)
        localError = nil
        saveError = nil
        reportEditingState()
      }
    }

    /// The `pointerSpeed` sheet.
    @ViewBuilder
    private func pointerSpeedSheet() -> some View {
      ProfilePointerSpeedSheet(
        speed: draft.profile.pointerSpeed,
        capabilities: capabilities,
        liveState: {
          let model = ControllerModelID(
            vendorID: draft.profile.device.vendorID,
            productID: draft.profile.device.productID
          )
          return try await viewModel.gateway.controllerState(for: .model(model))
        },
        onSave: { speed in applyDraftChange { try draft.settingPointerSpeed(speed) } }
      )
    }

    /// The `motion` sheet.
    @ViewBuilder
    private func motionSheet() -> some View {
      ProfileMotionSheet(tuning: draft.profile.motionTuning, output: draft.profile.gyroOutput) {
        tuning,
        output in
        applyDraftChange { try draft.settingMotionTuning(tuning, gyroOutput: output) }
      }
    }

    /// The `layerMotion` sheet.
    @ViewBuilder
    private func layerMotionSheet(_ layer: RemappingLayer) -> some View {
      ProfileMotionSheet(
        tuning: layer.motionTuning ?? draft.profile.motionTuning,
        output: .default,
        showsGyroOutput: false,
        onInherit: {
          applyDraftChange { try draft.settingLayerMotionTuning(nil, for: layer.id) }
        },
        onSave: { tuning, _ in
          applyDraftChange { try draft.settingLayerMotionTuning(tuning, for: layer.id) }
        }
      )
    }

    /// The `capture` sheet.
    @ViewBuilder
    private func captureSheet() -> some View {
      CaptureAssignmentSheet(
        viewModel: viewModel,
        capabilities: capabilities,
        macros: draft.profile.macros
      ) {
        source,
        destination in addBinding(source: source, destination: destination)
      }
    }

    /// The `adjustment` sheet.
    @ViewBuilder
    private func adjustmentSheet(_ binding: RemappingBinding) -> some View {
      AxisAdjustmentSheet(binding: binding) { tuning in
        updateAxisTuning(tuning, for: binding.id)
      }
    }

    /// The `behavior` sheet.
    @ViewBuilder
    private func behaviorSheet(_ binding: RemappingBinding) -> some View {
      BindingBehaviorSheet(binding: binding, capabilities: capabilities) {
        behavior,
        pulseDurationMs,
        turbo,
        longHold,
        multiTap,
        actions,
        remark in
        applyDraftChange {
          try draft.settingBindingBehaviors(
            behavior: behavior,
            pulseDurationMs: pulseDurationMs,
            turbo: turbo,
            longHold: longHold,
            multiTap: multiTap,
            for: binding.id
          ).settingAdditionalActions(actions, for: binding.id)
            .settingRemark(remark, for: binding.id)
        }
      }
    }

    /// The `chord` sheet.
    @ViewBuilder
    private func chordSheet() -> some View {
      ProfileCombinationSheet(kind: .chord, capabilities: capabilities) {
        sources,
        mode,
        windowMs,
        destination in
        addChord(sources: sources, mode: mode, windowMs: windowMs, destination: destination)
      }
    }

    /// The `sequence` sheet.
    @ViewBuilder
    private func sequenceSheet() -> some View {
      ProfileCombinationSheet(kind: .sequence, capabilities: capabilities) {
        sources,
        _,
        windowMs,
        destination in
        addSequence(sources: sources, windowMs: windowMs, destination: destination)
      }
    }

    /// The `layer` sheet.
    @ViewBuilder
    private func layerCreationSheet() -> some View {
      ProfileLayerSheet(capabilities: capabilities) { name, activator, mode in
        addLayer(name: name, activator: activator, mode: mode)
      }
    }

    /// The `macro` sheet.
    @ViewBuilder
    private func macroSheet(_ macro: RemappingMacro?) -> some View {
      MacroEditorSheet(macro: macro, capabilities: capabilities) { saveMacro($0) }
    }

    /// The `layerBinding` sheet.
    @ViewBuilder
    private func layerBindingSheet(_ layer: RemappingLayer) -> some View {
      ProfileLayerBindingSheet(layer: layer, capabilities: capabilities) {
        source,
        destination in
        setLayerBinding(layerID: layer.id, source: source, destination: destination)
      }
    }

    /// The `layerAdjustment` sheet.
    @ViewBuilder
    private func layerAdjustmentSheet(_ layerID: UUID, _ binding: RemappingBinding) -> some View {
      AxisAdjustmentSheet(binding: binding) { tuning in
        updateLayerAxisTuning(tuning, layerID: layerID, bindingID: binding.id)
      }
    }

    /// The `layerBehavior` sheet.
    @ViewBuilder
    private func layerBehaviorSheet(_ layerID: UUID, _ binding: RemappingBinding) -> some View {
      BindingBehaviorSheet(binding: binding, capabilities: capabilities) {
        behavior,
        pulseDurationMs,
        turbo,
        longHold,
        multiTap,
        actions,
        remark in
        applyDraftChange {
          try draft.settingLayerBindingBehaviors(
            behavior: behavior,
            pulseDurationMs: pulseDurationMs,
            layerID: layerID,
            bindingID: binding.id,
            turbo: turbo,
            longHold: longHold,
            multiTap: multiTap
          ).settingAdditionalActions(actions, for: binding.id, layerID: layerID)
            .settingRemark(remark, for: binding.id, layerID: layerID)
        }
      }
    }

    /// The confirmation dialog for the pending ``confirmation``.
    private func confirmationAlert(_ confirmation: ProfileEditorConfirmation) -> Alert {
      switch confirmation {
      case .activateEmpty:
        Alert(
          title: Text(
            OJDLocalized.string(
              "ui.profiles.emptyActivationTitle"
            )
          ),
          message: Text(
            OJDLocalized.string(
              "ui.profiles.emptyActivationMessage"
            )
          ),
          primaryButton: .destructive(
            Text(OJDLocalized.string("action.setActive"))
          ) { activateProfile(allowEmpty: true) },
          secondaryButton: .cancel { self.confirmation = nil }
        )
      case .activateNotice(let message):
        Alert(
          title: Text(OJDLocalized.string("ui.profiles.activationTitle")),
          message: Text(message),
          primaryButton: .default(
            Text(OJDLocalized.string("action.setActive"))
          ) { activateProfile(allowEmpty: false) },
          secondaryButton: .cancel { self.confirmation = nil }
        )
      case .clearInputs:
        Alert(
          title: Text(
            OJDLocalized.string("ui.profiles.clearInputsTitle")
          ),
          message: Text(
            OJDLocalized.string(
              "ui.profiles.clearInputsMessage"
            )
          ),
          primaryButton: .destructive(
            Text(OJDLocalized.string("ui.profiles.clearInputsConfirm"))
          ) { clearInputs() },
          secondaryButton: .cancel { self.confirmation = nil }
        )
      case .removeAllAssignments:
        Alert(
          title: Text(OJDLocalized.string("ui.profiles.removeAllAssignmentsTitle")),
          message: Text(OJDLocalized.string("ui.profiles.removeAllAssignmentsMessage")),
          primaryButton: .destructive(
            Text(OJDLocalized.string("ui.profiles.removeAllAssignmentsConfirm"))
          ) { removeAllAssignments() },
          secondaryButton: .cancel { self.confirmation = nil }
        )
      }
    }

    /// The header: the profile's name, the details and activation buttons, the actions menu, the
    /// conflict banner and the warning about paused input.
    var editorHeader: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        HStack(alignment: .center, spacing: OJDSpacing.medium) {
          Text(draft.profile.name).font(.headline.weight(.semibold)).frame(
            maxWidth: .infinity,
            alignment: .leading
          ).ojdAccessibilityLabel(
            OJDLocalized.string("term.profileName")
          )
          OJDCompactSymbolButton(
            symbolName: "pencil",
            label: OJDLocalized.string("ui.profiles.details"),
            help: OJDLocalized.string("ui.profiles.detailsHelp")
          ) { activeSheet = .metadata }
          primaryActivationAction
          profileActionMenu
        }
        if showingConflict {
          ConflictBanner(
            reload: {
              Task { @MainActor in
                await viewModel.refresh()
                switch viewModel.remappingState {
                case .available(let snapshot):
                  guard let latest = snapshot.profiles.first(where: { $0.id == profile.id })
                  else {
                    saveError = OJDLocalized.string("ui.profiles.reloadUnavailable")
                    return
                  }
                  showingConflict = false
                  expectedCurrent = latest
                  draft = RuntimeProfileDraft(profile: latest)
                  saveError = nil
                  reportEditingState()
                case .unavailable(let message), .error(let message): saveError = message
                case .loading: saveError = OJDLocalized.string("ui.profiles.reloadUnavailable")
                }
              }
            },
            keepEditing: { showingConflict = false }
          )
        }
        if draft.profile.suppressesAllControllerInput {
          HStack(spacing: OJDSpacing.small) {
            Text(
              OJDLocalized.string(
                "ui.profiles.emptyInputWarning"
              )
            ).foregroundColor(Color(NSColor.systemOrange))
            Button(
              OJDLocalized.string("ui.profiles.restoreDefaultInput")
            ) { restoreDefaultInput() }.help(
              OJDLocalized.string("ui.profiles.restoreDefaultInputHelp")
            )
          }.font(.body)
        }
      }.padding(.horizontal, 28).padding(.vertical, 18)
    }

    /// The Set Active or Deactivate button; a Joy-Con pair profile has none.
    @ViewBuilder
    var primaryActivationAction: some View {
      if profile.joyConPair == nil {
        Button(
          OJDLocalized.string(
            isActive ? "action.deactivate" : "action.setActive"
          )
        ) { isActive ? deactivateProfile() : requestActivation() }.disabled(isMutationActive)
          .help(
            OJDLocalized.string(
              isActive ? "ui.profiles.deactivateHelp" : "ui.profiles.setActiveHelp"
            )
          )
      }
    }

    /// The Actions menu.
    var profileActionMenu: some View {
      Picker(
        OJDLocalized.string("ui.profiles.actions"),
        selection: Binding<ProfileEditorMenuAction?>(
          get: { nil },
          set: { action in if let action { performMenuAction(action) } }
        )
      ) {
        Text(OJDLocalized.string("ui.profiles.actions")).tag(
          Optional<ProfileEditorMenuAction>.none
        )
        ForEach(menuActions, id: \.self) { action in Text(action.title).tag(Optional(action)) }
      }.pickerStyle(PopUpButtonPickerStyle()).labelsHidden().frame(width: 132)
        .disabled(isMutationActive).help(OJDLocalized.string("ui.profiles.actionsHelp"))
    }

    /// The picker of the editor section: a segmented control, or a pop-up menu when the editor is
    /// narrow.
    ///
    /// - Parameter width: The width of the editor.
    /// - Returns: The picker.
    func sectionNavigation(width: CGFloat) -> some View {
      Group {
        if ProfilePresentationPolicy.navigationStyle(for: width) == .segmented {
          Picker(
            OJDLocalized.string("ui.profiles.editorSection"),
            selection: $selectedSection
          ) {
            ForEach(ProfilePresentationPolicy.sectionOrder) { section in
              Text(section.title).tag(section)
            }
          }.pickerStyle(SegmentedPickerStyle()).labelsHidden()
            .ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.editorSection"))
            .help(OJDLocalized.string("ui.profiles.editorSectionHelp"))
        } else {
          HStack {
            Text(OJDLocalized.string("ui.profiles.editorSection"))
              .foregroundColor(Color(NSColor.secondaryLabelColor))
            Picker("", selection: $selectedSection) {
              ForEach(ProfilePresentationPolicy.sectionOrder) { section in
                Text(section.title).tag(section)
              }
            }.labelsHidden().pickerStyle(PopUpButtonPickerStyle()).frame(maxWidth: .infinity)
              .ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.editorSection"))
              .help(OJDLocalized.string("ui.profiles.editorSectionHelp"))
          }
        }
      }.padding(.horizontal, 28).padding(.vertical, 10)
        .ojdAccessibilityValue(selectedSection.title)
    }
  }

#endif
