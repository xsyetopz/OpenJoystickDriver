#if os(macOS)
  import OpenJoystickDriverKit
  import SwiftUI

  struct ProfileMotionSheet: View {
    let showsGyroOutput: Bool
    let onInherit: (() -> Void)?
    let onSave: (RemappingMotionTuning, RemappingGyroOutput) -> Void
    @Environment(\.presentationMode)
    private var presentationMode
    @State
    private var draft: ProfileMotionDraft
    @State
    private var errorMessage: String?
    @State
    private var numericText: [String: String]
    @State
    private var gyro: ProfileGyroDraft

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
        Text(label("title")).font(.headline)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            if showsGyroOutput {
              ProfileGyroFields(draft: $gyro)
              Divider()
            }
            Picker(label("space"), selection: $draft.space) {
              Text(label("local")).tag(RemappingMotionSpace.local)
              Text(label("player")).tag(RemappingMotionSpace.player)
              Text(label("world")).tag(RemappingMotionSpace.world)
            }
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
            Toggle(label("invertYaw"), isOn: $draft.invertYaw)
            Toggle(
              label("automaticBias"),
              isOn: $draft.automaticBias
            )
            Divider()
            Toggle(label("leanEnabled"), isOn: $draft.leanEnabled)
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
            }
          }.padding(.trailing, 8)
        }
        if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        HStack {
          Button(OJDLocalized.string("common.reset")) {
            draft = ProfileMotionDraft(.default)
            numericText = draft.numericText
            gyro = ProfileGyroDraft(.default)
            errorMessage = nil
          }
          if let onInherit {
            Button(OJDLocalized.string("profiles.motion.inherit")) {
              onInherit()
              presentationMode.wrappedValue.dismiss()
            }
          }
          Spacer()
          Button(OJDLocalized.string("common.cancel")) {
            presentationMode.wrappedValue.dismiss()
          }
          Button(OJDLocalized.string("common.save")) {
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
          }
        }
      }.padding(28).frame(width: 500, height: 600)
    }

    private func label(_ key: String) -> String {
      OJDLocalized.string("profiles.motion." + key)
    }

    private func slider(
      _ key: String,
      value: Binding<Double>,
      maximum: Double
    ) -> some View {
      VStack(alignment: .leading, spacing: 4) {
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
        ).ojdAccessibilityLabel(label(key))
      }
    }
  }
#endif
