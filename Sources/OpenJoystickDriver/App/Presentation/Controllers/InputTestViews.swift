#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  struct InputTestView: View {
    @ObservedObject var model: InputTestViewModel
    let runtimeViewModel: RuntimeViewModel

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          controllerHeader
          HStack(alignment: .top, spacing: 16) {
            InputTestLiveInputView(
              liveState: model.liveState,
              protocolVariant: model.device?.protocolVariant ?? .unknown,
              mappingFlags: model.device?.mappingFlags ?? []
            ).frame(minWidth: 460, maxWidth: .infinity, alignment: .topLeading)
            diagnosticsColumn.frame(width: 330, alignment: .topLeading)
          }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      }.background(Color(NSColor.windowBackgroundColor)).onReceive(runtimeViewModel.$statusState) {
        state in
        guard case .available(let status) = state else { return }
        model.reconcileStatus(status)
      }
    }

    private var controllerHeader: some View {
      HStack(spacing: 10) {
        Circle().fill(statusColor).frame(width: 8, height: 8)
        Text(statusLabel).font(.subheadline.weight(.semibold))
        if let device = model.device {
          Text(
            "\(reported(device.connection)) · \(device.protocolVariant.displayLabel) · "
              + "\(reported(device.parser)) · \(usbIdentifier(device))"
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Spacer()
      }.accessibilityElement(children: .combine).ojdAccessibilityLabel(
        OJDLocalized.string("inputTest.status", fallback: "Input test status")
      ).ojdAccessibilityValue(statusLabel)
    }

    private var diagnosticsColumn: some View {
      VStack(alignment: .leading, spacing: 16) {
        InputTestAxisValuesView(liveState: model.liveState)
        InputTestOutputControlsView(settings: model.outputSettings) {
          VStack(alignment: .leading, spacing: 16) {
            rumbleGroup
            lightingGroup
            outputErrorView
          }
        }
      }
    }

    @ViewBuilder private var rumbleGroup: some View {
      GroupBox {
        if model.capabilities.supportsRumble {
          VStack(alignment: .leading, spacing: 10) {
            rumbleMotorGrid.disabled(!model.canSendOutput || model.isOutputBusy)
            Divider()
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(OJDLocalized.string("inputTest.duration", fallback: "Duration"))
                Spacer()
                Text("\(Int(model.rumbleDurationMilliseconds)) ms").font(
                  .system(.caption, design: .monospaced)
                )
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
      } label: {
        Text(OJDLocalized.string("inputTest.rumble", fallback: "Rumble")).font(.headline)
      }
    }

    @ViewBuilder private var lightingGroup: some View {
      GroupBox {
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
                  Text("Off").tag(PhysicalPlayerIndicator.off)
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
                PhysicalColorWell(color: colorBinding).frame(width: 44, height: 24)
                Button(OJDLocalized.string("common.apply", fallback: "Apply")) {
                  model.applyColor()
                }
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
      } label: {
        Text(OJDLocalized.string("inputTest.lighting", fallback: "Lighting")).font(.headline)
      }
    }

    @ViewBuilder private var outputErrorView: some View {
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

    @ViewBuilder private func rumbleControl(for motor: PhysicalRumbleMotor) -> some View {
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

    @ViewBuilder private func outputStatus(for operation: InputTestViewModel.OutputOperation)
      -> some View
    {
      switch model.outputState {
      case .running(let current) where current == operation: OJDLoadingIndicator()
      case .succeeded(let current) where current == operation:
        Text(OJDLocalized.string("common.done", fallback: "Done")).foregroundColor(
          Color(NSColor.systemGreen)
        )
      case .failed(let current) where current == operation:
        Text(OJDLocalized.string("common.failed", fallback: "Failed")).foregroundColor(
          Color(NSColor.systemRed)
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

    private var statusLabel: String {
      switch model.sessionState {
      case .idle: return OJDLocalized.string("inputTest.idle", fallback: "Ready")
      case .starting: return OJDLocalized.string("inputTest.starting", fallback: "Starting…")
      case .live: return OJDLocalized.string("inputTest.live", fallback: "Input active")
      case .stale: return OJDLocalized.string("inputTest.stale", fallback: "Input interrupted")
      case .disconnected:
        return OJDLocalized.string("inputTest.disconnected", fallback: "Controller disconnected")
      case .permissionRequired:
        return OJDLocalized.string(
          "inputTest.permissionRequired",
          fallback: "Input Monitoring permission required"
        )
      case .unavailable:
        return OJDLocalized.string("inputTest.unavailable", fallback: "Input unavailable")
      case .error: return OJDLocalized.string("common.failed", fallback: "Failed")
      }
    }

    private var statusColor: Color {
      switch model.sessionState {
      case .live: return Color(NSColor.systemGreen)
      case .starting, .stale: return Color(NSColor.systemOrange)
      case .idle: return Color(NSColor.secondaryLabelColor)
      case .disconnected, .permissionRequired, .unavailable, .error: return Color(NSColor.systemRed)
      }
    }

    private func motorLabel(_ motor: PhysicalRumbleMotor) -> String {
      switch motor {
      case .leftMain: return "Left main"
      case .rightMain: return "Right main"
      case .leftTrigger: return "Left trigger"
      case .rightTrigger: return "Right trigger"
      case .leftHaptic: return "Left haptic"
      case .rightHaptic: return "Right haptic"
      }
    }

    private func reported(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty
        ? OJDLocalized.string("controllers.notReported", fallback: "Not reported") : trimmed
    }

    private func usbIdentifier(_ device: ApplicationServiceDeviceDescription) -> String {
      guard device.vendorID != 0 || device.productID != 0 else {
        return OJDLocalized.string("controllers.notReported", fallback: "Not reported")
      }
      return String(format: "%04X:%04X", device.vendorID, device.productID)
    }
  }

  private struct InputTestOutputControlsView<Content: View>: View {
    @ObservedObject var settings: InputTestOutputSettings
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
  }

  private struct PhysicalColorWell: NSViewRepresentable {
    @Binding var color: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSColorWell {
      let well = NSColorWell()
      well.target = context.coordinator
      well.action = #selector(Coordinator.changed(_:))
      return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
      context.coordinator.parent = self
      well.color = color
    }

    final class Coordinator: NSObject {
      var parent: PhysicalColorWell

      init(parent: PhysicalColorWell) { self.parent = parent }

      @MainActor @objc func changed(_ sender: NSColorWell) { parent.color = sender.color }
    }
  }

#endif
