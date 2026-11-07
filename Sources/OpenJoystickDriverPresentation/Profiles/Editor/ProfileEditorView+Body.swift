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
        VStack(alignment: .leading, spacing: 0) {
          editorHeader(width: proxy.size.width)
          Divider()
          sectionNavigation(width: proxy.size.width)
          Divider()
          editorContent(width: proxy.size.width)
          Divider()
          editorFooter
        }
      }.disabled(isEditingDisabled).sheet(item: $editor.activeSheet) { sheet in
        Group {
          switch sheet {
          case .metadata: ProfileMetadataSheet(profile: draft.profile) { updateMetadata($0) }
          case .sticks:
            ProfileStickSheet(mappings: draft.profile.stickMappings) { mappings in
              draft = try draft.settingStickMappings(mappings)
              localError = nil
              saveError = nil
              reportEditingState()
            }
          case .triggers:
            ProfileTriggerSheet(mappings: draft.profile.triggerMappings) { mappings in
              draft = try draft.settingTriggerMappings(mappings)
              localError = nil
              saveError = nil
              reportEditingState()
            }
          case .touch:
            ProfileTouchSheet(mappings: draft.profile.touchMappings, capabilities: capabilities) {
              mappings in applyDraftChange { try draft.settingTouchMappings(mappings) }
            }
          case .motion:
            ProfileMotionSheet(tuning: draft.profile.motionTuning, output: draft.profile.gyroOutput)
            { tuning, output in
              applyDraftChange { try draft.settingMotionTuning(tuning, gyroOutput: output) }
            }
          case .layerMotion(let layer):
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
          case .capture:
            CaptureAssignmentSheet(viewModel: viewModel, capabilities: capabilities) {
              source,
              destination in addBinding(source: source, destination: destination)
            }
          case .adjustment(let binding):
            AxisAdjustmentSheet(binding: binding) { tuning in
              updateAxisTuning(tuning, for: binding.id)
            }
          case .behavior(let binding):
            BindingBehaviorSheet(binding: binding, capabilities: capabilities) {
              behavior,
              pulseDurationMs,
              turbo,
              longHold,
              multiTap,
              actions in
              applyDraftChange {
                try draft.settingBindingBehaviors(
                  behavior: behavior,
                  pulseDurationMs: pulseDurationMs,
                  turbo: turbo,
                  longHold: longHold,
                  multiTap: multiTap,
                  for: binding.id
                ).settingAdditionalActions(actions, for: binding.id)
              }
            }
          case .chord:
            ProfileCombinationSheet(kind: .chord, capabilities: capabilities) {
              sources,
              mode,
              windowMs,
              destination in
              addChord(sources: sources, mode: mode, windowMs: windowMs, destination: destination)
            }
          case .sequence:
            ProfileCombinationSheet(kind: .sequence, capabilities: capabilities) {
              sources,
              _,
              windowMs,
              destination in
              addSequence(sources: sources, windowMs: windowMs, destination: destination)
            }
          case .layer:
            ProfileLayerSheet(capabilities: capabilities) { name, activator, mode in
              addLayer(name: name, activator: activator, mode: mode)
            }
          case .layerBinding(let layer):
            ProfileLayerBindingSheet(layer: layer, capabilities: capabilities) {
              source,
              destination in
              setLayerBinding(layerID: layer.id, source: source, destination: destination)
            }
          case .layerAdjustment(let layerID, let binding):
            AxisAdjustmentSheet(binding: binding) { tuning in
              updateLayerAxisTuning(tuning, layerID: layerID, bindingID: binding.id)
            }
          case .layerBehavior(let layerID, let binding):
            BindingBehaviorSheet(binding: binding, capabilities: capabilities) {
              behavior,
              pulseDurationMs,
              turbo,
              longHold,
              multiTap,
              actions in
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
              }
            }
          }
        }.disabled(isEditingDisabled)
      }.alert(item: $confirmation) { confirmation in
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
      }.onReceive(library.$mutationState) { mutation in handleMutation(mutation) }.onAppear {
        reportEditingState()
      }
    }

    /// The header: the profile's name, the details and activation buttons, the actions menu, the
    /// facts, the conflict banner and the warning about suppressed input.
    ///
    /// - Parameter width: The width of the editor, which decides how the facts are laid out.
    /// - Returns: The header.
    func editorHeader(width: CGFloat) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 10) {
          Text(draft.profile.name).font(.headline.weight(.semibold)).frame(
            maxWidth: .infinity,
            alignment: .leading
          ).ojdAccessibilityLabel(
            OJDLocalized.string("term.profileName")
          )
          OJDCompactSymbolButton(
            symbolName: "pencil",
            label: OJDLocalized.string("ui.profiles.details")
          ) { activeSheet = .metadata }
          primaryActivationAction
          profileActionMenu
        }
        if width < ProfilePresentationPolicy.compactNavigationWidth {
          VStack(alignment: .leading, spacing: 4) { profileFacts }
        } else {
          HStack(spacing: 10) { profileFacts }
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
        if draft.profile.suppressesAllControllerInput {
          HStack(spacing: 8) {
            Text(
              OJDLocalized.string(
                "ui.profiles.emptyInputWarning"
              )
            ).foregroundColor(Color(NSColor.systemOrange))
            Button(
              OJDLocalized.string("ui.profiles.restoreDefaultInput")
            ) { restoreDefaultInput() }
          }.font(.caption)
        }
      }.padding(.horizontal, 28).padding(.vertical, 18)
    }

    /// The target, the number of assignments and the activation state of the profile.
    @ViewBuilder
    var profileFacts: some View {
      Text(RuntimePresentation.profileScopeLabel(draft.profile.applicationScope)).foregroundColor(
        Color(NSColor.secondaryLabelColor)
      )
      Text(assignmentCountLabel(draft.profile.bindings.count)).foregroundColor(
        Color(NSColor.secondaryLabelColor)
      )
      Text(activationLabel).foregroundColor(Color(NSColor.secondaryLabelColor))
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
        .ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.actions"))
        .disabled(isMutationActive)
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
          }
        }
      }.padding(.horizontal, 28).padding(.vertical, 10).ojdAccessibilityLabel(
        OJDLocalized.string("ui.profiles.editorSection")
      ).ojdAccessibilityValue(selectedSection.title)
    }
  }

#endif
