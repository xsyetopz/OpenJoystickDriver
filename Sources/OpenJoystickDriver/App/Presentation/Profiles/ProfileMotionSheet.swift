#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileMotionSheet: View {
    let showsGyroOutput: Bool
    let onInherit: (() -> Void)?
    let onSave: (RemappingMotionTuning, RemappingGyroOutput) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var draft: ProfileMotionDraft
    @State private var errorMessage: String?
    @State private var numericText: [String: String]
    @State private var gyro: ProfileGyroDraft

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

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(label("title", "Motion tuning")).font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if showsGyroOutput {
              ProfileGyroFields(draft: $gyro)
              Divider()
            }
            Picker(label("space", "Coordinate space"), selection: $draft.space) {
              Text(label("local", "Local")).tag(RemappingMotionSpace.local)
              Text(label("player", "Player")).tag(RemappingMotionSpace.player)
              Text(label("world", "World")).tag(RemappingMotionSpace.world)
            }
            slider(
              "pitchSensitivity",
              "Pitch sensitivity",
              value: $draft.pitchSensitivity,
              maximum: 100
            )
            slider("yawSensitivity", "Yaw sensitivity", value: $draft.yawSensitivity, maximum: 100)
            slider(
              "smoothingHalfTimeMs",
              "Smoothing half-time (ms)",
              value: $draft.smoothingHalfTimeMs,
              maximum: 1000
            )
            slider(
              "thresholdDegreesPerSecond",
              "Rate threshold (degrees/s)",
              value: $draft.thresholdDegreesPerSecond,
              maximum: 1000
            )
            slider(
              "yawRelaxation",
              "Player yaw relaxation",
              value: $draft.yawRelaxation,
              maximum: 10
            )
            slider(
              "sideReductionThreshold",
              "World side reduction",
              value: $draft.sideReductionThreshold,
              maximum: 1
            )
            slider(
              "gravityCorrectionRate",
              "Gravity correction rate (1/s)",
              value: $draft.gravityCorrectionRate,
              maximum: 100
            )
            Toggle(label("invertPitch", "Invert pitch"), isOn: $draft.invertPitch)
            Toggle(label("invertYaw", "Invert yaw"), isOn: $draft.invertYaw)
            Toggle(
              label("automaticBias", "Automatic stillness calibration"),
              isOn: $draft.automaticBias
            )
            Divider()
            Toggle(label("leanEnabled", "Enable lean sources"), isOn: $draft.leanEnabled)
            if draft.leanEnabled {
              slider(
                "leanThresholdDegrees",
                "Lean threshold (degrees)",
                value: $draft.leanThresholdDegrees,
                maximum: 89
              )
              slider(
                "leanHysteresisDegrees",
                "Lean release hysteresis (degrees)",
                value: $draft.leanHysteresisDegrees,
                maximum: 30
              )
            }
            Toggle(
              label("steeringEnabled", "Enable motion steering"),
              isOn: $draft.steeringEnabled
            )
            if draft.steeringEnabled {
              Picker(
                label("steeringOutput", "Virtual steering axis"), selection: $draft.steeringOutput
              ) {
                Text(label("steeringLeft", "Left stick horizontal")).tag(
                  RemappingMotionSteeringOutput.leftStickX
                )
                Text(label("steeringRight", "Right stick horizontal")).tag(
                  RemappingMotionSteeringOutput.rightStickX
                )
              }
              slider(
                "steeringDeadzoneDegrees",
                "Steering deadzone (degrees)",
                value: $draft.steeringDeadzoneDegrees,
                maximum: 89
              )
              slider(
                "steeringFullScaleDegrees",
                "Full steering angle (degrees)",
                value: $draft.steeringFullScaleDegrees,
                maximum: 90
              )
              slider(
                "steeringResponseExponent",
                "Steering response exponent",
                value: $draft.steeringResponseExponent,
                maximum: 10
              )
              Toggle(label("steeringInverted", "Invert steering"), isOn: $draft.steeringInverted)
            }
          }.padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("common.reset", fallback: "Reset")) {
            draft = ProfileMotionDraft(.default)
            numericText = draft.numericText
            gyro = ProfileGyroDraft(.default)
            errorMessage = nil
          }
          if let onInherit {
            Button(OJDLocalized.string("profiles.motion.inherit", fallback: "Use profile tuning")) {
              onInherit()
              presentationMode.wrappedValue.dismiss()
            }
          }
          Spacer()
          Button(OJDLocalized.string("common.cancel", fallback: "Cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save", fallback: "Save")) {
            do {
              let edited = try draft.applyingNumericText(
                numericText, decimalSeparator: Locale.current.decimalSeparator ?? "."
              )
              onSave(
                try edited.validatedTuning(),
                try gyro.validatedOutput(decimalSeparator: Locale.current.decimalSeparator ?? ".")
              )
              presentationMode.wrappedValue.dismiss()
            } catch { errorMessage = RuntimePresentation.userFacingError(error) }
          }
        }
      }.padding(28).frame(width: 500, height: 600)
    }

    private func label(_ key: String, _ fallback: String) -> String {
      OJDLocalized.string("profiles.motion." + key, fallback: fallback)
    }

    private func slider(
      _ key: String, _ fallback: String, value: Binding<Double>, maximum: Double
    ) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(label(key, fallback))
          Spacer()
          TextField(label(key, fallback), text: Binding(
            get: { numericText[key] ?? String(value.wrappedValue) },
            set: { text in
              numericText[key] = text
              if let parsed = ProfileMotionDraft.numericValue(
                text, decimalSeparator: Locale.current.decimalSeparator ?? "."
              ), (0...maximum).contains(parsed) {
                value.wrappedValue = parsed
              }
            }
          )).frame(width: 100).ojdAccessibilityLabel(label(key, fallback))
        }
        Slider(value: Binding(
          get: { value.wrappedValue },
          set: { value.wrappedValue = $0; numericText[key] = String($0) }
        ), in: 0...maximum).ojdAccessibilityLabel(label(key, fallback))
      }
    }
  }
#endif
