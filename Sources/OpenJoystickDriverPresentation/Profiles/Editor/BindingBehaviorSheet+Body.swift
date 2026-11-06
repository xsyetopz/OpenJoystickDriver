#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension BindingBehaviorSheet {
    /// Receives the behavior, pulse duration in milliseconds, turbo, long hold, double tap and
    /// additional actions when the person chooses Apply.
    typealias SaveAction = (
      RemappingBindingBehavior, Double, RemappingTurbo?, RemappingLongHold?, RemappingDoubleTap?,
      [RemappingAction]
    ) -> Void

    /// The behavior sheet's fields and its Cancel and Apply buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
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
          binding.destination.isContinuous || turboEnabled || longHoldEnabled || doubleTapEnabled
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
          ProfileAdditionalActionsView(
            source: binding.source,
            capabilities: capabilities,
            actions: $additionalActions
          )
        }
        Toggle(OJDLocalized.string("ui.profiles.turbo"), isOn: $turboEnabled)
          .disabled(
            !binding.destination.acceptsTurbo || longHoldEnabled || doubleTapEnabled
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
        Toggle(
          OJDLocalized.string("ui.profiles.doubleTap"),
          isOn: $doubleTapEnabled
        ).disabled(!supportsActivation || turboEnabled || behavior != .hold)
        if doubleTapEnabled {
          valueSlider(
            title: OJDLocalized.string("ui.profiles.tapWindow"),
            value: $doubleTapWindow,
            range: RemappingDoubleTap.windowRange,
            format: "%.0f ms"
          )
          destinationPicker(selection: $doubleTapDestination)
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { dismiss() }
          Button(OJDLocalized.string("action.apply")) {
            onSave(
              behavior,
              pulseDurationMs,
              turboEnabled ? RemappingTurbo(repeatRateHz: turboRate, dutyCycle: turboDuty) : nil,
              longHoldEnabled
                ? RemappingLongHold(durationMs: longHoldDuration, destination: longHoldDestination)
                : nil,
              doubleTapEnabled
                ? RemappingDoubleTap(windowMs: doubleTapWindow, destination: doubleTapDestination)
                : nil,
              additionalActions
            )
            dismiss()
          }
        }
      }.padding(28).frame(width: 470)
    }

    /// Whether the assignment's source can start a long hold or double tap: any discrete source
    /// with a discrete destination.
    private var supportsActivation: Bool {
      switch binding.source {
      case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
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
    ///   - format: The `String(format:)` pattern of the value shown.
    ///   - multiplier: Scales the value before it is formatted, such as 100 for a percentage.
    /// - Returns: The slider with the title and the formatted value.
    private func valueSlider(
      title: String,
      value: Binding<Double>,
      range: ClosedRange<Double>,
      format: String,
      multiplier: Double = 1
    ) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(String(format: format, value.wrappedValue * multiplier)).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          )
        }
        Slider(value: value, in: range).ojdAccessibilityLabel(title)
      }
    }

    /// A picker of the discrete destinations, with the fields of a physical output.
    private func destinationPicker(selection: Binding<RemappingDestination>) -> some View {
      VStack(alignment: .leading, spacing: 8) {
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
