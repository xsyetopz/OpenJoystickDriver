#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  /// The sheet that edits the motion tuning of a profile, with the gyro output when it applies.
  struct ProfileMotionSheet: View {
    /// Whether the sheet shows the gyro output fields above the motion fields.
    let showsGyroOutput: Bool
    /// Clears the motion tuning of the profile so that it inherits; nil hides the Inherit button.
    let onInherit: (() -> Void)?
    /// Receives the validated tuning and gyro output when the person chooses Save.
    let onSave: (RemappingMotionTuning, RemappingGyroOutput) -> Void
    /// Dismisses the sheet.
    @Environment(\.presentationMode)
    private var presentationMode
    /// The motion tuning being edited.
    @State
    private var draft: ProfileMotionDraft
    /// The message of the failed validation, or nil.
    @State
    private var errorMessage: String?
    /// The text of each numeric field as typed, by key.
    @State
    private var numericText: [String: String]
    /// The gyro output being edited.
    @State
    private var gyro: ProfileGyroDraft

    /// Creates the sheet on the current motion tuning and gyro output.
    ///
    /// - Parameters:
    ///   - tuning: The motion tuning to edit.
    ///   - output: The gyro output to edit.
    ///   - showsGyroOutput: Whether the sheet shows the gyro output fields.
    ///   - onInherit: Clears the motion tuning; nil hides the Inherit button.
    ///   - onSave: Receives the validated tuning and gyro output.
    init(
      tuning: RemappingMotionTuning,
      output: RemappingGyroOutput,
      showsGyroOutput: Bool = true,
      onInherit: (() -> Void)? = nil,
      onSave: @escaping (RemappingMotionTuning, RemappingGyroOutput) -> Void
    ) {
      self.onSave = onSave
      self.showsGyroOutput = showsGyroOutput
      self.onInherit = onInherit
      _draft = State(initialValue: ProfileMotionDraft(tuning))
      _numericText = State(initialValue: ProfileMotionDraft(tuning).numericText)
      _gyro = State(initialValue: ProfileGyroDraft(output))
    }

    /// The title, the gyro output fields, the motion tuning and the Inherit, Cancel and Save
    /// buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(label("title")).font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: OJDSpacing.medium) {
            if showsGyroOutput {
              ProfileGyroFields(draft: $gyro)
              Divider()
            }
            Picker(label("space"), selection: $draft.space) {
              Text(label("local")).tag(RemappingMotionSpace.local)
              Text(label("player")).tag(RemappingMotionSpace.player)
              Text(label("world")).tag(RemappingMotionSpace.world)
            }.help(tooltip("space"))
            slider(
              "pitchSensitivity",
              value: $draft.pitchSensitivity,
              maximum: 100
            )
            slider("yawSensitivity", value: $draft.yawSensitivity, maximum: 100)
            slider(
              "smoothingHalfTimeMs",
              value: $draft.smoothingHalfTimeMs,
              maximum: 1000
            )
            slider(
              "thresholdDegreesPerSecond",
              value: $draft.thresholdDegreesPerSecond,
              maximum: 1000
            )
            slider(
              "yawRelaxation",
              value: $draft.yawRelaxation,
              maximum: 10
            )
            slider(
              "sideReductionThreshold",
              value: $draft.sideReductionThreshold,
              maximum: 1
            )
            slider(
              "gravityCorrectionRate",
              value: $draft.gravityCorrectionRate,
              maximum: 100
            )
            Toggle(label("invertPitch"), isOn: $draft.invertPitch)
              .help(tooltip("invertPitch"))
            Toggle(label("invertYaw"), isOn: $draft.invertYaw)
              .help(tooltip("invertYaw"))
            Toggle(
              label("automaticBias"),
              isOn: $draft.automaticBias
            )
            .help(tooltip("automaticBias"))
            Divider()
            Toggle(label("leanEnabled"), isOn: $draft.leanEnabled)
              .help(tooltip("leanEnabled"))
            if draft.leanEnabled {
              slider(
                "leanThresholdDegrees",
                value: $draft.leanThresholdDegrees,
                maximum: 89
              )
              slider(
                "leanHysteresisDegrees",
                value: $draft.leanHysteresisDegrees,
                maximum: 30
              )
            }
            Toggle(label("steeringEnabled"), isOn: $draft.steeringEnabled)
              .help(tooltip("steeringEnabled"))
            if draft.steeringEnabled {
              Picker(
                label("steeringOutput"),
                selection: $draft.steeringOutput
              ) {
                Text(label("steeringLeft")).tag(
                  RemappingMotionSteeringOutput.leftStickX
                )
                Text(label("steeringRight")).tag(
                  RemappingMotionSteeringOutput.rightStickX
                )
              }
              .help(tooltip("steeringOutput"))
              slider(
                "steeringDeadzoneDegrees",
                value: $draft.steeringDeadzoneDegrees,
                maximum: 89
              )
              slider(
                "steeringFullScaleDegrees",
                value: $draft.steeringFullScaleDegrees,
                maximum: 90
              )
              slider(
                "steeringResponseExponent",
                value: $draft.steeringResponseExponent,
                maximum: 10
              )
              Toggle(label("steeringInverted"), isOn: $draft.steeringInverted)
                .help(tooltip("steeringInverted"))
            }
          }.padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("action.reset")) {
            draft = ProfileMotionDraft(.default)
            numericText = draft.numericText
            gyro = ProfileGyroDraft(.default)
            errorMessage = nil
          }.help(OJDLocalized.string("ui.help.reset"))
          if let onInherit {
            Button(OJDLocalized.string("ui.profiles.motion.inherit")) {
              onInherit()
              presentationMode.wrappedValue.dismiss()
            }.help(OJDLocalized.string("ui.profiles.motion.inheritHelp"))
          }
          Spacer()
          Button(OJDLocalized.string("action.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }.help(OJDLocalized.string("ui.help.cancel"))
          Button(OJDLocalized.string("action.save")) {
            do {
              let edited = try draft.applyingNumericText(
                numericText,
                decimalSeparator: Locale.current.decimalSeparator ?? "."
              )
              onSave(
                try edited.validatedTuning(),
                try gyro.validatedOutput(decimalSeparator: Locale.current.decimalSeparator ?? ".")
              )
              presentationMode.wrappedValue.dismiss()
            } catch { errorMessage = RuntimePresentation.userFacingError(error) }
          }.help(OJDLocalized.string("ui.help.save"))
        }
      }.ojdSheet(.regular).frame(height: 600)
    }

    /// Returns the text of the motion field called `key`.
    private func label(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.motion." + key)
    }

    /// Returns the tooltip of the motion field called `key`.
    private func tooltip(_ key: String) -> String {
      OJDLocalized.string("ui.profiles.motion." + key + "Help")
    }

    /// A slider with a text field for the number called `key`, from 0 to `maximum`.
    ///
    /// A typed value that is not a number in the range leaves the slider where it was.
    ///
    /// - Parameters:
    ///   - key: The key of the field.
    ///   - value: The number to edit.
    ///   - maximum: The largest value.
    /// - Returns: The slider with its text field.
    private func slider(
      _ key: String,
      value: Binding<Double>,
      maximum: Double
    ) -> some View {
      VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
        HStack {
          Text(label(key))
          Spacer()
          TextField(
            label(key),
            text: Binding(
              get: { numericText[key] ?? String(value.wrappedValue) },
              set: { text in
                numericText[key] = text
                if let parsed = ProfileMotionDraft.numericValue(
                  text,
                  decimalSeparator: Locale.current.decimalSeparator ?? "."
                ), (0...maximum).contains(parsed) {
                  value.wrappedValue = parsed
                }
              }
            )
          ).frame(width: 100).ojdAccessibilityLabel(label(key))
            .help(tooltip(key))
        }
        Slider(
          value: Binding(
            get: { value.wrappedValue },
            set: {
              value.wrappedValue = $0
              numericText[key] = String($0)
            }
          ),
          in: 0...maximum
        ).ojdAccessibilityLabel(label(key)).help(tooltip(key))
      }
    }
  }
#endif
