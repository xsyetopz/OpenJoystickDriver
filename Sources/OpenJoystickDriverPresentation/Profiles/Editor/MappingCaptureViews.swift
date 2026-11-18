#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Axis adjustment and capture

  /// The sheet that adjusts the axis tuning of an assignment: dead zone, gain, inversion,
  /// response curve and digital activation threshold.
  struct AxisAdjustmentSheet: View {
    /// The assignment whose axis tuning the sheet edits.
    let binding: RemappingBinding
    /// Receives the tuning when the person chooses Save.
    let onSave: (RemappingAxisTuning) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The dead zone.
    @State
    private var deadzone: Double
    /// The gain.
    @State
    private var gain: Double
    /// Whether the axis is inverted.
    @State
    private var inverted: Bool
    /// The response curve.
    @State
    private var curve: RemappingResponseCurve
    /// The digital activation threshold.
    @State
    private var threshold: Double

    /// Creates the sheet on the axis tuning of `binding`, or the default tuning when it has none.
    init(binding: RemappingBinding, onSave: @escaping (RemappingAxisTuning) -> Void) {
      self.binding = binding
      self.onSave = onSave
      let tuning = binding.axisTuning ?? .default
      _deadzone = State(initialValue: tuning.deadzone)
      _gain = State(initialValue: tuning.gain)
      _inverted = State(initialValue: tuning.inverted)
      _curve = State(initialValue: tuning.responseCurve)
      _threshold = State(initialValue: tuning.digitalActivationThreshold)
    }

    /// The axis tuning form and its Cancel and Save buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(
          OJDLocalized.formatted(
            "ui.capture.adjust",
            RuntimePresentation.sourceLabel(binding.source)
          )
        ).font(.headline.weight(.semibold))
        SliderRow(
          title: OJDLocalized.string("ui.capture.deadZone"),
          value: $deadzone,
          help: OJDLocalized.string("ui.capture.deadZoneHelp"),
          range: RemappingAxisTuning.deadzoneRange,
          suffix: "%"
        )
        SliderRow(
          title: OJDLocalized.string("ui.capture.gain"),
          value: $gain,
          help: OJDLocalized.string("ui.capture.gainHelp"),
          range: RemappingAxisTuning.gainRange,
          suffix: "×"
        )
        Toggle(OJDLocalized.string("ui.capture.invertAxis"), isOn: $inverted)
          .help(OJDLocalized.string("ui.capture.invertAxisHelp"))
        Picker(
          OJDLocalized.string("ui.capture.responseCurve"),
          selection: $curve
        ) {
          ForEach(RemappingResponseCurve.allCases, id: \.self) { value in
            Text(value.label).tag(value)
          }
        }.help(OJDLocalized.string("ui.capture.responseCurveHelp"))
        SliderRow(
          title: OJDLocalized.string("ui.capture.digitalThreshold"),
          value: $threshold,
          help: OJDLocalized.string("ui.capture.digitalThresholdHelp"),
          range: RemappingAxisTuning.digitalActivationThresholdRange,
          suffix: "%"
        )
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }.help(OJDLocalized.string("ui.help.cancelSheet"))
          Button(OJDLocalized.string("action.save")) {
            onSave(
              RemappingAxisTuning(
                deadzone: deadzone,
                gain: gain,
                inverted: inverted,
                responseCurve: curve,
                digitalActivationThreshold: threshold
              )
            )
            presentationMode.wrappedValue.dismiss()
          }.help(OJDLocalized.string("ui.help.save"))
        }
      }.ojdSheet(.compact)
    }
  }

  extension RemappingResponseCurve {
    /// The name of the curve in the response curve popups.
    var label: String {
      switch self {
      case .linear: return OJDLocalized.string("ui.capture.linear")
      case .easeIn: return OJDLocalized.string("ui.capture.easeIn")
      case .easeOut: return OJDLocalized.string("ui.capture.easeOut")
      case .smoothStep: return OJDLocalized.string("ui.capture.smoothStep")
      }
    }
  }

  /// A slider with `title` and the value beside it.
  private struct SliderRow: View {
    /// The text above the slider.
    let title: String
    /// The number to edit.
    @Binding
    var value: Double
    /// The tooltip of the slider.
    let help: String
    /// The values the slider allows.
    let range: ClosedRange<Double>
    /// The unit after the value; `%` shows the value as a percentage.
    let suffix: String

    /// The slider and its value.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        HStack {
          Text(title)
          Spacer()
          Text(formattedValue).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Slider(value: $value, in: range).ojdAccessibilityLabel(title).help(help)
      }
    }

    /// The value with its suffix.
    private var formattedValue: String {
      let percent = suffix == "%"
      let shown = percent ? value * 100 : value
      return unsafe String(format: percent ? "%.0f%@" : "%.1f%@", shown, suffix)
    }
  }

  /// The banner that says the profile changed elsewhere, with Reload and Keep Editing buttons.
  struct ConflictBanner: View {
    /// Reloads the stored profile.
    let reload: () -> Void
    /// Keeps the edits in the draft.
    let keepEditing: () -> Void

    /// The banner with its Reload and Keep Editing buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.small) {
        Text(
          OJDLocalized.string(
            "ui.error.profileChanged"
          )
        ).font(.subheadline.weight(.semibold))
        HStack(spacing: OJDSpacing.medium) {
          Button(OJDLocalized.string("action.reload")) { reload() }
            .help(OJDLocalized.string("ui.profiles.reloadHelp"))
          Button(OJDLocalized.string("action.keepEditing")) {
            keepEditing()
          }.help(OJDLocalized.string("ui.profiles.keepEditingHelp"))
        }
      }.padding(10).background(
        RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor))
      )
    }
  }

#endif
