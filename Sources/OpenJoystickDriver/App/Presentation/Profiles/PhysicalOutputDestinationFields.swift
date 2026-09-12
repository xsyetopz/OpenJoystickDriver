#if canImport(SwiftUI)
  import OpenJoystickDriverKit
  import SwiftUI

  struct PhysicalOutputDestinationFields: View {
    @Binding var destination: RemappingDestination

    var body: some View {
      if case .physical(let output) = destination {
        VStack(alignment: .leading, spacing: 8) {
          switch output {
          case .rumble(let motor, let intensity):
            Picker(
              OJDLocalized.string("profiles.physical.motor", fallback: "Motor"),
              selection: rumbleMotor(motor, intensity: intensity)
            ) {
              ForEach(PhysicalRumbleMotor.allCases, id: \.self) {
                Text(RuntimePresentation.humanized($0.rawValue)).tag($0)
              }
            }
            unitSlider(
              OJDLocalized.string("profiles.physical.intensity", fallback: "Intensity"),
              value: rumbleIntensity(motor, intensity: intensity)
            )
          case .playerIndicator(let indicator):
            Picker(
              OJDLocalized.string("profiles.physical.player", fallback: "Player indicator"),
              selection: playerIndicator(indicator)
            ) {
              ForEach(PhysicalPlayerIndicator.allCases, id: \.self) {
                Text(
                  $0 == .off
                    ? OJDLocalized.string("common.disabled", fallback: "Disabled")
                    : String($0.rawValue)
                ).tag($0)
              }
            }
          case .color(let red, let green, let blue):
            colorSlider(
              OJDLocalized.string("profiles.physical.red", fallback: "Red"),
              value: colorComponent(red, green: green, blue: blue, component: 0)
            )
            colorSlider(
              OJDLocalized.string("profiles.physical.green", fallback: "Green"),
              value: colorComponent(red, green: green, blue: blue, component: 1)
            )
            colorSlider(
              OJDLocalized.string("profiles.physical.blue", fallback: "Blue"),
              value: colorComponent(red, green: green, blue: blue, component: 2)
            )
          case .brightness(let intensity):
            unitSlider(
              OJDLocalized.string("profiles.physical.brightness", fallback: "Brightness"),
              value: brightness(intensity)
            )
          case .adaptiveTrigger(let trigger, let effect):
            Picker(
              OJDLocalized.string("profiles.physical.trigger", fallback: "Adaptive trigger"),
              selection: adaptiveTrigger(trigger, effect: effect)
            ) {
              ForEach(PhysicalAdaptiveTrigger.allCases, id: \.self) {
                Text(RuntimePresentation.humanized($0.rawValue)).tag($0)
              }
            }
            Picker(
              OJDLocalized.string("profiles.physical.effect", fallback: "Effect"),
              selection: adaptiveKind(trigger, effect: effect)
            ) {
              ForEach(PhysicalAdaptiveTriggerEffectKind.allCases, id: \.self) {
                Text(RuntimePresentation.humanized($0.rawValue)).tag($0)
              }
            }
            if effect.kind == .resistance {
              unitSlider(
                OJDLocalized.string(
                  "profiles.physical.startPosition", fallback: "Resistance start"
                ),
                value: adaptiveStart(trigger, effect: effect)
              )
              unitSlider(
                OJDLocalized.string("profiles.physical.strength", fallback: "Resistance strength"),
                value: adaptiveStrength(trigger, effect: effect)
              )
            }
          }
        }.padding(.leading, 8)
      }
    }

    private func rumbleMotor(
      _ motor: PhysicalRumbleMotor,
      intensity: Double
    ) -> Binding<PhysicalRumbleMotor> {
      Binding(
        get: { motor },
        set: { destination = .physical(.rumble(motor: $0, intensity: intensity)) }
      )
    }

    private func rumbleIntensity(
      _ motor: PhysicalRumbleMotor,
      intensity: Double
    ) -> Binding<Double> {
      Binding(
        get: { intensity },
        set: { destination = .physical(.rumble(motor: motor, intensity: $0)) }
      )
    }

    private func playerIndicator(_ indicator: PhysicalPlayerIndicator)
      -> Binding<PhysicalPlayerIndicator>
    {
      Binding(get: { indicator }, set: { destination = .physical(.playerIndicator($0)) })
    }

    private func colorComponent(
      _ red: UInt8,
      green: UInt8,
      blue: UInt8,
      component: Int
    ) -> Binding<Double> {
      Binding(
        get: { Double([red, green, blue][component]) },
        set: { value in
          var values = [red, green, blue]
          values[component] = UInt8(value.rounded())
          destination = .physical(.color(red: values[0], green: values[1], blue: values[2]))
        }
      )
    }

    private func brightness(_ intensity: Double) -> Binding<Double> {
      Binding(get: { intensity }, set: { destination = .physical(.brightness($0)) })
    }

    private func adaptiveTrigger(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<PhysicalAdaptiveTrigger> {
      Binding(get: { trigger }, set: { destination = .physical(.adaptiveTrigger($0, effect)) })
    }

    private func adaptiveKind(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<PhysicalAdaptiveTriggerEffectKind> {
      Binding(
        get: { effect.kind },
        set: { kind in
          destination = .physical(
            .adaptiveTrigger(
              trigger,
              kind == .off
                ? .off
                : PhysicalAdaptiveTriggerEffect(
                  kind: .resistance,
                  startPosition: effect.startPosition,
                  strength: effect.strength
                )
            )
          )
        }
      )
    }

    private func adaptiveStart(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<Double> {
      Binding(
        get: { effect.startPosition },
        set: {
          destination = .physical(
            .adaptiveTrigger(
              trigger,
              PhysicalAdaptiveTriggerEffect(
                kind: .resistance, startPosition: $0, strength: effect.strength
              )
            )
          )
        }
      )
    }

    private func adaptiveStrength(
      _ trigger: PhysicalAdaptiveTrigger,
      effect: PhysicalAdaptiveTriggerEffect
    ) -> Binding<Double> {
      Binding(
        get: { effect.strength },
        set: {
          destination = .physical(
            .adaptiveTrigger(
              trigger,
              PhysicalAdaptiveTriggerEffect(
                kind: .resistance, startPosition: effect.startPosition, strength: $0
              )
            )
          )
        }
      )
    }

    private func unitSlider(_ title: String, value: Binding<Double>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(title): \(Int((value.wrappedValue * 100).rounded()))%").font(.caption)
        Slider(value: value, in: 0...1).ojdAccessibilityLabel(title)
      }
    }

    private func colorSlider(_ title: String, value: Binding<Double>) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(title): \(Int(value.wrappedValue))").font(.caption)
        Slider(value: value, in: 0...255, step: 1).ojdAccessibilityLabel(title)
      }
    }
  }
#endif
