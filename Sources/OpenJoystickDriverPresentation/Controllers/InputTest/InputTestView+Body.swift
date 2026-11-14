#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// One rumble motor's control.
  ///
  /// It observes the output settings itself, so its slider and value follow each change; rows built
  /// inside `ForEach` are not re-rendered by a parent that observes the settings.
  struct InputTestRumbleMotorControl: View {
    /// The values of the output controls.
    @ObservedObject
    var settings: InputTestOutputSettings
    /// The motor.
    let motor: PhysicalRumbleMotor
    /// The name of the motor.
    let title: String
    /// Whether the motor is full or off, with no intensity.
    let isBinary: Bool

    /// A switch for a binary motor, or a slider for the intensity.
    var body: some View {
      let value = Binding<Double>(
        get: { settings.rumbleIntensities[motor] ?? 0 },
        set: { settings.rumbleIntensities[motor] = $0 }
      )
      if isBinary {
        Toggle(
          title,
          isOn: Binding(get: { value.wrappedValue > 0 }, set: { value.wrappedValue = $0 ? 255 : 0 })
        ).help(OJDLocalized.string("ui.help.rumbleToggle"))
      } else {
        InputTestSliderRow(
          title: title,
          valueText: "\(Int(value.wrappedValue.rounded()))",
          accessibilityLabel: title
        ) {
          Slider(value: value, in: 0...255)
        }
      }
    }
  }

  /// A slider on one form row: the title leads, the slider fills the trailing column and the value
  /// follows in a fixed-width monospaced-digit column so every slider ends at the same edge.
  ///
  /// The row names the slider with `accessibilityLabel` and gives it `valueText` as its value.
  struct InputTestSliderRow<Control: View>: View {
    /// The title of the row.
    let title: String
    /// The value beside the slider.
    let valueText: String
    /// The name VoiceOver reads for the slider.
    let accessibilityLabel: String
    /// The slider.
    let control: Control

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - title: The title of the row.
    ///   - valueText: The value beside the slider.
    ///   - accessibilityLabel: The name VoiceOver reads for the slider.
    ///   - control: The slider.
    init(
      title: String,
      valueText: String,
      accessibilityLabel: String,
      @ViewBuilder control: () -> Control
    ) {
      self.title = title
      self.valueText = valueText
      self.accessibilityLabel = accessibilityLabel
      self.control = control()
    }

    /// The row.
    var body: some View {
      OJDLabeledRow(title) {
        HStack(spacing: OJDSpacing.small) {
          control.labelsHidden().ojdAccessibilityLabel(accessibilityLabel)
            .ojdAccessibilityValue(valueText)
          Text(valueText)
            .font(.system(.body).monospacedDigit())
            .foregroundColor(Color(NSColor.secondaryLabelColor))
            .frame(width: 64, alignment: .trailing)
        }
      }
    }
  }

  extension InputTestView {
    /// The form: the controller header and the sections the controller supports.
    var body: some View {
      Form {
        Section {
          controllerHeader
          GuidedCheckRow(
            check: model.guidedCheck,
            canStart: model.canStartGuidedCheck,
            start: model.startGuidedCheck
          )
        }.ojdInterfaceRow(InputTestRow.status)
        ForEach(model.visibleSections, id: \.self) { section in
          switch section {
          case .liveInput: Section { liveInput }.ojdInterfaceRow(InputTestRow.controlDiagram)
          case .motion:
            Section(header: Text(OJDLocalized.string("ui.motion.calibration.title"))) {
              MotionCalibrationControls(model: model.motionCalibration)
            }
          case .rumble:
            Section(header: Text(OJDLocalized.string("ui.inputTest.rumble"))) {
              InputTestOutputControlsView(settings: model.outputSettings) {
                rumbleContent
                if outputErrorBelongs(to: [.rumble]) { outputErrorView }
              }
            }.ojdInterfaceRow(InputTestRow.rumble)
          case .lighting:
            Section(header: Text(OJDLocalized.string("ui.inputTest.lighting"))) {
              InputTestOutputControlsView(settings: model.outputSettings) {
                lightingContent
                if outputErrorBelongs(to: [.playerIndicator, .color, .brightness]) {
                  outputErrorView
                }
              }
            }.ojdInterfaceRow(InputTestRow.lighting)
          }
        }
        Section(header: Text(OJDLocalized.string("ui.controllers.recalibrate.title"))) {
          ControllerRecalibrationControls(
            gateway: model.gateway,
            selector: model.isDeviceConnected
              ? model.device.map { .session($0.sessionToken) } : nil
          )
        }
      }.ojdGroupedForm().onReceive(runtimeViewModel.$statusState) { state in
        guard case .available(let status) = state else { return }
        model.reconcileStatus(status)
      }
    }

    /// The header: the session state with its symbol, and the connection, protocol and ID of the
    /// controller.
    private var controllerHeader: some View {
      HStack(spacing: OJDSpacing.medium) {
        OJDSystemSymbol(name: statusSemanticState.presentation.symbolName, fallback: statusLabel)
          .foregroundColor(Color(statusSemanticState.presentation.tone.color))
          .accessibilityHidden(true)
        Text(statusLabel).font(.subheadline.weight(.semibold))
        if let device = model.device {
          Text(
            "\(OJDValue.reported(device.connection).displayText) · "
              + "\(device.protocolBinding.displayName) · "
              + usbIdentifier(device).displayText
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer()
      }.accessibilityElement(children: .combine).ojdAccessibilityLabel(
        OJDLocalized.string("ui.inputTest.status")
      ).ojdAccessibilityValue(statusLabel)
    }

    /// The glyphs of the identity the Controllers list shows for this controller; the generic
    /// glyphs when no controller is selected.
    private var presentation: VirtualIdentityPresentation {
      Self.presentation(of: model.device)
    }

    /// Returns the identity glyphs of the controller, or the generic glyphs for none.
    ///
    /// - Parameter device: The selected controller, or nil.
    /// - Returns: The identity glyphs of the controller, or the generic glyphs for none.
    static func presentation(
      of device: ApplicationServiceDeviceDescription?
    ) -> VirtualIdentityPresentation {
      device?.publishedIdentityPresentation ?? .generic
    }

    /// The live input of the controller.
    var liveInput: some View {
      InputTestLiveInputView(
        liveState: model.liveState,
        presentation: presentation,
        layout: model.controlLayout
      ).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The rumble controls, or the note that the controller has no rumble.
    @ViewBuilder
    private var rumbleContent: some View {
      if model.capabilities.supportsRumble {
        Group {
          ForEach(model.capabilities.rumbleMotors, id: \.self) { rumbleControl(for: $0) }
          Text(OJDLocalized.string("ui.inputTest.rumbleAppliesOnTest")).font(.caption)
            .foregroundColor(Color(NSColor.secondaryLabelColor))
          InputTestSliderRow(
            title: OJDLocalized.string("ui.inputTest.duration"),
            valueText: OJDLocalized.formatted(
              "ui.inputTest.durationValue",
              Int(model.rumbleDurationMilliseconds)
            ),
            accessibilityLabel: OJDLocalized.string("ui.inputTest.duration")
          ) {
            Slider(
              value: rumbleDurationBinding,
              in: Double(
                InputTestViewModel.rumbleDurationRange.lowerBound
              )...Double(
                InputTestViewModel.rumbleDurationRange.upperBound
              ),
              step: 50
            )
          }
        }.disabled(!model.canSendOutput || model.isOutputBusy)
        HStack(spacing: OJDSpacing.small) {
          Button(OJDLocalized.string("ui.inputTest.testRumble")) {
            model.testRumble()
          }.disabled(!model.canSendOutput || model.isOutputBusy)
            .help(OJDLocalized.string("ui.help.testRumble"))
          Button(OJDLocalized.string("action.stop")) { model.stopRumble() }
            .disabled(!model.canStopRumble).help(OJDLocalized.string("ui.help.stopRumble"))
          Spacer()
          outputStatus(for: .rumble)
        }
      } else {
        unavailableOutputLabel(OJDLocalized.string("ui.inputTest.rumbleUnavailable"))
      }
    }

    /// The player indicator, color and brightness controls that the controller supports.
    @ViewBuilder
    private var lightingContent: some View {
      Group {
        if model.capabilities.supportsPlayerIndicator {
          VStack(alignment: .leading, spacing: OJDSpacing.small) {
            Text(OJDLocalized.string("ui.inputTest.playerIndicator"))
            HStack {
              Picker("", selection: playerIndicatorBinding) {
                Text(OJDLocalized.string("ui.inputTest.off")).tag(PhysicalPlayerIndicator.off)
                Text("1").tag(PhysicalPlayerIndicator.player1)
                Text("2").tag(PhysicalPlayerIndicator.player2)
                Text("3").tag(PhysicalPlayerIndicator.player3)
                Text("4").tag(PhysicalPlayerIndicator.player4)
              }.pickerStyle(.segmented).labelsHidden()
                .ojdAccessibilityLabel(OJDLocalized.string("ui.inputTest.playerIndicator"))
                .help(OJDLocalized.string("ui.help.playerIndicator"))
              outputStatus(for: .playerIndicator)
            }
          }
        }
        if model.capabilities.lightingFeatures.contains(.programmableColor) {
          OJDLabeledRow(OJDLocalized.string("ui.inputTest.color")) {
            HStack {
              OJDPhysicalColorWell(color: colorBinding).frame(width: 44, height: 24)
              Button(OJDLocalized.string("action.apply")) { model.applyColor() }
                .help(OJDLocalized.string("ui.help.applyLight"))
            }
          }
        }
        if model.capabilities.supportsProgrammableBrightness {
          VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
            HStack {
              Text(OJDLocalized.string("ui.inputTest.brightness"))
              Spacer()
              Text("\(Int(model.brightness.rounded()))").font(
                .system(.body, design: .monospaced)
              )
            }
            HStack {
              Slider(value: brightnessBinding, in: 0...255)
                .ojdAccessibilityLabel(OJDLocalized.string("ui.inputTest.brightness"))
                .ojdAccessibilityValue("\(Int(model.brightness.rounded()))")
              Button(OJDLocalized.string("action.apply")) { model.applyBrightness() }
                .help(OJDLocalized.string("ui.help.applyLight"))
            }
          }
        }
      }.disabled(!model.canSendOutput || model.isOutputBusy)
    }

    /// Returns whether the latest failed output test is one of `operations`.
    ///
    /// - Parameter operations: The output tests of the section.
    /// - Returns: Whether the latest failed output test is one of `operations`.
    private func outputErrorBelongs(to operations: Set<InputTestViewModel.OutputOperation>) -> Bool
    {
      guard case .failed(let operation) = model.outputState else { return false }
      return operations.contains(operation)
    }

    /// The message of the failed output test.
    @ViewBuilder
    private var outputErrorView: some View {
      if let error = model.outputError {
        Text(error).font(.body).foregroundColor(Color(NSColor.systemRed)).fixedSize(
          horizontal: false,
          vertical: true
        ).ojdAccessibilityLabel(
          OJDLocalized.string("ui.inputTest.outputError")
        )
      }
    }

    /// Returns the control of one rumble motor.
    ///
    /// - Parameter motor: The motor.
    /// - Returns: The control of one rumble motor.
    private func rumbleControl(for motor: PhysicalRumbleMotor) -> some View {
      InputTestRumbleMotorControl(
        settings: model.outputSettings,
        motor: motor,
        title: motor.title,
        isBinary: model.capabilities.binaryRumbleMotors.contains(motor)
      )
    }

    /// Returns the note that an output is unavailable.
    ///
    /// - Parameter message: The text of the note.
    /// - Returns: The note that an output is unavailable.
    private func unavailableOutputLabel(_ message: String) -> some View {
      Text(message).foregroundColor(Color(NSColor.secondaryLabelColor))
    }

    /// Returns the progress, Done or Failed for the latest output test of `operation`.
    ///
    /// - Parameter operation: The output test.
    /// - Returns: The progress, Done or Failed for the latest output test of `operation`.
    @ViewBuilder
    private func outputStatus(for operation: InputTestViewModel.OutputOperation) -> some View {
      switch model.outputState {
      case .running(let current) where current == operation: ProgressView()
      case .succeeded(let current) where current == operation:
        Text(OJDLocalized.string("action.done")).foregroundColor(
          Color(SemanticState.healthy.presentation.tone.color)
        )
      case .failed(let current) where current == operation:
        Text(OJDLocalized.string("status.failed")).foregroundColor(
          Color(SemanticState.failure.presentation.tone.color)
        )
      default: EmptyView()
      }
    }

    /// The binding between the color well and the red, green and blue values.
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

    /// The binding to the rumble test length.
    private var rumbleDurationBinding: Binding<Double> {
      Binding(
        get: { model.rumbleDurationMilliseconds },
        set: { model.rumbleDurationMilliseconds = $0 }
      )
    }

    /// The binding to the player indicator; choosing one applies it.
    private var playerIndicatorBinding: Binding<PhysicalPlayerIndicator> {
      Binding(get: { model.playerIndicator }, set: { model.choosePlayerIndicator($0) })
    }

    /// The binding to the brightness.
    private var brightnessBinding: Binding<Double> {
      Binding(get: { model.brightness }, set: { model.brightness = $0 })
    }
  }

#endif
