import OpenJoystickDriverKit
import SwiftUI

extension InputTestWindowView {
  func outputTestRow(_ device: DeviceViewModel) -> some View {
    let capabilities = device.physicalOutputCapabilities
    let canRumble = capabilities.supportsRumble
    return OJDCard(title: L10n.string("input.rumbleTest")) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(
            canRumble
              ? L10n.string("input.rumbleSendShort")
              : L10n.string("input.rumbleUnavailable")
          )
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Text(capabilities.evidence.rawValue)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
          Text(canRumble ? L10n.string("input.supported") : L10n.string("input.unavailable"))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(canRumble ? .green : .secondary)
        }
        Text(
          L10n.string(
            "input.outputCapabilities",
            physicalOutputNames(capabilities.rumbleMotors.map {
              capabilities.binaryRumbleMotors.contains($0) ? "\($0.rawValue)[0/1]" : $0.rawValue
            }),
            physicalOutputNames(capabilities.lightingFeatures.map(\.rawValue))
          )
        )
          .font(.caption)
          .foregroundColor(.secondary)
        VStack(alignment: .leading, spacing: 7) {
          Text(L10n.string("input.motors"))
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
              RumbleSlider(label: L10n.string("input.left"), value: $rumbleLeft)
              RumbleSlider(label: L10n.string("input.right"), value: $rumbleRight)
            }
            if capabilities.supportsTriggerRumble {
              VStack(alignment: .leading, spacing: 5) {
                RumbleSlider(label: "LT", value: $rumbleLT)
                RumbleSlider(label: "RT", value: $rumbleRT)
              }
            }
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            rumbleIconButton(
              rumbleRunning ? L10n.string("input.sending") : L10n.string("input.pulse"),
              systemName: rumbleRunning ? "hourglass" : "dot.radiowaves.left.and.right"
            ) {
              sendRumble(to: device, durationMs: Int(rumbleDurationMs))
            }
            .disabled(rumbleRunning || !canRumble)
            rumbleIconButton(L10n.string("input.hold"), systemName: "infinity") {
              sendRumble(to: device, durationMs: 0)
            }
            .disabled(!canRumble)
            rumbleIconButton(L10n.string("input.stop"), systemName: "stop.fill") {
              sendRumble(to: device, left: 0, right: 0, lt: 0, rt: 0, durationMs: 0)
            }
            .disabled(!canRumble)
            Divider().frame(height: 18)
            Stepper(
              L10n.string("input.durationMs", Int(rumbleDurationMs)),
              value: $rumbleDurationMs,
              in: 50...5000,
              step: 50
            )
              .font(.caption)
              .frame(width: 160)
          }
          HStack(spacing: 8) {
            rumbleIconButton(L10n.string("input.leftMotor"), systemName: "l.circle") {
              sendRumble(
                to: device,
                left: UInt8(clamping: Int(rumbleLeft)),
                right: 0,
                lt: 0,
                rt: 0
              )
            }
            .disabled(rumbleRunning || !canRumble)
            rumbleIconButton(L10n.string("input.rightMotor"), systemName: "r.circle") {
              sendRumble(
                to: device,
                left: 0,
                right: UInt8(clamping: Int(rumbleRight)),
                lt: 0,
                rt: 0
              )
            }
            .disabled(rumbleRunning || !canRumble)
            Divider().frame(height: 16)
            rumbleIconButton(L10n.string("input.low"), systemName: "speaker.wave.1.fill") {
              setRumbleValues(
                left: 32,
                right: 32,
                lt: 32,
                rt: 32,
                includeTriggers: capabilities.supportsTriggerRumble
              )
            }
            rumbleIconButton(L10n.string("input.mid"), systemName: "speaker.wave.2.fill") {
              setRumbleValues(
                left: 128,
                right: 128,
                lt: 128,
                rt: 128,
                includeTriggers: capabilities.supportsTriggerRumble
              )
            }
            rumbleIconButton(L10n.string("input.max"), systemName: "speaker.wave.3.fill") {
              setRumbleValues(
                left: 255,
                right: 255,
                lt: 255,
                rt: 255,
                includeTriggers: capabilities.supportsTriggerRumble
              )
            }
            rumbleIconButton(L10n.string("input.zero"), systemName: "speaker.slash.fill") {
              setRumbleValues(
                left: 0,
                right: 0,
                lt: 0,
                rt: 0,
                includeTriggers: capabilities.supportsTriggerRumble
              )
            }
          }
          HStack(spacing: 8) {
            if let rumbleResult {
              Text(L10n.string("input.lastCommand", rumbleResult))
                .font(.caption)
                .foregroundColor(.secondary)
            } else {
              Text(L10n.string("input.rumblePhysicalOnly"))
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
          if capabilities.supportsPlayerIndicator {
            Divider()
            HStack(spacing: 8) {
              Text(L10n.string("input.playerIndicator"))
                .font(.caption.weight(.semibold))
              Picker("", selection: $playerIndicator) {
                ForEach(PhysicalPlayerIndicator.allCases, id: \.rawValue) { indicator in
                  Text(playerIndicatorLabel(indicator)).tag(indicator)
                }
              }
              .labelsHidden()
              .frame(width: 110)
              SwiftUI.Button(L10n.string("input.apply")) {
                sendPlayerIndicator(to: device)
              }
              .disabled(playerIndicatorRunning)
              if let playerIndicatorResult {
                Text(playerIndicatorResult)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
          if capabilities.supportsProgrammableBrightness {
            Divider()
            HStack(spacing: 8) {
              Text(L10n.string("input.brightness"))
                .font(.caption.weight(.semibold))
              Slider(value: $physicalBrightness, in: 0...255, step: 1)
                .frame(width: 150)
              Text("\(Int(physicalBrightness))")
                .font(.caption.monospacedDigit())
                .frame(width: 28, alignment: .trailing)
              SwiftUI.Button(L10n.string("input.apply")) {
                sendPhysicalBrightness(to: device)
              }
              .disabled(physicalBrightnessRunning)
              if let physicalBrightnessResult {
                Text(physicalBrightnessResult)
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
          if capabilities.lightingFeatures.contains(.programmableColor) {
            Divider()
            VStack(alignment: .leading, spacing: 7) {
              HStack(spacing: 8) {
                Text(L10n.string("input.lightbarColor"))
                  .font(.caption.weight(.semibold))
                Spacer()
                SwiftUI.Button(L10n.string("input.apply")) {
                  sendPhysicalColor(to: device)
                }
                .disabled(physicalColorRunning)
                if let physicalColorResult {
                  Text(physicalColorResult)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }
              HStack(spacing: 10) {
                colorChannelSlider("R", value: $physicalColorRed)
                colorChannelSlider("G", value: $physicalColorGreen)
                colorChannelSlider("B", value: $physicalColorBlue)
              }
            }
          }
          let validationPlan = PhysicalOutputValidationPlan(
            vendorID: device.vendorID,
            productID: device.productID,
            parser: device.parser,
            capabilities: device.physicalOutputCapabilities
          )
          if !validationPlan.steps.isEmpty {
            Divider()
            SwiftUI.Button {
              showPhysicalOutputValidationPlan.toggle()
            } label: {
              HStack {
                Text(L10n.string("input.validationPlan"))
                  .font(.caption.weight(.semibold))
                Spacer()
                Text(showPhysicalOutputValidationPlan ? "−" : "+")
                  .font(.caption.weight(.semibold))
              }
            }
            .buttonStyle(.plain)
            if showPhysicalOutputValidationPlan {
                VStack(alignment: .leading, spacing: 8) {
                  ForEach(Array(validationPlan.steps.enumerated()), id: \.element.id) { index, step in
                    VStack(alignment: .leading, spacing: 2) {
                      Text("\(index + 1). \(step.id)")
                        .font(.caption.weight(.semibold))
                      Text(step.command)
                        .font(.system(size: 10, design: .monospaced))
                      Text(L10n.string("input.expectedObservation", step.expectedObservation))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                  }
                  Text(L10n.string("input.planIncludedInReport"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 6)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  func rumbleIconButton(
    _ title: String,
    systemName: String,
    action: @escaping () -> Void
  ) -> some View {
    SwiftUI.Button(action: action) {
      if #available(macOS 11.0, *) {
        VStack(spacing: 3) {
          Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
          Text(rumbleGlyphCaption(title))
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
        }
        .frame(width: 44, height: 36)
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
      } else {
        Text(title)
          .font(.caption)
          .frame(width: 44, height: 36)
      }
    }
    .buttonStyle(.borderless)
  }

  @ViewBuilder
  func colorChannelSlider(_ label: String, value: Binding<Double>) -> some View {
    HStack(spacing: 4) {
      Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced))
      Slider(value: value, in: 0...255, step: 1).frame(width: 90)
      Text("\(Int(value.wrappedValue))")
        .font(.caption.monospacedDigit())
        .frame(width: 26, alignment: .trailing)
    }
  }

  func rumbleGlyphCaption(_ title: String) -> String {
    if title == L10n.string("input.sending") { return "sending" }
    if title == L10n.string("input.pulse") { return "pulse" }
    if title == L10n.string("input.hold") { return "hold" }
    if title == L10n.string("input.stop") { return "stop" }
    if title == L10n.string("input.leftMotor") { return "L" }
    if title == L10n.string("input.rightMotor") { return "R" }
    if title == L10n.string("input.low") { return "low" }
    if title == L10n.string("input.mid") { return "mid" }
    if title == L10n.string("input.max") { return "max" }
    if title == L10n.string("input.zero") { return "zero" }
    return title
  }

  func sendRumble(
    to device: DeviceViewModel,
    left: UInt8? = nil,
    right: UInt8? = nil,
    lt: UInt8? = nil,
    rt: UInt8? = nil,
    durationMs: Int? = nil
  ) {
    rumbleRunning = true
    rumbleResult = nil
    Task {
      let motors = device.physicalOutputCapabilities.rumbleMotors
      let ok = await model.sendPhysicalRumble(
        vendorID: device.vendorID,
        productID: device.productID,
        left: motors.contains(.leftMain) || motors.contains(.leftHaptic)
          ? left ?? UInt8(clamping: Int(rumbleLeft)) : 0,
        right: motors.contains(.rightMain) || motors.contains(.rightHaptic)
          ? right ?? UInt8(clamping: Int(rumbleRight)) : 0,
        lt: motors.contains(.leftTrigger) ? lt ?? UInt8(clamping: Int(rumbleLT)) : 0,
        rt: motors.contains(.rightTrigger) ? rt ?? UInt8(clamping: Int(rumbleRT)) : 0,
        durationMs: durationMs ?? Int(rumbleDurationMs)
      )
      rumbleResult = ok ? L10n.string("input.rumbleSent") : L10n.string("input.rumbleNotAvailable")
      rumbleRunning = false
    }
  }

  func setRumbleValues(
    left: Double, right: Double, lt: Double, rt: Double, includeTriggers: Bool
  ) {
    rumbleLeft = left
    rumbleRight = right
    rumbleLT = includeTriggers ? lt : 0
    rumbleRT = includeTriggers ? rt : 0
  }

  func sendPlayerIndicator(to device: DeviceViewModel) {
    playerIndicatorRunning = true
    playerIndicatorResult = nil
    Task {
      let ok = await model.setPhysicalPlayerIndicator(
        vendorID: device.vendorID,
        productID: device.productID,
        indicator: playerIndicator
      )
      playerIndicatorResult = L10n.string(
        ok ? "input.indicatorSent" : "input.indicatorNotAvailable"
      )
      playerIndicatorRunning = false
    }
  }

  func sendPhysicalColor(to device: DeviceViewModel) {
    physicalColorRunning = true
    physicalColorResult = nil
    Task {
      let ok = await model.setPhysicalColor(
        vendorID: device.vendorID,
        productID: device.productID,
        red: UInt8(clamping: Int(physicalColorRed)),
        green: UInt8(clamping: Int(physicalColorGreen)),
        blue: UInt8(clamping: Int(physicalColorBlue))
      )
      physicalColorResult = L10n.string(
        ok ? "input.colorSent" : "input.colorNotAvailable"
      )
      physicalColorRunning = false
    }
  }

  func sendPhysicalBrightness(to device: DeviceViewModel) {
    physicalBrightnessRunning = true
    physicalBrightnessResult = nil
    Task {
      let ok = await model.setPhysicalBrightness(
        vendorID: device.vendorID,
        productID: device.productID,
        brightness: UInt8(clamping: Int(physicalBrightness))
      )
      physicalBrightnessResult = L10n.string(
        ok ? "input.brightnessSent" : "input.brightnessNotAvailable"
      )
      physicalBrightnessRunning = false
    }
  }

  func playerIndicatorLabel(_ indicator: PhysicalPlayerIndicator) -> String {
    indicator == .off
      ? L10n.string("input.off")
      : L10n.string("input.playerNumber", indicator.rawValue)
  }

  func physicalOutputNames(_ values: [String]) -> String {
    values.isEmpty ? L10n.string("input.none") : values.joined(separator: ", ")
  }
}
