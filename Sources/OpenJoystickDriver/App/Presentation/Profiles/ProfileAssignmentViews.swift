#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  struct BindingGroup {
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

  struct AssignmentGroupView: View {
    let title: String
    let bindings: [RemappingBinding]
    @Binding var draft: RuntimeProfileDraft
    let isEditingDisabled: Bool
    let onRemove: (UUID) -> Void
    let onError: (String) -> Void
    let onAdjust: (RemappingBinding) -> Void
    let onBehavior: (RemappingBinding) -> Void
    let onEditingStateChanged: () -> Void

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.subheadline.weight(.semibold)).padding(.bottom, 5)
          ForEach(bindings) { binding in
            AssignmentRow(
              binding: binding,
              draft: $draft,
              isEditingDisabled: isEditingDisabled,
              onRemove: onRemove,
              onError: onError,
              onAdjust: onAdjust,
              onBehavior: onBehavior,
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
    let isEditingDisabled: Bool
    let onRemove: (UUID) -> Void
    let onError: (String) -> Void
    let onAdjust: (RemappingBinding) -> Void
    let onBehavior: (RemappingBinding) -> Void
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
          OJDSystemSymbol(name: "arrow.right", fallback: "->").foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
          Text(OJDLocalized.string("common.destination", fallback: "Destination")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Picker("", selection: destinationBinding) {
          ForEach(
            DestinationOption.options(for: binding.source, including: binding.destination),
            id: \.destination
          ) { option in
            KeyboardDestinationLabel(destination: option.destination).tag(option.destination)
          }
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
          Button(OJDLocalized.string("profiles.behavior", fallback: "Behavior...")) {
            onBehavior(binding)
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
      }.disabled(isEditingDisabled).frame(maxWidth: .infinity, alignment: .leading).padding(
        .vertical,
        7
      ).ojdAccessibilityLabel(OJDLocalized.string("common.assignment", fallback: "Assignment"))
        .ojdAccessibilityValue(assignmentAccessibilityValue)
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
          guard !isEditingDisabled else { return }
          do {
            draft = try draft.settingDestination(destination, for: binding.id)
            onEditingStateChanged()
          } catch { onError(RuntimePresentation.userFacingError(error)) }
        }
      )
    }

    private func setSource(_ source: RemappingSource) {
      guard !isEditingDisabled else { return }
      do {
        draft = try draft.settingSource(source, for: binding.id)
        onEditingStateChanged()
      } catch { onError(RuntimePresentation.userFacingError(error)) }
    }
  }

#endif
