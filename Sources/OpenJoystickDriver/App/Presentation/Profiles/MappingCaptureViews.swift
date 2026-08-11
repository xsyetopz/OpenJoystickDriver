#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // MARK: - Axis adjustment and capture

  struct AxisAdjustmentSheet: View {
    let binding: RemappingBinding
    let onSave: (RemappingAxisTuning) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var deadzone: Double
    @State private var gain: Double
    @State private var inverted: Bool
    @State private var curve: RemappingResponseCurve
    @State private var threshold: Double

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

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text("Adjust \(RuntimePresentation.sourceLabel(binding.source))").font(
          .headline.weight(.semibold)
        )
        SliderRow(
          title: "Dead zone",
          value: $deadzone,
          range: RemappingAxisTuning.deadzoneRange,
          suffix: "%"
        )
        SliderRow(title: "Gain", value: $gain, range: RemappingAxisTuning.gainRange, suffix: "×")
        Toggle("Invert axis", isOn: $inverted)
        Picker("Response curve", selection: $curve) {
          ForEach(RemappingResponseCurve.allCases, id: \.self) { value in
            Text(responseCurveLabel(value)).tag(value)
          }
        }
        SliderRow(
          title: "Digital threshold",
          value: $threshold,
          range: RemappingAxisTuning.digitalActivationThresholdRange,
          suffix: "%"
        )
        HStack {
          Spacer()
          Button("Cancel") { presentationMode.wrappedValue.dismiss() }
          Button("Save") {
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
          }
        }
      }.padding(28).frame(width: 430)
    }

    private func responseCurveLabel(_ value: RemappingResponseCurve) -> String {
      switch value {
      case .linear: return "Linear"
      case .easeIn: return "Ease in"
      case .easeOut: return "Ease out"
      case .smoothStep: return "Smooth step"
      }
    }
  }

  private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title)
          Spacer()
          Text(formattedValue).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        Slider(value: $value, in: range)
      }
    }

    private var formattedValue: String {
      let percent = suffix == "%"
      let value = percent ? value * 100 : value
      return String(format: percent ? "%.0f%@" : "%.1f%@", value, suffix)
    }
  }

  struct CaptureAssignmentSheet: View {
    @ObservedObject var viewModel: RuntimeViewModel
    let onAdd: (RemappingSource, RemappingDestination) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var source: RemappingSource = .button(.south)
    @State private var destination: RemappingDestination = .keyboard(key: .space, modifiers: [])
    @State private var keyboardDestinationCleared = false
    @State private var keyboardCaptureActive = false
    @State private var selectedRuntimeIdentifier: String?

    var body: some View {
      VStack(alignment: .leading, spacing: 15) {
        Text("Press a controller control").font(.headline.weight(.semibold))
        Text("Choose a control below, or listen briefly for the next input.").foregroundColor(
          Color(NSColor.secondaryLabelColor)
        ).fixedSize(horizontal: false, vertical: true)
        Picker("Controller control", selection: sourceBinding) {
          ForEach(SourceOption.options(including: source), id: \.source) { option in
            Text(option.title).tag(option.source)
          }
        }
        if !connectedDevices.isEmpty {
          Picker("Controller", selection: selectedDeviceBinding) {
            ForEach(connectedDevices, id: \.runtimeIdentifier) { device in
              Text(device.name).tag(device.runtimeIdentifier)
            }
          }
          if let selector = selectedDeviceSelector {
            Button(isListening ? "Listening…" : "Listen for control") {
              beginListening(for: selector)
            }.disabled(isListening)
          }
        } else {
          Text("Connect a controller to enable live capture. Manual selection is still available.")
            .font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        captureStatus
        Picker("Destination", selection: destinationBinding) {
          ForEach(DestinationOption.options(for: source, including: destination), id: \.destination)
          { option in Text(option.title).tag(option.destination) }
        }.ojdAccessibilityLabel("Destination").ojdAccessibilityValue(destinationAccessibilityValue)
        if case .keyboard = destination {
          KeyboardDestinationCaptureView(
            destination: $destination,
            isCleared: $keyboardDestinationCleared,
            isCapturing: $keyboardCaptureActive
          )
        }
        HStack {
          Spacer()
          Button("Cancel") { cancelCapture() }
          Button("Add assignment") {
            onAdd(source, destination)
            viewModel.cancelInputCapture()
          }.disabled(!canAddAssignment)
        }
      }.padding(28).frame(width: 470).ojdAccessibilityLabel("Controller control capture")
        .background(
          EscapeKeyMonitor(isCapturing: { keyboardCaptureActive }, onEscape: { cancelCapture() })
        ).onAppear { selectInitialDevice() }.onDisappear { stopListening() }.onReceive(
          viewModel.$inputCaptureState
        ) { captureState in
          handleCaptureState(captureState)
          announceCaptureState(captureState)
        }
    }

    private var canAddAssignment: Bool {
      if case .keyboard = destination { return !keyboardDestinationCleared }
      return true
    }

    private var isListening: Bool {
      guard let selectedDeviceSelector else { return false }
      if case .listening(let selector) = viewModel.inputCaptureState {
        return selector == selectedDeviceSelector
      }
      return false
    }

    private var destinationBinding: Binding<RemappingDestination> {
      Binding(
        get: { destination },
        set: {
          destination = $0
          keyboardDestinationCleared = false
        }
      )
    }

    private var sourceBinding: Binding<RemappingSource> {
      Binding(
        get: { source },
        set: { newSource in
          source = newSource
          let options = DestinationOption.options(for: newSource, including: destination)
          if !options.contains(where: { $0.destination == destination }),
            let replacement = options.first
          {
            destination = replacement.destination
          }
          keyboardDestinationCleared = false
        }
      )
    }

    private var connectedDevices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }

    private var selectedDeviceBinding: Binding<String> {
      Binding(
        get: { selectedRuntimeIdentifier ?? connectedDevices.first?.runtimeIdentifier ?? "" },
        set: {
          if selectedRuntimeIdentifier != $0 { stopListening() }
          selectedRuntimeIdentifier = $0
        }
      )
    }

    private var selectedDeviceSelector: RuntimeDeviceSelector? {
      guard
        let device = connectedDevices.first(where: {
          $0.runtimeIdentifier
            == (selectedRuntimeIdentifier ?? connectedDevices.first?.runtimeIdentifier)
        })
      else { return nil }
      return RuntimeDeviceSelector(device: device)
    }

    private func selectInitialDevice() {
      guard selectedRuntimeIdentifier == nil else { return }
      selectedRuntimeIdentifier = connectedDevices.first?.runtimeIdentifier
    }

    private func cancelCapture() {
      stopListening()
      announce("Controller capture canceled.")
      presentationMode.wrappedValue.dismiss()
    }

    private func beginListening(for selector: RuntimeDeviceSelector) {
      viewModel.cancelInputCapture()
      Task { @MainActor in await viewModel.listenForInput(for: selector) }
    }

    private func stopListening() { viewModel.cancelInputCapture() }

    private func announce(_ message: String) {
      NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }

    private func handleCaptureState(_ captureState: RuntimeInputCaptureState) {
      switch captureState {
      case .detected(let selector, _, let detected):
        guard let selectedDeviceSelector, selector == selectedDeviceSelector else { return }
        applyDetectedSource(detected)
      case .received, .unavailable, .error, .idle, .listening: break
      }
    }

    private func applyDetectedSource(_ detected: RemappingSource) {
      source = detected
      let options = DestinationOption.options(for: detected, including: destination)
      if !options.contains(where: { $0.destination == destination }),
        let replacement = options.first
      {
        destination = replacement.destination
      }
      keyboardDestinationCleared = false
    }

    private var destinationAccessibilityValue: String {
      if case .keyboard = destination, keyboardDestinationCleared { return "No key selected" }
      return RuntimePresentation.destinationLabel(destination)
    }

    private var captureStatusAccessibilityValue: String {
      switch viewModel.inputCaptureState {
      case .idle: return "Ready to listen."
      case .listening: return "Listening for a controller control."
      case .received(_, let state):
        if let detected = RuntimePresentation.detectedSource(from: state) {
          return "Detected: \(RuntimePresentation.sourceLabel(detected))."
        }
        return "Input received, but no supported control was identified."
      case .detected(_, _, let detected):
        return "Detected: \(RuntimePresentation.sourceLabel(detected)). "
          + "Destination is ready for selection."
      case .unavailable(_, let message), .error(_, let message): return message
      }
    }

    private func announceCaptureState(_ captureState: RuntimeInputCaptureState) {
      let message: String
      switch captureState {
      case .idle, .received: return
      case .listening: message = "Listening for a controller control. Press Escape to cancel."
      case .detected(let selector, _, let detected):
        guard selectedDeviceSelector == selector else { return }
        message =
          "Detected: \(RuntimePresentation.sourceLabel(detected)). "
          + "Destination is ready for selection."
      case .unavailable(_, let detail): message = detail
      case .error(_, let detail): message = "Capture error. \(detail)"
      }
      NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }

    @ViewBuilder private var captureStatus: some View {
      Group {
        switch viewModel.inputCaptureState {
        case .idle: EmptyView()
        case .listening: Text("Listening for a controller control…")
        case .received(_, let state):
          VStack(alignment: .leading, spacing: 3) {
            if let detected = RuntimePresentation.detectedSource(from: state) {
              Text("Detected: \(RuntimePresentation.sourceLabel(detected))").font(
                .subheadline.weight(.semibold)
              )
            } else {
              Text("Input received, but no supported control was identified.").font(
                .subheadline.weight(.semibold)
              )
            }
            Text(
              state.pressedButtons.isEmpty
                ? "No button is currently held."
                : "Buttons held: \(state.pressedButtons.joined(separator: ", "))"
            )
          }
        case .detected(_, let state, let detected):
          VStack(alignment: .leading, spacing: 3) {
            Text("Detected: \(RuntimePresentation.sourceLabel(detected))").font(
              .subheadline.weight(.semibold)
            )
            Text(
              state.pressedButtons.isEmpty
                ? "No button is currently held."
                : "Buttons held: \(state.pressedButtons.joined(separator: ", "))"
            )
          }
        case .unavailable(_, let message), .error(_, let message):
          Text(message).foregroundColor(Color(NSColor.systemRed))
        }
      }.ojdAccessibilityLabel("Capture status").ojdAccessibilityValue(
        captureStatusAccessibilityValue
      )
    }
  }

  struct ConflictBanner: View {
    let reload: () -> Void
    let keepEditing: () -> Void

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        Text("This profile changed elsewhere. Reload or keep editing.").font(
          .subheadline.weight(.semibold)
        )
        HStack(spacing: 10) {
          Button("Reload") { reload() }
          Button("Keep editing") { keepEditing() }
        }
      }.padding(10).background(
        RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor))
      )
    }
  }

  enum ProfileNameValidation {
    static func trimmedName(_ name: String) -> String {
      name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canCreate(name: String, hasSelectedDevice: Bool) -> Bool {
      hasSelectedDevice && !trimmedName(name).isEmpty
    }
  }

  struct ProfileNameSheet: View {
    let title: String
    let initialName: String
    let devices: [ApplicationServiceDeviceDescription]
    let onCreate: (String, ApplicationServiceDeviceDescription) -> Void
    @Environment(\.presentationMode) private var presentationMode
    @State private var name: String
    @State private var selectedRuntimeIdentifier: String?

    init(
      title: String,
      initialName: String,
      devices: [ApplicationServiceDeviceDescription],
      onCreate: @escaping (String, ApplicationServiceDeviceDescription) -> Void
    ) {
      self.title = title
      self.initialName = initialName
      self.devices = devices
      self.onCreate = onCreate
      _name = State(initialValue: initialName)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(.headline.weight(.semibold))
        TextField("Profile name", text: $name).textFieldStyle(RoundedBorderTextFieldStyle())
        if !name.isEmpty && trimmedName.isEmpty {
          Text("Enter a profile name.").font(.caption).foregroundColor(
            Color(NSColor.systemRed)
          ).fixedSize(horizontal: false, vertical: true).ojdAccessibilityLabel(
            "Profile name validation"
          )
        }
        Picker("Controller", selection: selectedDeviceBinding) {
          ForEach(devices, id: \.runtimeIdentifier) { device in
            Text(device.name).tag(device.runtimeIdentifier)
          }
        }
        HStack {
          Spacer()
          Button("Cancel") { presentationMode.wrappedValue.dismiss() }
          Button("Create") {
            guard canCreate, let device = selectedDevice else { return }
            onCreate(trimmedName, device)
            presentationMode.wrappedValue.dismiss()
          }.disabled(!canCreate)
        }
      }.padding(28).frame(width: 390).onAppear {
        selectedRuntimeIdentifier = devices.first?.runtimeIdentifier
      }
    }

    private var trimmedName: String { ProfileNameValidation.trimmedName(name) }

    private var canCreate: Bool {
      ProfileNameValidation.canCreate(name: name, hasSelectedDevice: selectedDevice != nil)
    }

    private var selectedDeviceBinding: Binding<String> {
      Binding(
        get: { selectedRuntimeIdentifier ?? devices.first?.runtimeIdentifier ?? "" },
        set: { selectedRuntimeIdentifier = $0 }
      )
    }

    private var selectedDevice: ApplicationServiceDeviceDescription? {
      devices.first {
        $0.runtimeIdentifier == (selectedRuntimeIdentifier ?? devices.first?.runtimeIdentifier)
      }
    }
  }

#endif
