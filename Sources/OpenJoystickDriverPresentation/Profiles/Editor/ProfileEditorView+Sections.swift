#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ProfileEditorView {

    /// The form that shows the selected section.
    ///
    /// - Parameter width: The width of the editor, which decides the layout of the assignment rows.
    /// - Returns: The form.
    func editorContent(width: CGFloat) -> some View {
      Form {
        sectionContent(assignmentLayout: ProfilePresentationPolicy.assignmentRowLayout(for: width))
      }.ojdGroupedForm().id(selectedSection)
    }

    /// The content of the selected section.
    @ViewBuilder
    func sectionContent(assignmentLayout: ProfileAssignmentRowLayout) -> some View {
      switch selectedSection {
      case .assignments: assignmentsSection(rowLayout: assignmentLayout)
      case .combinations:
        ProfileCombinationsSection(
          profile: draft.profile,
          openSheet: { activeSheet = $0 },
          removeChord: removeChord,
          removeSequence: removeSequence
        )
      case .layers:
        ProfileLayersSection(
          profile: draft.profile,
          capabilities: capabilities,
          openSheet: { activeSheet = $0 },
          removeLayer: removeLayer,
          removeBinding: removeLayerBinding
        )
      case .macros:
        ProfileMacrosSection(
          macros: draft.profile.macros,
          openSheet: { activeSheet = $0 },
          removeMacro: removeMacro
        )
      case .controller:
        ProfileControllerSection(
          profile: draft.profile,
          capabilities: capabilities,
          openSheet: { activeSheet = $0 },
          updateOutputPolicy: { policy in applyDraftChange { try draft.settingOutputPolicy(policy) }
          },
          updatePhysicalColor: { color in applyDraftChange { try draft.settingPhysicalColor(color) }
          }
        )
      }
    }

    /// The Assignments section: the header with the add and clear buttons, and the assignments by
    /// group.
    @ViewBuilder
    func assignmentsSection(rowLayout: ProfileAssignmentRowLayout) -> some View {
      Section(
        header: HStack(alignment: .firstTextBaseline) {
          Text(OJDLocalized.string("term.assignments"))
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("action.addAssignment")
          ) { activeSheet = .capture }
          Button(OJDLocalized.string("ui.profiles.clearInputs")) {
            confirmation = .clearInputs
          }.disabled(isEditingDisabled)
        }
      ) {
        if draft.profile.bindings.isEmpty {
          Text(OJDLocalized.string("ui.profiles.noAssignments"))
          Text(OJDLocalized.string("ui.profiles.assignmentInstructions"))
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
      }
      ForEach(bindingGroups, id: \.title) { group in
        AssignmentGroupView(
          title: group.title,
          bindings: group.bindings,
          capabilities: capabilities,
          draft: $editor.draft,
          isEditingDisabled: isEditingDisabled,
          onRemove: removeBinding,
          onError: { localError = $0 },
          onAdjust: { activeSheet = .adjustment($0) },
          onBehavior: { activeSheet = .behavior($0) },
          onEditingStateChanged: {
            localError = nil
            saveError = nil
            reportEditingState()
          },
          rowLayout: rowLayout
        )
      }
    }

    /// The footer: the latest refused edit, the save status and the Save button.
    var editorFooter: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let localError {
          Text(localError).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack(spacing: 10) {
          Spacer(minLength: 8)
          saveStatusView
          Button(OJDLocalized.string("action.save")) { save() }.disabled(
            draft.profile == expectedCurrent || saveInFlight || isMutationActive
          )
        }
      }.padding(.horizontal, 28).padding(.vertical, 14)
    }

    /// The save status: the progress while a save runs, then its label.
    @ViewBuilder
    var saveStatusView: some View {
      HStack(spacing: 6) {
        if saveStatus == .saving { ProgressView() }
        Text(saveStatus.label).foregroundColor(saveStatus.color)
      }.frame(minHeight: 28).ojdAccessibilityLabel(
        OJDLocalized.string("ui.profiles.saveStatus")
      ).ojdAccessibilityValue(saveStatus.accessibilityValue)
    }

    /// Whether a save or another change of the profile library runs.
    var isMutationActive: Bool {
      if saveInFlight { return true }
      if library.activeMutationOperation != nil { return true }
      if case .saving = library.mutationState { return true }
      return false
    }

    /// Whether edits are ignored: the editor is blocked or a change runs.
    var isEditingDisabled: Bool { isEditingBlocked || isMutationActive }

    /// The save status of the draft: saving, failed, unsaved or saved.
    var saveStatus: ProfileSaveStatus {
      if saveInFlight { return .saving }
      if saveError != nil { return .error }
      if draft.profile != expectedCurrent { return .unsaved }
      return .saved
    }

    /// A binding to the profile name in the draft.
    var nameBinding: Binding<String> {
      Binding(
        get: { draft.profile.name },
        set: { newValue in
          guard !isEditingDisabled else { return }
          draft = draft.settingName(newValue)
          saveError = nil
          reportEditingState()
        }
      )
    }

    /// The assignments of the draft grouped by section, in the order of the sections.
    var bindingGroups: [BindingGroup] {
      let grouped = Dictionary(grouping: draft.profile.bindings) { profileSourceGroup($0.source) }
      return BindingGroup.Order.allCases.compactMap { order in
        guard let bindings = grouped[order.title], !bindings.isEmpty else { return nil }
        return BindingGroup(title: order.title, bindings: bindings)
      }
    }

  }

#endif
