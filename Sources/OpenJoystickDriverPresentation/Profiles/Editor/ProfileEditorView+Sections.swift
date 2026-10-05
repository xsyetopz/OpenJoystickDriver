#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension ProfileEditorView {

    func editorContent(width: CGFloat) -> some View {
      ScrollView {
        sectionContent(assignmentLayout: ProfilePresentationPolicy.assignmentRowLayout(for: width))
          .padding(28).frame(maxWidth: .infinity, alignment: .leading)
      }.id(selectedSection)
    }

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

    func assignmentsSection(rowLayout: ProfileAssignmentRowLayout) -> some View {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          Text(OJDLocalized.string("common.assignments")).font(.headline)
          Spacer()
          OJDCompactSymbolButton(
            symbolName: "plus",
            label: OJDLocalized.string("common.addAssignment")
          ) { activeSheet = .capture }
          Button(OJDLocalized.string("profiles.clearInputs")) {
            confirmation = .clearInputs
          }.disabled(isEditingDisabled)
        }
        if draft.profile.bindings.isEmpty {
          EmptyStateView(
            symbol: "plus.circle",
            title: OJDLocalized.string("profiles.noAssignments"),
            message: OJDLocalized.string(
              "profiles.assignmentInstructions"
            )
          )
        } else {
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
      }
    }

    var editorFooter: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let localError {
          Text(localError).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack(spacing: 10) {
          OJDDestructiveButton(action: onDelete) {
            Text(OJDLocalized.string("common.delete"))
          }.disabled(isMutationActive)
          Spacer(minLength: 8)
          saveStatusView
          Button(OJDLocalized.string("common.save")) { save() }.disabled(
            draft.profile == expectedCurrent || saveInFlight || isMutationActive
          )
        }
      }.padding(.horizontal, 28).padding(.vertical, 14)
    }

    @ViewBuilder
    var saveStatusView: some View {
      HStack(spacing: 6) {
        if saveStatus == .saving { ProgressView() }
        Text(saveStatus.label).foregroundColor(saveStatus.color)
      }.frame(minHeight: 28).ojdAccessibilityLabel(
        OJDLocalized.string("profiles.saveStatus")
      ).ojdAccessibilityValue(saveStatus.accessibilityValue)
    }

    var isMutationActive: Bool {
      if saveInFlight { return true }
      if library.activeMutationOperation != nil { return true }
      if case .saving = library.mutationState { return true }
      return false
    }

    var isEditingDisabled: Bool { isEditingBlocked || isMutationActive }

    var saveStatus: ProfileSaveStatus {
      if saveInFlight { return .saving }
      if saveError != nil { return .error }
      if draft.profile != expectedCurrent { return .unsaved }
      return .saved
    }

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

    var bindingGroups: [BindingGroup] {
      let grouped = Dictionary(grouping: draft.profile.bindings) { profileSourceGroup($0.source) }
      return BindingGroup.Order.allCases.compactMap { order in
        guard let bindings = grouped[order.title], !bindings.isEmpty else { return nil }
        return BindingGroup(title: order.title, bindings: bindings)
      }
    }

  }

#endif
