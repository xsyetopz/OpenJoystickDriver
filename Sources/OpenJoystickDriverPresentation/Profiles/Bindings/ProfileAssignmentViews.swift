#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// Returns the title of the section that lists assignments with `source`.
  func profileSourceGroup(_ source: RemappingSource) -> String {
    switch source {
    case .button(let button):
      switch button {
      case .leftShoulder, .rightShoulder:
        return OJDLocalized.string("ui.profiles.sectionShoulders")
      case .leftStickClick, .rightStickClick:
        return OJDLocalized.string("ui.profiles.sectionStickClicks")
      case .start, .back, .guide, .capture, .touchpadClick, .microphone, .leftTrigger,
        .rightTrigger:
        return OJDLocalized.string("ui.profiles.sectionSystemControls")
      default: return OJDLocalized.string("ui.profiles.sectionFaceButtons")
      }
    case .dpad: return OJDLocalized.string("ui.profiles.sectionDpad")
    case .axis, .axisDirection:
      switch source {
      case .axis(.leftTrigger), .axis(.rightTrigger), .axisDirection(.leftTrigger, _),
        .axisDirection(.rightTrigger, _):
        return OJDLocalized.string("ui.profiles.sectionTriggers")
      default: return OJDLocalized.string("ui.profiles.sectionSticks")
      }
    case .triggerStage: return OJDLocalized.string("ui.profiles.sectionTriggers")
    case .motionLean: return OJDLocalized.string("ui.profiles.sectionMotion")
    case .touchContact, .touchGrid, .touchSwipe:
      return OJDLocalized.string("ui.profiles.sectionTouch")
    }
  }

  /// The assignments of one section of the profile editor.
  struct BindingGroup {
    /// The title of the section.
    let title: String
    /// The assignments in the section.
    let bindings: [RemappingBinding]

    /// The sections of the profile editor's assignment list, in the order they appear.
    enum Order: CaseIterable {
      /// Face buttons.
      case face
      /// Shoulder buttons.
      case shoulders
      /// The directional pad.
      case dpad
      /// The sticks.
      case sticks
      /// The triggers.
      case triggers
      /// The stick clicks.
      case clicks
      /// Touch.
      case touch
      /// Motion.
      case motion
      /// System controls.
      case system

      /// The title of the section.
      var title: String {
        switch self {
        case .face:
          return OJDLocalized.string("ui.profiles.sectionFaceButtons")
        case .shoulders:
          return OJDLocalized.string("ui.profiles.sectionShoulders")
        case .dpad: return OJDLocalized.string("ui.profiles.sectionDpad")
        case .sticks: return OJDLocalized.string("ui.profiles.sectionSticks")
        case .triggers: return OJDLocalized.string("ui.profiles.sectionTriggers")
        case .clicks:
          return OJDLocalized.string("ui.profiles.sectionStickClicks")
        case .touch: return OJDLocalized.string("ui.profiles.sectionTouch")
        case .motion: return OJDLocalized.string("ui.profiles.sectionMotion")
        case .system:
          return OJDLocalized.string("ui.profiles.sectionSystemControls")
        }
      }
    }
  }

  /// One section of assignment rows in the profile editor.
  struct AssignmentGroupView: View {
    /// The title of the section.
    let title: String
    /// The assignments in the section.
    let bindings: [RemappingBinding]
    /// What the controller has, which marks unsupported sources and destinations.
    let capabilities: ControllerProfileCapabilities
    /// The profile being edited.
    @Binding
    var draft: RuntimeProfileDraft
    /// Whether the rows ignore edits.
    let isEditingDisabled: Bool
    /// Removes the assignment with the identifier.
    let onRemove: (UUID) -> Void
    /// Shows an error message.
    let onError: (String) -> Void
    /// Opens the sheet that adjusts the axis tuning of an assignment.
    let onAdjust: (RemappingBinding) -> Void
    /// Opens the sheet that edits the behavior of an assignment.
    let onBehavior: (RemappingBinding) -> Void
    /// Called after an edit changed the draft.
    let onEditingStateChanged: () -> Void
    /// Whether the source and destination pickers sit side by side or one above the other.
    let rowLayout: ProfileAssignmentRowLayout

    /// The assignments of the group in a section.
    var body: some View {
      Section(header: Text(title)) {
        ForEach(bindings) { binding in
          AssignmentRow(
            binding: binding,
            capabilities: capabilities,
            draft: $draft,
            isEditingDisabled: isEditingDisabled,
            onRemove: onRemove,
            onError: onError,
            onAdjust: onAdjust,
            onBehavior: onBehavior,
            onEditingStateChanged: onEditingStateChanged,
            layout: rowLayout
          )
        }
      }
    }
  }

  /// The row of one assignment: pickers for its source and destination, and the Adjust,
  /// Behavior and Remove buttons.
  private struct AssignmentRow: View {
    /// The assignment.
    let binding: RemappingBinding
    /// What the controller has, which marks unsupported sources and destinations.
    let capabilities: ControllerProfileCapabilities
    /// The profile being edited.
    @Binding
    var draft: RuntimeProfileDraft
    /// Whether the row ignores edits.
    let isEditingDisabled: Bool
    /// Removes the assignment with the identifier.
    let onRemove: (UUID) -> Void
    /// Shows an error message.
    let onError: (String) -> Void
    /// Opens the sheet that adjusts the axis tuning of the assignment.
    let onAdjust: (RemappingBinding) -> Void
    /// Opens the sheet that edits the behavior of the assignment.
    let onBehavior: (RemappingBinding) -> Void
    /// Called after an edit changed the draft.
    let onEditingStateChanged: () -> Void
    /// Whether the source and destination pickers sit side by side or one above the other.
    let layout: ProfileAssignmentRowLayout

    /// The source, the destination and their fields of one assignment.
    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        if layout == .inline {
          HStack(alignment: .top, spacing: 12) {
            sourceField
            OJDSystemSymbol(name: "arrow.right", fallback: "->").foregroundColor(
              Color(NSColor.secondaryLabelColor)
            ).padding(.top, 25).accessibilityHidden(true)
            destinationField
          }
        } else {
          sourceField
          destinationField
        }

        HStack(spacing: 8) {
          if binding.axisTuning != nil {
            Button(OJDLocalized.string("action.adjust")) {
              onAdjust(binding)
            }.ojdAccessibilityLabel(
              OJDLocalized.formatted(
                "ui.capture.adjust",
                RuntimePresentation.sourceLabel(binding.source)
              )
            )
          }
          Button(OJDLocalized.string("ui.profiles.behavior")) {
            onBehavior(binding)
          }
          Spacer(minLength: 0)
          Button(
            action: { onRemove(binding.id) },
            label: {
              OJDSystemSymbol(name: "minus.circle", fallback: "−").accessibilityHidden(true)
                .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
            }
          ).buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(
            OJDLocalized.string("action.removeAssignment")
          ).help(OJDLocalized.string("action.removeAssignment"))
        }
      }.disabled(isEditingDisabled).frame(maxWidth: .infinity, alignment: .leading).padding(
        .vertical,
        7
      ).ojdAccessibilityLabel(OJDLocalized.string("term.assignment"))
        .ojdAccessibilityValue(assignmentAccessibilityValue)
    }

    /// The picker of the controller control.
    private var sourceField: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(OJDLocalized.string("ui.capture.controllerControl")).font(
          .caption
        ).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker("", selection: sourceBinding) {
          ForEach(
            SourceOption.options(including: binding.source, capabilities: capabilities),
            id: \.source
          ) { option in Text(option.title).tag(option.source).disabled(!option.isSupported) }
        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).ojdAccessibilityLabel(
          OJDLocalized.string("ui.capture.controllerControl")
        ).ojdAccessibilityValue(RuntimePresentation.sourceLabel(binding.source))
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The picker of the destination, with the fields of a physical output and a note when the
    /// controller lacks the source or the destination.
    private var destinationField: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(OJDLocalized.string("term.destination")).font(.caption)
          .foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker("", selection: destinationBinding) {
          ForEach(
            DestinationOption.options(
              for: binding.source,
              including: binding.destination,
              capabilities: capabilities
            ),
            id: \.destination
          ) { option in
            KeyboardDestinationLabel(destination: option.destination).tag(option.destination)
              .disabled(!option.isSupported)
          }
        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).ojdAccessibilityLabel(
          OJDLocalized.string("term.destination")
        ).ojdAccessibilityValue(RuntimePresentation.destinationLabel(binding.destination))
        PhysicalOutputDestinationFields(destination: destinationBinding).disabled(
          !ProfileCapabilityPolicy.supports(binding.destination, capabilities: capabilities)
        )
        if !ProfileCapabilityPolicy.supports(binding.source, capabilities: capabilities)
          || !ProfileCapabilityPolicy.supports(binding.destination, capabilities: capabilities)
        {
          Text(
            OJDLocalized.string(
              "ui.profiles.notSupportedByController"
            )
          ).font(.caption).foregroundColor(Color(NSColor.systemOrange))
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The assignment as VoiceOver reads it; an assignment with axis tuning reads with its own
    /// summary.
    private var assignmentAccessibilityValue: String {
      let source = RuntimePresentation.sourceLabel(binding.source)
      let destination = RuntimePresentation.destinationLabel(binding.destination)
      if binding.axisTuning == nil {
        return OJDLocalized.formatted(
          "ui.profiles.assignmentSummary",
          source,
          destination
        )
      }
      return OJDLocalized.formatted(
        "ui.profiles.assignmentAdjustSummary",
        source,
        destination
      )
    }

    /// The source picker's binding; a refused change shows through ``onError``.
    private var sourceBinding: Binding<RemappingSource> {
      Binding(get: { binding.source }, set: { setSource($0) })
    }

    /// The destination picker's binding; a refused change shows through ``onError``.
    private var destinationBinding: Binding<RemappingDestination> {
      Binding(
        get: { binding.destination },
        set: { destination in
          guard !isEditingDisabled else { return }
          do {
            draft = try draft.settingDestination(destination, for: binding.id)
            onEditingStateChanged()
          } catch { onError(RuntimePresentation.userFacingError(error)) }
        }
      )
    }

    /// Sets the source of the assignment in the draft and reports a refusal through ``onError``.
    private func setSource(_ source: RemappingSource) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.settingSource(source, for: binding.id)
        onEditingStateChanged()
      } catch { onError(RuntimePresentation.userFacingError(error)) }
    }
  }

#endif
