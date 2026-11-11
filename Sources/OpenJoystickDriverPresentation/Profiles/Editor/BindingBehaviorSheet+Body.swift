#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension BindingBehaviorSheet {
    /// Receives the behavior, pulse duration in milliseconds, turbo, long hold, tap counts,
    /// additional actions and remark (nil when the field is blank) when the person chooses Apply.
    typealias SaveAction = (
      RemappingBindingBehavior, Double, RemappingTurbo?, RemappingLongHold?, [RemappingMultiTap],
      [RemappingAction], String?
    ) -> Void

    /// The behavior sheet's fields and its Cancel and Apply buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.profiles.bindingBehavior")).font(
          .headline.weight(.semibold)
        )
        Picker(
          OJDLocalized.string("ui.profiles.bindingBehavior"),
          selection: $behavior
        ) {
          Text(OJDLocalized.string("ui.profiles.hold")).tag(
            RemappingBindingBehavior.hold
          )
          Text(OJDLocalized.string("ui.profiles.toggle")).tag(
            RemappingBindingBehavior.toggle
          )
          Text(OJDLocalized.string("ui.profiles.tapOnPress")).tag(
            RemappingBindingBehavior.tapOnPress
          )
          Text(OJDLocalized.string("ui.profiles.tapOnRelease")).tag(
            RemappingBindingBehavior.tapOnRelease
          )
          Text(OJDLocalized.string("ui.profiles.pulse")).tag(
            RemappingBindingBehavior.pulse
          )
          Text(OJDLocalized.string("ui.profiles.pressOnly")).tag(
            RemappingBindingBehavior.press
          )
          Text(OJDLocalized.string("ui.profiles.releaseOnly")).tag(
            RemappingBindingBehavior.release
          )
        }.disabled(
          binding.destination.isContinuous || turboEnabled || longHoldEnabled
            || !multiTapEntries.isEmpty
        )
        if behavior == .pulse {
          valueSlider(
            title: OJDLocalized.string("ui.profiles.pulseDuration"),
            value: $pulseDurationMs,
            range: RemappingBinding.pulseDurationRange,
            format: "%.0f ms"
          )
        }
        if showsAdditionalActions {
          TextField(OJDLocalized.string("ui.profiles.remark"), text: $remarkText)
            .ojdAccessibilityLabel(OJDLocalized.string("ui.profiles.remark"))
          ProfileAdditionalActionsView(
            source: binding.source,
            capabilities: capabilities,
            actions: $additionalActions
          )
        }
        Toggle(OJDLocalized.string("ui.profiles.turbo"), isOn: $turboEnabled)
          .disabled(
            !binding.destination.acceptsTurbo || longHoldEnabled || !multiTapEntries.isEmpty
              || behavior != .hold
          )
        if turboEnabled {
          valueSlider(
            title: OJDLocalized.string("ui.profiles.turboRate"),
            value: $turboRate,
            range: RemappingTurbo.repeatRateHzRange,
            format: "%.0f Hz"
          )
          valueSlider(
            title: OJDLocalized.string("ui.profiles.turboDuty"),
            value: $turboDuty,
            range: RemappingTurbo.dutyCycleRange,
            format: "%.0f%%",
            multiplier: 100
          )
          valueSlider(
            title: OJDLocalized.string("ui.profiles.turboDelay"),
            value: $turboDelay,
            range: RemappingTurbo.initialDelayMsRange,
            format: "%.0f ms"
          )
          Toggle(OJDLocalized.string("ui.profiles.turboLimit"), isOn: $turboLimitEnabled)
          if turboLimitEnabled {
            valueSlider(
              title: OJDLocalized.string("ui.profiles.turboMax"),
              value: $turboMax,
              range: Double(
                RemappingTurbo.maxRepeatsRange.lowerBound
              )...Double(
                RemappingTurbo.maxRepeatsRange.upperBound
              ),
              format: "%.0f"
            )
          }
        }
        Divider()
        Toggle(
          OJDLocalized.string("ui.profiles.longHold"),
          isOn: $longHoldEnabled
        ).disabled(!supportsActivation || turboEnabled || behavior != .hold)
        if longHoldEnabled {
          valueSlider(
            title: OJDLocalized.string("ui.profiles.holdDuration"),
            value: $longHoldDuration,
            range: RemappingLongHold.durationRange,
            format: "%.0f ms"
          )
          destinationPicker(selection: $longHoldDestination)
        }
        multiTapSection
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }
          Button(OJDLocalized.string("action.apply")) {
            onSave(
              behavior,
              pulseDurationMs,
              turboEnabled
                ? RemappingTurbo(
                  repeatRateHz: turboRate,
                  dutyCycle: turboDuty,
                  initialDelayMs: turboDelay,
                  maxRepeats: turboLimitEnabled ? Int(turboMax.rounded()) : nil
                ) : nil,
              longHoldEnabled
                ? RemappingLongHold(durationMs: longHoldDuration, destination: longHoldDestination)
                : nil,
              multiTapEntries,
              additionalActions,
              trimmedRemark
            )
            dismiss()
          }
        }
      }.ojdSheet(.regular)
    }

    /// The remark without surrounding whitespace, or nil when it is blank.
    var trimmedRemark: String? {
      let trimmed = remarkText.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether the assignment's source can start a long hold or tap count: any discrete source
    /// with a discrete destination.
    var supportsActivation: Bool {
      switch binding.source {
      case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe,
        .stickRegion, .triggerBand, .touchArea:
        return !binding.destination.isContinuous
      case .axis, .axisDirection: return false
      }
    }

    /// A slider for `value` with `title` and the formatted value beside it.
    ///
    /// - Parameters:
    ///   - title: The text above the slider.
    ///   - value: The number to edit.
    ///   - range: The values the slider allows.
    ///   - format: The `unsafe String(format:)` pattern of the value shown.
    ///   - multiplier: Scales the value before it is formatted, such as 100 for a percentage.
    /// - Returns: The slider with the title and the formatted value.
    func valueSlider(
      title: String,
      value: Binding<Double>,
      range: ClosedRange<Double>,
      format: String,
      multiplier: Double = 1
    ) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        HStack {
          Text(title)
          Spacer()
          Text(unsafe String(format: format, value.wrappedValue * multiplier)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range).ojdAccessibilityLabel(title)
      }
    }

    /// A picker of the discrete destinations, with the fields of a physical output.
    func destinationPicker(selection: Binding<RemappingDestination>) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Picker(
          OJDLocalized.string("term.destination"),
          selection: selection
        ) {
          ForEach(discreteDestinations(including: selection.wrappedValue), id: \.destination) {
            Text($0.title).tag($0.destination)
          }
        }
        PhysicalOutputDestinationFields(destination: selection)
      }
    }

    /// Dismisses the sheet.
    func dismiss() { presentationMode.wrappedValue.dismiss() }
  }

#endif
