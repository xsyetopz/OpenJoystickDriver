#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension InputTestView {
    var body: some View {
      GeometryReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            controllerHeader
            dashboard(for: InputTestLayoutPolicy.widthClass(for: proxy.size.width))
          }.padding(18).frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }.background(Color(NSColor.windowBackgroundColor)).onReceive(runtimeViewModel.$statusState) {
        state in
        guard case .available(let status) = state else { return }
        model.reconcileStatus(status)
      }
    }

    private var controllerHeader: some View {
      HStack(spacing: 10) {
        OJDSystemSymbol(name: statusSemanticState.presentation.symbolName, fallback: statusLabel)
          .foregroundColor(Color(statusSemanticState.presentation.tone.color))
          .accessibilityHidden(true)
        Text(statusLabel).font(.subheadline.weight(.semibold))
        if let device = model.device {
          Text(
            "\(reported(device.connection)) · \(device.protocolBinding.displayLabel) · "
              + "\(reported(device.protocolBinding.rawValue)) · \(usbIdentifier(device)) · "
              + device.publishedIdentityLabel
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer()
      }.accessibilityElement(children: .combine).ojdAccessibilityLabel(
        OJDLocalized.string("inputTest.status", fallback: "Input test status")
      ).ojdAccessibilityValue(statusLabel)
    }

    @ViewBuilder
    private func dashboard(for widthClass: InputTestLayoutPolicy.WidthClass) -> some View {
      switch widthClass {
      case .compact:
        VStack(alignment: .leading, spacing: 18) {
          liveInput
          axisValues
          motionGroup
          rumbleGroup
          lightingGroup
        }
      case .regular:
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top, spacing: 18) {
            liveInput
            VStack(alignment: .leading, spacing: 18) {
              axisValues
              motionGroup
            }.frame(width: 260)
          }
          HStack(alignment: .top, spacing: 18) {
            rumbleGroup
            lightingGroup
          }
        }
      case .wide:
        HStack(alignment: .top, spacing: 18) {
          liveInput.frame(minWidth: 380, idealWidth: 420, maxWidth: 480)
          HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
              axisValues
              rumbleGroup
            }
            VStack(alignment: .leading, spacing: 18) {
              motionGroup
              lightingGroup
            }
          }.frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
    }

    private var motionGroup: some View {
      GroupBox {
        MotionCalibrationControls(model: model.motionCalibration, embedded: true)
      } label: {
        Text(OJDLocalized.string("motion.calibration.title", fallback: "Motion calibration"))
      }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var publishedProfile: VirtualDeviceProfile {
      model.device?.publishedVirtualProfile ?? .openJoystickDriverGenericHID
    }

    var liveInput: some View {
      InputTestLiveInputView(
        liveState: model.liveState,
        publishedProfile: publishedProfile,
        embedded: true
      ).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var axisValues: some View {
      GroupBox {
        InputTestAxisValuesView(liveState: model.liveState, embedded: true)
      } label: {
        Text(OJDLocalized.string("inputTest.axisValues", fallback: "Axis values"))
      }
    }

    private var rumbleGroup: some View {
      GroupBox {
        InputTestOutputControlsView(settings: model.outputSettings) {
          VStack(alignment: .leading, spacing: 10) {
            rumbleContent
            if outputErrorBelongs(to: [.rumble]) { outputErrorView }
          }
        }
      } label: {
        Text(OJDLocalized.string("inputTest.rumble", fallback: "Rumble"))
      }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var lightingGroup: some View {
      GroupBox {
        InputTestOutputControlsView(settings: model.outputSettings) {
          VStack(alignment: .leading, spacing: 10) {
            lightingContent
            if outputErrorBelongs(to: [.playerIndicator, .color, .brightness]) { outputErrorView }
          }
        }
      } label: {
        Text(OJDLocalized.string("inputTest.lighting", fallback: "Lighting"))
      }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var rumbleContent: some View {
      if model.capabilities.supportsRumble {
        VStack(alignment: .leading, spacing: 10) {
          rumbleMotorGrid.disabled(!model.canSendOutput || model.isOutputBusy)
          Divider()
          VStack(alignment: .leading, spacing: 5) {
            HStack {
              Text(OJDLocalized.string("inputTest.duration", fallback: "Duration"))
              Spacer()
              Text(
                OJDLocalized.formatted(
                  "inputTest.durationValue",
                  fallback: "%d ms",
                  Int(model.rumbleDurationMilliseconds)
                )
              ).font(.system(.caption, design: .monospaced))
            }
            Slider(value: rumbleDurationBinding, in: 100...2_000, step: 50)
          }.disabled(!model.canSendOutput || model.isOutputBusy)
          HStack(spacing: 8) {
            Button(OJDLocalized.string("inputTest.testRumble", fallback: "Test Rumble")) {
              model.testRumble()
            }.disabled(!model.canSendOutput || model.isOutputBusy)
            Button(OJDLocalized.string("common.stop", fallback: "Stop")) { model.stopRumble() }
              .disabled(!model.canStopRumble)
            Spacer()
            outputStatus(for: .rumble)
          }
        }.padding(4)
      } else {
        unavailableOutputLabel(
          OJDLocalized.string(
            "inputTest.rumbleUnavailable",
            fallback: "Rumble is not supported by this controller."
          )
        )
      }
    }

    @ViewBuilder
    private var lightingContent: some View {
      if model.capabilities.lightingFeatures.isEmpty {
        unavailableOutputLabel(
          OJDLocalized.string(
            "inputTest.lightingUnavailable",
            fallback: "Lighting controls are not available for this controller."
          )
        )
      } else {
        VStack(alignment: .leading, spacing: 12) {
          if model.capabilities.supportsPlayerIndicator {
            VStack(alignment: .leading, spacing: 6) {
              Text(OJDLocalized.string("inputTest.playerIndicator", fallback: "Player indicator"))
              Picker("", selection: playerIndicatorBinding) {
                Text(OJDLocalized.string("inputTest.off", fallback: "Off")).tag(
                  PhysicalPlayerIndicator.off
                )
                Text("1").tag(PhysicalPlayerIndicator.player1)
                Text("2").tag(PhysicalPlayerIndicator.player2)
                Text("3").tag(PhysicalPlayerIndicator.player3)
                Text("4").tag(PhysicalPlayerIndicator.player4)
              }.pickerStyle(.segmented).labelsHidden()
              Button(OJDLocalized.string("common.apply", fallback: "Apply")) {
                model.applyPlayerIndicator()
              }
            }
          }
          if model.capabilities.lightingFeatures.contains(.programmableColor) {
            HStack {
              Text(OJDLocalized.string("inputTest.color", fallback: "Color"))
              Spacer()
              OJDPhysicalColorWell(color: colorBinding).frame(width: 44, height: 24)
              Button(OJDLocalized.string("common.apply", fallback: "Apply")) { model.applyColor() }
            }
          }
          if model.capabilities.supportsProgrammableBrightness {
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(OJDLocalized.string("inputTest.brightness", fallback: "Brightness"))
                Spacer()
                Text("\(Int(model.brightness))").font(.system(.caption, design: .monospaced))
              }
              HStack {
                Slider(value: brightnessBinding, in: 0...255, step: 1)
                Button(OJDLocalized.string("common.apply", fallback: "Apply")) {
                  model.applyBrightness()
                }
              }
            }
          }
        }.padding(4).disabled(!model.canSendOutput || model.isOutputBusy)
      }
    }

    private func outputErrorBelongs(to operations: Set<InputTestViewModel.OutputOperation>) -> Bool
    {
      guard case .failed(let operation) = model.outputState else { return false }
      return operations.contains(operation)
    }

    @ViewBuilder
    private var outputErrorView: some View {
      if let error = model.outputError {
        Text(error).font(.caption).foregroundColor(Color(NSColor.systemRed)).fixedSize(
          horizontal: false,
          vertical: true
        ).ojdAccessibilityLabel(
          OJDLocalized.string("inputTest.outputError", fallback: "Physical output error")
        )
      }
    }

    private var rumbleMotorGrid: some View {
      let motors = model.capabilities.rumbleMotors
      let midpoint = (motors.count + 1) / 2
      return HStack(alignment: .top, spacing: 14) {
        VStack(spacing: 9) {
          ForEach(Array(motors.prefix(midpoint)), id: \.self) { rumbleControl(for: $0) }
        }
        VStack(spacing: 9) {
          ForEach(Array(motors.dropFirst(midpoint)), id: \.self) { rumbleControl(for: $0) }
        }
      }
    }

    @ViewBuilder
    private func rumbleControl(for motor: PhysicalRumbleMotor) -> some View {
      let value = Binding<Double>(
        get: { model.rumbleIntensities[motor] ?? 0 },
        set: { model.rumbleIntensities[motor] = $0 }
      )
      if model.capabilities.binaryRumbleMotors.contains(motor) {
        Toggle(
          motorLabel(motor),
          isOn: Binding(get: { value.wrappedValue > 0 }, set: { value.wrappedValue = $0 ? 255 : 0 })
        )
      } else {
        VStack(alignment: .leading, spacing: 3) {
          HStack {
            Text(motorLabel(motor))
            Spacer()
            Text("\(Int(value.wrappedValue))").font(.system(.caption, design: .monospaced))
          }
          Slider(value: value, in: 0...255, step: 1)
        }
      }
    }

    private func unavailableOutputLabel(_ message: String) -> some View {
      Text(message).font(.subheadline).foregroundColor(Color(NSColor.secondaryLabelColor)).padding(
        4
      ).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func outputStatus(for operation: InputTestViewModel.OutputOperation) -> some View {
      switch model.outputState {
      case .running(let current) where current == operation: ProgressView()
      case .succeeded(let current) where current == operation:
        Text(OJDLocalized.string("common.done", fallback: "Done")).foregroundColor(
          Color(SemanticState.healthy.presentation.tone.color)
        )
      case .failed(let current) where current == operation:
        Text(OJDLocalized.string("common.failed", fallback: "Failed")).foregroundColor(
          Color(SemanticState.failure.presentation.tone.color)
        )
      default: EmptyView()
      }
    }

    private var colorBinding: Binding<NSColor> {
      Binding(
        get: {
          NSColor(
            calibratedRed: model.red / 255,
            green: model.green / 255,
            blue: model.blue / 255,
            alpha: 1
          )
        },
        set: { color in
          let converted = color.usingColorSpace(.deviceRGB) ?? color
          model.red = Double(converted.redComponent * 255)
          model.green = Double(converted.greenComponent * 255)
          model.blue = Double(converted.blueComponent * 255)
        }
      )
    }

    private var rumbleDurationBinding: Binding<Double> {
      Binding(
        get: { model.rumbleDurationMilliseconds },
        set: { model.rumbleDurationMilliseconds = $0 }
      )
    }

    private var playerIndicatorBinding: Binding<PhysicalPlayerIndicator> {
      Binding(get: { model.playerIndicator }, set: { model.playerIndicator = $0 })
    }

    private var brightnessBinding: Binding<Double> {
      Binding(get: { model.brightness }, set: { model.brightness = $0 })
    }
  }

#endif
