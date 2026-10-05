#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ProfileEditorView {

    var draft: RuntimeProfileDraft {
      get { editor.draft }
      nonmutating set { editor.draft = newValue }
    }
    var expectedCurrent: RemappingProfile {
      get { editor.expectedCurrent }
      nonmutating set { editor.expectedCurrent = newValue }
    }
    var activeSheet: ProfileEditorSheet? {
      get { editor.activeSheet }
      nonmutating set { editor.activeSheet = newValue }
    }
    var showingConflict: Bool {
      get { editor.showingConflict }
      nonmutating set { editor.showingConflict = newValue }
    }
    var localError: String? {
      get { editor.localError }
      nonmutating set { editor.localError = newValue }
    }
    var saveError: String? {
      get { editor.saveError }
      nonmutating set { editor.saveError = newValue }
    }
    var saveState: ProfileEditorSaveState {
      get { editor.saveState }
      nonmutating set { editor.saveState = newValue }
    }

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
              doubleTap,
              actions in
              applyDraftChange {
                try draft.settingBindingBehaviors(
                  behavior: behavior,
                  pulseDurationMs: pulseDurationMs,
                  turbo: turbo,
                  longHold: longHold,
                  doubleTap: doubleTap,
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
              doubleTap,
              actions in
              applyDraftChange {
                try draft.settingLayerBindingBehaviors(
                  behavior: behavior,
                  pulseDurationMs: pulseDurationMs,
                  layerID: layerID,
                  bindingID: binding.id,
                  turbo: turbo,
                  longHold: longHold,
                  doubleTap: doubleTap
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
                "profiles.emptyActivationTitle"
              )
            ),
            message: Text(
              OJDLocalized.string(
                "profiles.emptyActivationMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("common.setActive"))
            ) { activateProfile() },
            secondaryButton: .cancel { self.confirmation = nil }
          )
        case .clearInputs:
          Alert(
            title: Text(
              OJDLocalized.string("profiles.clearInputsTitle")
            ),
            message: Text(
              OJDLocalized.string(
                "profiles.clearInputsMessage"
              )
            ),
            primaryButton: .destructive(
              Text(OJDLocalized.string("profiles.clearInputs"))
            ) { clearInputs() },
            secondaryButton: .cancel { self.confirmation = nil }
          )
        }
      }.onReceive(library.$mutationState) { mutation in handleMutation(mutation) }.onAppear {
        reportEditingState()
      }
    }

    func editorHeader(width: CGFloat) -> some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 10) {
          Text(draft.profile.name).font(.headline.weight(.semibold)).frame(
            maxWidth: .infinity,
            alignment: .leading
          ).ojdAccessibilityLabel(
            OJDLocalized.string("common.profileName")
          )
          OJDCompactSymbolButton(
            symbolName: "pencil",
            label: OJDLocalized.string("profiles.details")
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
                "profiles.emptyInputWarning"
              )
            ).foregroundColor(Color(NSColor.systemOrange))
            Button(
              OJDLocalized.string("profiles.restoreDefaultInput")
            ) { restoreDefaultInput() }
          }.font(.caption)
        }
      }.padding(.horizontal, 28).padding(.vertical, 18)
    }

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

    @ViewBuilder
    var primaryActivationAction: some View {
      if profile.joyConPair == nil {
        Button(
          OJDLocalized.string(
            isActive ? "common.deactivate" : "common.setActive"
          )
        ) { isActive ? deactivateProfile() : requestActivation() }.disabled(isMutationActive)
      }
    }

    var profileActionMenu: some View {
      Picker(
        OJDLocalized.string("profiles.actions"),
        selection: Binding<ProfileEditorMenuAction?>(
          get: { nil },
          set: { action in if let action { performMenuAction(action) } }
        )
      ) {
        Text(OJDLocalized.string("profiles.actions")).tag(
          Optional<ProfileEditorMenuAction>.none
        )
        ForEach(menuActions, id: \.self) { action in Text(action.title).tag(Optional(action)) }
      }.pickerStyle(PopUpButtonPickerStyle()).labelsHidden().frame(width: 132)
        .ojdAccessibilityLabel(OJDLocalized.string("profiles.actions"))
        .disabled(isMutationActive)
    }

    func sectionNavigation(width: CGFloat) -> some View {
      Group {
        if ProfilePresentationPolicy.navigationStyle(for: width) == .segmented {
          Picker(
            OJDLocalized.string("profiles.editorSection"),
            selection: $selectedSection
          ) {
            ForEach(ProfilePresentationPolicy.sectionOrder) { section in
              Text(section.title).tag(section)
            }
          }.pickerStyle(SegmentedPickerStyle()).labelsHidden()
        } else {
          HStack {
            Text(OJDLocalized.string("profiles.editorSection"))
              .foregroundColor(Color(NSColor.secondaryLabelColor))
            Picker("", selection: $selectedSection) {
              ForEach(ProfilePresentationPolicy.sectionOrder) { section in
                Text(section.title).tag(section)
              }
            }.labelsHidden().pickerStyle(PopUpButtonPickerStyle()).frame(maxWidth: .infinity)
          }
        }
      }.padding(.horizontal, 28).padding(.vertical, 10).ojdAccessibilityLabel(
        OJDLocalized.string("profiles.editorSection")
      ).ojdAccessibilityValue(selectedSection.title)
    }
  }

#endif
