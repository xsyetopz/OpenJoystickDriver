#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  extension CaptureAssignmentSheet {

    /// The control picker, the destination and the Cancel and Add Assignment buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.capture.pressControl"))
          .font(.headline.weight(.semibold))
        Text(
          OJDLocalized.string(
            "ui.capture.chooseControl"
          )
        ).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )

        Picker(
          OJDLocalized.string("ui.capture.controllerControl"),
          selection: sourceBinding
        ) {
          ForEach(SourceOption.options(including: source, capabilities: capabilities), id: \.source)
          { option in Text(option.title).tag(option.source).disabled(!option.isSupported) }
        }.ojdAccessibilityLabel(OJDLocalized.string("ui.capture.controllerControl"))

        touchSourceControls
        if !connectedDevices.isEmpty {
          Picker(
            OJDLocalized.string("term.controller"),
            selection: selectedDeviceBinding
          ) {
            ForEach(connectedDevices, id: \.sessionToken) { device in
              Text(device.name).tag(device.sessionToken.rawValue)
            }
          }.ojdAccessibilityLabel(OJDLocalized.string("term.controller"))
          if let selector = selectedDeviceSelector {
            Button(
              isListening
                ? OJDLocalized.string("ui.capture.listeningButton")
                : OJDLocalized.string("ui.capture.listen")
            ) { beginListening(for: selector) }.disabled(isListening)
          }
        } else {
          Text(
            OJDLocalized.string(
              "ui.capture.connectForLive"
            )
          ).font(.caption).foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        captureStatus
        Picker(
          OJDLocalized.string("term.destination"),

          selection: destinationBinding
        ) {
          ForEach(
            DestinationOption.options(
              for: source,
              including: destination,
              capabilities: capabilities,
              macros: macros
            ),
            id: \.destination
          ) { option in Text(option.title).tag(option.destination).disabled(!option.isSupported) }
        }.ojdAccessibilityLabel(OJDLocalized.string("term.destination"))

          .ojdAccessibilityValue(destinationAccessibilityValue)
        if case .keyboard = destination {
          KeyboardDestinationCaptureView(
            destination: $destination,
            isCleared: $keyboardDestinationCleared,
            isCapturing: $keyboardCaptureActive
          )
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { cancelCapture() }
          Button(OJDLocalized.string("action.addAssignment")) {
            onAdd(source, destination)
            viewModel.cancelInputCapture()
          }.disabled(!canAddAssignment)
        }
      }.ojdSheet(.regular).accessibilityElement(children: .contain)
        .ojdAccessibilityLabel(OJDLocalized.string("ui.capture.title")).background(
          EscapeKeyMonitor(isCapturing: { keyboardCaptureActive }, onEscape: { cancelCapture() })
        ).onAppear { selectInitialDevice() }.onDisappear { stopListening() }.onReceive(
          viewModel.$inputCaptureState
        ) { captureState in
          handleCaptureState(captureState)
          announceCaptureState(captureState)
        }
    }

    /// The step controls of a touch grid or swipe source; any other source shows none.
    @ViewBuilder
    private var touchSourceControls: some View {
      switch source {
      case .touchGrid(let grid):
        VStack(alignment: .leading, spacing: OJDSpacing.small) {
          Stepper(
            OJDLocalized.formatted(
              "ui.capture.touchColumns",
              grid.columns
            ),
            value: touchGridValue(\.columns),
            in: RemappingTouchGridSource.dimensionRange
          )
          Stepper(
            OJDLocalized.formatted("ui.capture.touchRows", grid.rows),
            value: touchGridValue(\.rows),
            in: RemappingTouchGridSource.dimensionRange
          )
          Stepper(
            OJDLocalized.formatted(
              "ui.capture.touchColumn",
              grid.column + 1
            ),
            value: touchGridValue(\.column),
            in: 0...max(0, grid.columns - 1)
          )
          Stepper(
            OJDLocalized.formatted("ui.capture.touchRow", grid.row + 1),
            value: touchGridValue(\.row),
            in: 0...max(0, grid.rows - 1)
          )
        }.padding(.leading, 8)
      case .touchSwipe(let swipe):
        VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
          Text(
            OJDLocalized.formatted(
              "ui.capture.touchSwipeDistance",
              swipe.minimumDistance * 100
            )
          )
          Slider(
            value: Binding(
              get: { swipe.minimumDistance },
              set: { distance in
                source = .touchSwipe(
                  RemappingTouchSwipeSource(
                    surface: swipe.surface,
                    direction: swipe.direction,
                    minimumDistance: distance
                  )
                )
              }
            ),
            in: RemappingTouchSwipeSource.minimumDistanceRange
          ).ojdAccessibilityLabel(OJDLocalized.string("a11y.capture.touchSwipeDistance"))
            .ojdAccessibilityValue(
              swipe.minimumDistance.formatted(.percent.precision(.fractionLength(0)))
            )
        }.padding(.leading, 8)
      case .button, .dpad, .axis, .axisDirection, .triggerStage, .motionLean, .touchContact,
        .stickRegion, .triggerBand, .touchArea:
        EmptyView()
      }
    }

    /// Returns a binding to one number of the touch grid source: its columns, rows, column or row.
    ///
    /// Setting a number keeps the chosen cell inside the grid.
    private func touchGridValue(_ keyPath: KeyPath<RemappingTouchGridSource, Int>) -> Binding<Int> {
      Binding(
        get: {
          guard case .touchGrid(let grid) = source else { return 0 }
          return grid[keyPath: keyPath]
        },
        set: { value in
          guard case .touchGrid(let grid) = source else { return }
          var columns = grid.columns
          var rows = grid.rows
          var column = grid.column
          var row = grid.row
          switch keyPath {
          case \.columns: columns = value
          case \.rows: rows = value
          case \.column: column = value
          case \.row: row = value
          default: return
          }
          column = min(column, columns - 1)
          row = min(row, rows - 1)
          source = .touchGrid(
            RemappingTouchGridSource(
              surface: grid.surface,
              columns: columns,
              rows: rows,
              column: column,
              row: row
            )
          )
        }
      )
    }

    /// Whether the Add Assignment button is enabled: the controller supports the source and the
    /// destination, and a keyboard destination holds a key.
    private var canAddAssignment: Bool {
      guard ProfileCapabilityPolicy.supports(source, capabilities: capabilities),
        ProfileCapabilityPolicy.supports(destination, capabilities: capabilities)
      else { return false }
      if case .keyboard = destination { return !keyboardDestinationCleared }
      return true
    }

    /// Whether the capture listens to the selected controller.
    private var isListening: Bool {
      guard let selectedDeviceSelector else { return false }
      if case .listening(let selector) = viewModel.inputCaptureState {
        return selector == selectedDeviceSelector
      }
      return false
    }

    /// The destination picker's binding; choosing a destination marks the keyboard key as not
    /// cleared.
    private var destinationBinding: Binding<RemappingDestination> {
      Binding(
        get: { destination },
        set: {
          destination = $0
          keyboardDestinationCleared = false
        }
      )
    }

    /// The source picker's binding; choosing a source keeps the destination when it still fits the
    /// source, and else takes the first destination that does.
    private var sourceBinding: Binding<RemappingSource> {
      Binding(
        get: { source },
        set: { newSource in
          source = newSource
          let options = DestinationOption.options(
            for: newSource,
            including: destination,
            capabilities: capabilities,
            macros: macros
          )
          if !options.contains(where: { $0.destination == destination }),
            let replacement = options.first

          {
            destination = replacement.destination
          }
          keyboardDestinationCleared = false
        }
      )
    }

    /// The connected controllers, or none while the status is not loaded.
    private var connectedDevices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = viewModel.statusState else { return [] }
      return status.devices
    }

    /// The picker's binding to the session token of the controller to listen to; the first
    /// connected controller until one is chosen.
    ///
    /// Choosing another controller stops listening.
    private var selectedDeviceBinding: Binding<String> {
      Binding(
        get: { selectedSessionToken ?? connectedDevices.first?.sessionToken.rawValue ?? "" },
        set: {
          if selectedSessionToken != $0 { stopListening() }
          selectedSessionToken = $0
        }
      )
    }

    /// The reference to the controller to listen to, or nil when no controller is connected.
    var selectedDeviceSelector: ControllerReference? {
      guard
        let device = connectedDevices.first(where: {
          $0.sessionToken.rawValue
            == (selectedSessionToken ?? connectedDevices.first?.sessionToken.rawValue)
        })
      else { return nil }
      return ControllerReference.session(device.sessionToken)
    }

    /// Selects the first connected controller when none is selected.
    private func selectInitialDevice() {
      guard selectedSessionToken == nil else { return }
      selectedSessionToken = connectedDevices.first?.sessionToken.rawValue
    }

    /// Stops listening, announces the cancellation and dismisses the sheet.
    private func cancelCapture() {
      stopListening()
      announce(OJDLocalized.string("ui.capture.canceled"))
      presentationMode.wrappedValue.dismiss()
    }

    /// Starts the input capture on the controller `selector`.
    private func beginListening(for selector: ControllerReference) {
      viewModel.cancelInputCapture()
      Task { @MainActor in await viewModel.listenForInput(for: selector) }
    }

    /// Stops the input capture.
    private func stopListening() { viewModel.cancelInputCapture() }

    /// Announces `message` to VoiceOver.
    private func announce(_ message: String) {
      unsafe NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
      )
    }

    /// Takes the source that the capture detected on the selected controller; other states change
    /// nothing.
    private func handleCaptureState(_ captureState: RuntimeInputCaptureState) {
      switch captureState {
      case .detected(let selector, _, let detected):
        guard let selectedDeviceSelector, selector == selectedDeviceSelector else { return }
        applyDetectedSource(detected)
      case .received, .unavailable, .error, .idle, .listening: break
      }
    }

    /// Sets the source to `detected` when the controller supports it, and keeps the destination
    /// when it still fits the source, else takes the first destination that does.
    private func applyDetectedSource(_ detected: RemappingSource) {
      guard ProfileCapabilityPolicy.supports(detected, capabilities: capabilities) else { return }
      source = detected
      let options = DestinationOption.options(
        for: detected,
        including: destination,
        capabilities: capabilities,
        macros: macros
      )
      if !options.contains(where: { $0.destination == destination }),
        let replacement = options.first
      {
        destination = replacement.destination
      }
      keyboardDestinationCleared = false
    }

    /// The destination as VoiceOver reads it; a keyboard destination without a key reads as no
    /// key.
    private var destinationAccessibilityValue: String {
      if case .keyboard = destination, keyboardDestinationCleared {
        return OJDLocalized.string("ui.keyboard.noKey")
      }
      return RuntimePresentation.destinationLabel(destination)
    }
  }

#endif
