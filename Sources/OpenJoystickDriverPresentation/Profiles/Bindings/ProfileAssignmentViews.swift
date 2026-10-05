#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  func profileSourceGroup(_ source: RemappingSource) -> String {
    switch source {
    case .button(let button):
      switch button {
      case .leftShoulder, .rightShoulder:
        return OJDLocalized.string("profiles.sectionShoulders")
      case .leftStick, .rightStick:
        return OJDLocalized.string("profiles.sectionStickClicks")
      case .start, .back, .guide, .share, .options, .touchpad, .mute, .leftTriggerClick,
        .rightTriggerClick:
        return OJDLocalized.string("profiles.sectionSystemControls")
      default: return OJDLocalized.string("profiles.sectionFaceButtons")
      }
    case .dpad: return OJDLocalized.string("profiles.sectionDpad")
    case .axis, .axisDirection:
      switch source {
      case .axis(.leftTrigger), .axis(.rightTrigger), .axisDirection(.leftTrigger, _),
        .axisDirection(.rightTrigger, _):
        return OJDLocalized.string("profiles.sectionTriggers")
      default: return OJDLocalized.string("profiles.sectionSticks")
      }
    case .triggerStage: return OJDLocalized.string("profiles.sectionTriggers")
    case .motionLean: return OJDLocalized.string("profiles.sectionMotion")
    case .touchContact, .touchGrid, .touchSwipe:
      return OJDLocalized.string("profiles.sectionTouch")
    }
  }

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
      case touch
      case motion
      case system

      var title: String {
        switch self {
        case .face:
          return OJDLocalized.string("profiles.sectionFaceButtons")
        case .shoulders:
          return OJDLocalized.string("profiles.sectionShoulders")
        case .dpad: return OJDLocalized.string("profiles.sectionDpad")
        case .sticks: return OJDLocalized.string("profiles.sectionSticks")
        case .triggers: return OJDLocalized.string("profiles.sectionTriggers")
        case .clicks:
          return OJDLocalized.string("profiles.sectionStickClicks")
        case .touch: return OJDLocalized.string("profiles.sectionTouch")
        case .motion: return OJDLocalized.string("profiles.sectionMotion")
        case .system:
          return OJDLocalized.string("profiles.sectionSystemControls")
        }
      }
    }
  }

  struct AssignmentGroupView: View {
    let title: String
    let bindings: [RemappingBinding]
    let capabilities: ControllerProfileCapabilities
    @Binding
    var draft: RuntimeProfileDraft
    let isEditingDisabled: Bool
    let onRemove: (UUID) -> Void
    let onError: (String) -> Void
    let onAdjust: (RemappingBinding) -> Void
    let onBehavior: (RemappingBinding) -> Void
    let onEditingStateChanged: () -> Void
    let rowLayout: ProfileAssignmentRowLayout

    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.subheadline.weight(.semibold)).padding(.bottom, 5)
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
            if binding.id != bindings.last?.id { Divider().padding(.leading, 2) }
          }
        }.padding(4)
      }
    }
  }

  private struct AssignmentRow: View {
    let binding: RemappingBinding
    let capabilities: ControllerProfileCapabilities
    @Binding
    var draft: RuntimeProfileDraft
    let isEditingDisabled: Bool
    let onRemove: (UUID) -> Void
    let onError: (String) -> Void
    let onAdjust: (RemappingBinding) -> Void
    let onBehavior: (RemappingBinding) -> Void
    let onEditingStateChanged: () -> Void
    let layout: ProfileAssignmentRowLayout

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
            Button(OJDLocalized.string("common.adjust")) {
              onAdjust(binding)
            }.ojdAccessibilityLabel(
              OJDLocalized.formatted(
                "capture.adjust",
                RuntimePresentation.sourceLabel(binding.source)
              )
            )
          }
          Button(OJDLocalized.string("profiles.behavior")) {
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
            OJDLocalized.string("common.removeAssignment")
          ).help(OJDLocalized.string("common.removeAssignment"))
        }
      }.disabled(isEditingDisabled).frame(maxWidth: .infinity, alignment: .leading).padding(
        .vertical,
        7
      ).ojdAccessibilityLabel(OJDLocalized.string("common.assignment"))
        .ojdAccessibilityValue(assignmentAccessibilityValue)
    }

    private var sourceField: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(OJDLocalized.string("capture.controllerControl")).font(
          .caption
        ).foregroundColor(Color(NSColor.secondaryLabelColor))
        Picker("", selection: sourceBinding) {
          ForEach(
            SourceOption.options(including: binding.source, capabilities: capabilities),
            id: \.source
          ) { option in Text(option.title).tag(option.source).disabled(!option.isSupported) }
        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).ojdAccessibilityLabel(
          OJDLocalized.string("capture.controllerControl")
        ).ojdAccessibilityValue(RuntimePresentation.sourceLabel(binding.source))
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destinationField: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(OJDLocalized.string("common.destination")).font(.caption)
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
          OJDLocalized.string("common.destination")
        ).ojdAccessibilityValue(RuntimePresentation.destinationLabel(binding.destination))
        PhysicalOutputDestinationFields(destination: destinationBinding).disabled(
          !ProfileCapabilityPolicy.supports(binding.destination, capabilities: capabilities)
        )
        if !ProfileCapabilityPolicy.supports(binding.source, capabilities: capabilities)
          || !ProfileCapabilityPolicy.supports(binding.destination, capabilities: capabilities)
        {
          Text(
            OJDLocalized.string(
              "profiles.notSupportedByController"
            )
          ).font(.caption).foregroundColor(Color(NSColor.systemOrange))
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assignmentAccessibilityValue: String {
      let source = RuntimePresentation.sourceLabel(binding.source)
      let destination = RuntimePresentation.destinationLabel(binding.destination)
      if binding.axisTuning == nil {
        return OJDLocalized.formatted(
          "profiles.assignmentSummary",
          source,
          destination
        )
      }
      return OJDLocalized.formatted(
        "profiles.assignmentAdjustSummary",
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
