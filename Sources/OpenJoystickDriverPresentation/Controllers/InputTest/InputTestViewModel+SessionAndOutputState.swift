#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  extension InputTestViewModel {
    /// Where the sampling of the controller's input is.
    enum SessionState: Equatable {
      /// No sampling runs.
      case idle
      /// The first sample is awaited.
      case starting
      /// Samples arrive and every control is at rest.
      case receiving
      /// Samples arrive and a control has left its rest value.
      case live
      /// Samples stopped arriving after some had come.
      case stale
      /// The controller is not connected.
      case disconnected
      /// Reading the input needs a permission that is not granted.
      case permissionRequired
      /// No sample ever arrived.
      case unavailable
      /// The session failed; the status reads Failed.
      case error
    }

    /// The output test.
    enum OutputOperation: Equatable {
      /// The rumble test.
      case rumble
      /// The player indicator.
      case playerIndicator
      /// The color.
      case color
      /// The brightness.
      case brightness
    }

    /// Where the latest output test is.
    enum OutputState: Equatable {
      /// No output test runs.
      case idle
      /// The output test runs.
      case running(OutputOperation)
      /// The controller received the output.
      case succeeded(OutputOperation)
      /// The output failed.
      case failed(OutputOperation)
    }

    /// Waits for a number of nanoseconds.
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    /// The rumble intensity of each motor, kept in the output settings.
    var rumbleIntensities: [PhysicalRumbleMotor: Double] {
      get { outputSettings.rumbleIntensities }
      set { outputSettings.rumbleIntensities = newValue }
    }

    /// The rumble test length in milliseconds, kept in the output settings.
    var rumbleDurationMilliseconds: Double {
      get { outputSettings.rumbleDurationMilliseconds }
      set { outputSettings.rumbleDurationMilliseconds = newValue }
    }

    /// The player indicator to apply, kept in the output settings.
    var playerIndicator: PhysicalPlayerIndicator {
      get { outputSettings.playerIndicator }
      set { outputSettings.playerIndicator = newValue }
    }

    /// The red component of the color to apply, kept in the output settings.
    var red: Double {
      get { outputSettings.red }
      set { outputSettings.red = newValue }
    }

    /// The green component of the color to apply, kept in the output settings.
    var green: Double {
      get { outputSettings.green }
      set { outputSettings.green = newValue }
    }

    /// The blue component of the color to apply, kept in the output settings.
    var blue: Double {
      get { outputSettings.blue }
      set { outputSettings.blue = newValue }
    }

    /// The brightness to apply, kept in the output settings.
    var brightness: Double {
      get { outputSettings.brightness }
      set { outputSettings.brightness = newValue }
    }

    /// What the selected controller can do as output; none without a controller.
    var capabilities: PhysicalControllerOutputCapabilities {
      device?.physicalOutputCapabilities ?? .none
    }

    /// The sections shown for the selected controller: Motion calibration needs a gyroscope and
    /// Lighting needs a lighting feature; Rumble states when the controller has no motor.
    var visibleSections: [InputTestSection] {
      InputTestSection.allCases.filter { section in
        switch section {
        case .liveInput, .rumble: true
        case .motion: device?.capabilities.motion == true
        case .lighting: !capabilities.lightingFeatures.isEmpty
        }
      }
    }

    /// The rumble test lengths in milliseconds, up to the longest the service accepts, which
    /// `ojd controller rumble --duration` also allows.
    static let rumbleDurationRange = 100...maxRumbleDurationMs

    /// Returns the length in milliseconds, rounded and clamped to ``rumbleDurationRange``.
    ///
    /// - Parameter milliseconds: The length the slider holds.
    /// - Returns: The length in milliseconds, rounded and clamped to ``rumbleDurationRange``.
    static func clampedRumbleDuration(_ milliseconds: Double) -> Int {
      max(
        rumbleDurationRange.lowerBound,
        min(rumbleDurationRange.upperBound, Int(milliseconds.rounded()))
      )
    }

    /// The latest input of the controller.
    var latestInput: ControllerState { liveState.snapshot }

    /// Whether the input is being sampled.
    var isSampling: Bool { samplingTask != nil }

    /// Whether an output test runs.
    var isOutputBusy: Bool {
      if case .running = outputState { return true }
      return false
    }

    /// Whether the controller is connected, so an output can be sent.
    var canSendOutput: Bool { isDeviceConnected && device != nil }
    /// Whether the running output test is a rumble that Stop can end.
    var canStopRumble: Bool { outputMayRequireRumbleStop }

    /// Selects the controller.
    ///
    /// A different controller resets the input, the rumble intensities and the output state, and
    /// stops the output of the previous one.
    ///
    /// - Parameter selectedDevice: The controller to test.
    func selectDevice(_ selectedDevice: ApplicationServiceDeviceDescription) {
      motionCalibration.select(ControllerReference.session(selectedDevice.sessionToken))
      guard device?.sessionToken.rawValue != selectedDevice.sessionToken.rawValue else {
        device = selectedDevice
        startSamplingIfNeeded()
        return
      }
      let oldSelector = device.map { ControllerReference.session($0.sessionToken) }
      cancelSampling(nextState: .idle)
      cancelOutput(stopSelector: oldSelector)
      device = selectedDevice
      isDeviceConnected = true
      liveState.reset()
      rumbleIntensities = Dictionary(
        uniqueKeysWithValues: selectedDevice.physicalOutputCapabilities.rumbleMotors.map {
          ($0, 0.0)
        }
      )
      sessionState = .idle
      outputState = .idle
      outputError = nil
      startSamplingIfNeeded()
    }

    /// Follows the connected controllers: the selected controller's entry is refreshed, or the
    /// controller counts as disconnected and its output stops.
    ///
    /// - Parameter devices: The connected controllers.
    func reconcileConnectedDevices(_ devices: [ApplicationServiceDeviceDescription]) {
      guard let current = device else { return }
      guard
        let refreshed = devices.first(where: {
          $0.sessionToken.rawValue == current.sessionToken.rawValue
        })
      else {
        isDeviceConnected = false
        motionCalibration.select(nil)
        cancelSampling(nextState: .disconnected)
        cancelOutput(stopSelector: ControllerReference.session(current.sessionToken))
        return
      }
      device = refreshed
      isDeviceConnected = true
      motionCalibration.select(ControllerReference.session(refreshed.sessionToken))
      if sessionState == .disconnected || sessionState == .permissionRequired {
        sessionState = .idle
      }
      startSamplingIfNeeded()
    }

    /// Follows the runtime status: the connected controllers, and a missing input permission for a
    /// controller found over HID that is not connected.
    ///
    /// - Parameter status: The status of the service.
    func reconcileStatus(_ status: RuntimeStatusPresentation) {
      reconcileConnectedDevices(status.devices)
      guard !isDeviceConnected, status.permissions.inputRead != .granted,
        device?.discoverySource == .hid
      else { return }
      sessionState = .permissionRequired
    }

    /// Marks the window as open and starts sampling.
    func open() {
      isWindowActive = true
      startSamplingIfNeeded()
    }

    /// Starts sampling the input of the selected controller when the window is open and none runs.
    private func startSamplingIfNeeded() {
      guard isWindowActive, samplingTask == nil, isDeviceConnected else { return }
      guard let device else {
        sessionState = .disconnected
        return
      }
      samplingGeneration &+= 1
      let generation = samplingGeneration
      let selector = ControllerReference.session(device.sessionToken)
      sessionState = .starting
      samplingTask = Task { [weak self] in
        await self?.sampleLoop(selector: selector, generation: generation)
      }
    }

    /// Marks the window as closed and ends sampling and output.
    func close() {
      isWindowActive = false
      cancelSampling(nextState: device == nil ? .disconnected : .idle)
      cancelOutput(stopSelector: device.map { ControllerReference.session($0.sessionToken) })
      motionCalibration.select(nil)
    }

    /// Rumbles the controller for the chosen length.
    ///
    /// The service stops the rumble when the length ends. Does nothing without a connected
    /// controller that has rumble.
    func testRumble() {
      guard let device, canSendOutput, capabilities.supportsRumble else { return }
      let command = rumbleCommand()
      let selector = ControllerReference.session(device.sessionToken)
      let duration = Self.clampedRumbleDuration(rumbleDurationMilliseconds)
      beginOutputOperation(.rumble, selector: selector) { [gateway, rumbleSleep] in
        let intensities = RumbleIntensities(
          lowFrequency: UnipolarValue(byte: command.left),
          highFrequency: UnipolarValue(byte: command.right),
          leftTrigger: UnipolarValue(byte: command.leftTrigger),
          rightTrigger: UnipolarValue(byte: command.rightTrigger)
        ).mirroringMainOntoHaptics()
        // The daemon stops the rumble when the duration ends; the wait keeps the test running.
        let result = try await gateway.sendControllerOutput(
          .setRumble(intensities, duration: .milliseconds(duration)),
          for: selector
        )
        guard result.isDelivered else { return false }
        try await rumbleSleep(UInt64(duration) * 1_000_000)
        return true
      }
    }

    /// Stops the running rumble.
    func stopRumble() {
      guard outputMayRequireRumbleStop, let device else { return }
      cancelOutput(stopSelector: ControllerReference.session(device.sessionToken))
    }

    /// Applies the player indicator.
    ///
    /// Does nothing without a controller that has one.
    func applyPlayerIndicator() {
      guard let device, canSendOutput, capabilities.supportsPlayerIndicator else { return }
      let selector = ControllerReference.session(device.sessionToken)
      let indicator = playerIndicator
      beginOutputOperation(.playerIndicator, selector: selector) { [gateway] in
        try await gateway.sendControllerOutput(.setPlayerIndicator(indicator), for: selector)
          .isDelivered
      }
    }

    /// Previews the color on the controller.
    ///
    /// Does nothing without a controller that has a programmable color.
    func applyColor() {
      guard let device, canSendOutput, capabilities.lightingFeatures.contains(.programmableColor)
      else { return }
      let selector = ControllerReference.session(device.sessionToken)
      let components = (Self.byte(red), Self.byte(green), Self.byte(blue))
      let token = colorPreviewToken
      colorPreviewSelector = selector
      beginOutputOperation(.color, selector: selector) { [gateway] in
        try await gateway.previewColor(
          for: selector,
          token: token,
          red: components.0,
          green: components.1,
          blue: components.2
        )
      }
    }

    /// Applies the brightness.
    ///
    /// Does nothing without a controller that has programmable brightness.
    func applyBrightness() {
      guard let device, canSendOutput, capabilities.supportsProgrammableBrightness else { return }
      let selector = ControllerReference.session(device.sessionToken)
      let value = Self.byte(brightness)
      beginOutputOperation(.brightness, selector: selector) { [gateway] in
        try await gateway.sendControllerOutput(
          .setLightBrightness(UnipolarValue(byte: value)),
          for: selector
        ).isDelivered
      }
    }

    /// Reads the controller's input every sample interval until sampling is canceled or replaced.
    ///
    /// A read without input counts as a failure, and three failures in a row end sampling. The state
    /// is `live` from the first sample in which a control is off its rest value, and stays `live`
    /// while samples arrive.
    ///
    /// - Parameters:
    ///   - selector: The controller.
    ///   - generation: The count that names this sampling.
    private func sampleLoop(selector: ControllerReference, generation: UInt64) async {
      var receivedSnapshot = false
      var consecutiveFailures = 0
      while !Task.isCancelled, generation == samplingGeneration {
        do {
          let snapshot = try await gateway.controllerState(for: selector)
          try Task.checkCancellation()
          guard generation == samplingGeneration else { return }
          if let snapshot {
            liveState.update(snapshot)
            let next: SessionState =
              sessionState == .live || snapshot.hasControlOffRest ? .live : .receiving
            if sessionState != next { sessionState = next }
            receivedSnapshot = true
            consecutiveFailures = 0
          } else {
            consecutiveFailures += 1
            sessionState = receivedSnapshot ? .stale : .starting
          }
        } catch is CancellationError { return } catch {
          guard generation == samplingGeneration else { return }
          consecutiveFailures += 1
          sessionState = receivedSnapshot ? .stale : .starting
        }

        if consecutiveFailures >= 3 {
          sessionState = receivedSnapshot ? .stale : .unavailable
          samplingTask = nil
          return
        }

        do { try await sleep(sampleIntervalNanoseconds) } catch { return }
      }
    }

    /// Cancels the sampling and sets the session state.
    ///
    /// - Parameter nextState: The state after cancellation.
    private func cancelSampling(nextState: SessionState) {
      samplingGeneration &+= 1
      samplingTask?.cancel()
      samplingTask = nil
      sessionState = nextState
    }

    /// Runs an output test, after canceling the previous one and stopping its rumble.
    ///
    /// - Parameters:
    ///   - operation: The output test.
    ///   - selector: The controller.
    ///   - body: Sends the output and returns whether the controller received it.
    private func beginOutputOperation(
      _ operation: OutputOperation,
      selector: ControllerReference,
      body: @escaping @Sendable () async throws -> Bool
    ) {
      outputGeneration &+= 1
      let previousTask = outputTask
      let previousSelector = outputSelector
      let shouldStopPreviousRumble = outputMayRequireRumbleStop
      previousTask?.cancel()
      let generation = outputGeneration
      let gateway = self.gateway
      outputSelector = selector
      outputMayRequireRumbleStop = operation == .rumble
      outputState = .running(operation)
      outputError = nil
      outputTask = Task { [weak self] in
        do {
          await previousTask?.value
          if shouldStopPreviousRumble, let previousSelector {
            _ = try? await gateway.sendControllerOutput(.stopRumble, for: previousSelector)
          }
          try Task.checkCancellation()
          let succeeded = try await body()
          try Task.checkCancellation()
          guard let self, generation == self.outputGeneration else { return }
          self.clearOutputOperation()
          self.outputState = succeeded ? .succeeded(operation) : .failed(operation)
          if !succeeded {
            self.outputError = OJDLocalized.string(
              "ui.inputTest.outputRejected"
            )
          }
        } catch is CancellationError {
          guard let self, generation == self.outputGeneration else { return }
          self.clearOutputOperation()
          self.outputState = .idle
          self.outputError = nil
        } catch {
          guard let self, generation == self.outputGeneration else { return }
          self.clearOutputOperation()
          self.outputState = .failed(operation)
          self.outputError = RuntimePresentation.userFacingError(error)
        }
      }
    }

    /// Forgets the finished output test.
    private func clearOutputOperation() {
      outputTask = nil
      outputSelector = nil
      outputMayRequireRumbleStop = false
    }

    /// Cancels the output test and releases the color preview, and stops a rumble on the
    /// controller.
    ///
    /// - Parameter selector: The controller to stop when no output test names one.
    private func cancelOutput(stopSelector selector: ControllerReference?) {
      outputGeneration &+= 1
      let previousTask = outputTask
      let activeSelector = outputSelector ?? selector
      let shouldStopRumble = outputMayRequireRumbleStop
      let previewSelector = colorPreviewSelector
      colorPreviewSelector = nil
      let colorPreviewToken = colorPreviewToken
      previousTask?.cancel()
      outputSelector = nil
      outputMayRequireRumbleStop = false
      outputState = .idle
      outputError = nil
      outputTask = Task { [gateway] in
        await previousTask?.value
        if shouldStopRumble, let activeSelector {
          _ = try? await gateway.sendControllerOutput(.stopRumble, for: activeSelector)
        }
        if let previewSelector {
          _ = try? await gateway.releaseColorPreview(for: previewSelector, token: colorPreviewToken)
        }
      }
    }
  }

#endif
