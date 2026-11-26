#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  extension InputTestViewModel {
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
      guidedCheck.cancel()
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
        guidedCheck.cancel()
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
      guidedCheck.cancel()
      cancelSampling(nextState: device == nil ? .disconnected : .idle)
      cancelOutput(stopSelector: device.map { ControllerReference.session($0.sessionToken) })
      motionCalibration.select(nil)
    }

    /// Whether the Guided Check can start: the controller is connected, sampled, declares a control
    /// to ask for and no check runs.
    var canStartGuidedCheck: Bool {
      guard let device, isSampling, guidedCheck.run == nil else { return false }
      return isDeviceConnected && !ControllerCheckControl.steps(for: device.capabilities).isEmpty
    }

    /// Starts the Guided Check of the selected controller.
    func startGuidedCheck() {
      guard let device else { return }
      guidedCheck.start(device)
    }

    /// Rumbles the controller for the chosen length.
    ///
    /// The service stops the rumble when the length ends. Without a connected controller that has
    /// rumble, nothing is sent and ``outputError`` says why.
    func testRumble() {
      guard let device, canSendOutput else {
        refuseOutput(.rumble, .notConnected)
        return
      }
      guard capabilities.supportsRumble else {
        refuseOutput(.rumble, .unsupported)
        return
      }
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
    ///
    /// The Stop button is disabled unless a rumble runs (``canStopRumble``), so the guard only
    /// covers a call that comes after the rumble ended.
    func stopRumble() {
      guard outputMayRequireRumbleStop, let device else { return }
      cancelOutput(stopSelector: ControllerReference.session(device.sessionToken))
    }

    /// Chooses the player indicator and applies it at once; the picker has no Apply button.
    ///
    /// - Parameter indicator: The indicator the user chose.
    func choosePlayerIndicator(_ indicator: PhysicalPlayerIndicator) {
      playerIndicator = indicator
      applyPlayerIndicator()
    }

    /// Applies the player indicator.
    ///
    /// Without a connected controller that has one, nothing is sent and ``outputError`` says why.
    func applyPlayerIndicator() {
      guard let device, canSendOutput else {
        refuseOutput(.playerIndicator, .notConnected)
        return
      }
      guard capabilities.supportsPlayerIndicator else {
        refuseOutput(.playerIndicator, .unsupported)
        return
      }
      let selector = ControllerReference.session(device.sessionToken)
      let indicator = playerIndicator
      beginOutputOperation(.playerIndicator, selector: selector) { [gateway] in
        try await gateway.sendControllerOutput(.setPlayerIndicator(indicator), for: selector)
          .isDelivered
      }
    }

    /// Previews the color on the controller.
    ///
    /// Without a connected controller that has a programmable color, nothing is sent and
    /// ``outputError`` says why.
    func applyColor() {
      guard let device, canSendOutput else {
        refuseOutput(.color, .notConnected)
        return
      }
      guard capabilities.lightingFeatures.contains(.programmableColor) else {
        refuseOutput(.color, .unsupported)
        return
      }
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
    /// Without a connected controller that has programmable brightness, nothing is sent and
    /// ``outputError`` says why.
    func applyBrightness() {
      guard let device, canSendOutput else {
        refuseOutput(.brightness, .notConnected)
        return
      }
      guard capabilities.supportsProgrammableBrightness else {
        refuseOutput(.brightness, .unsupported)
        return
      }
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
    /// A read without input counts as a failure, and three failures in a row end sampling. The
    /// state is `live` from the first sample in which a control is off its rest value, and stays
    /// `live` while samples arrive.
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
            applySample(snapshot)
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

    /// Shows `snapshot` and moves the session state to `live` once a control is off its rest value.
    private func applySample(_ snapshot: ControllerState) {
      liveState.update(snapshot)
      guidedCheck.observe(snapshot)
      let next: SessionState =
        sessionState == .live || snapshot.hasControlOffRest ? .live : .receiving
      if sessionState != next { sessionState = next }
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
            _ = try await gateway.sendControllerOutput(.stopRumble, for: previousSelector)
          }
          try Task.checkCancellation()
          let succeeded = try await body()
          try Task.checkCancellation()
          guard let self, generation == outputGeneration else { return }
          clearOutputOperation()
          outputState = succeeded ? .succeeded(operation) : .failed(operation)
          if !succeeded {
            outputError = OJDLocalized.string(
              "ui.inputTest.outputRejected"
            )
          }
        } catch is CancellationError {
          guard let self, generation == outputGeneration else { return }
          clearOutputOperation()
          outputState = .idle
          outputError = nil
        } catch {
          guard let self, generation == outputGeneration else { return }
          clearOutputOperation()
          outputState = .failed(operation)
          outputError = RuntimePresentation.userFacingError(error)
        }
      }
    }

    /// Shows that `operation` was not sent, with the reason, in the state of the latest output
    /// test.
    ///
    /// - Parameters:
    ///   - operation: The output test.
    ///   - refusal: Why it was not sent.
    private func refuseOutput(_ operation: OutputOperation, _ refusal: OutputRefusal) {
      outputState = .failed(operation)
      outputError = OJDLocalized.string(refusal.messageKey)
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
      let generation = outputGeneration
      outputTask = Task { [weak self, gateway] in
        await previousTask?.value
        var operation = OutputOperation.rumble
        do {
          if shouldStopRumble, let activeSelector {
            _ = try await gateway.sendControllerOutput(.stopRumble, for: activeSelector)
          }
          if let previewSelector {
            operation = .color
            _ = try await gateway.releaseColorPreview(
              for: previewSelector,
              token: colorPreviewToken
            )
          }
        } catch {
          guard let self, generation == outputGeneration else { return }
          outputState = .failed(operation)
          outputError = RuntimePresentation.userFacingError(error)
        }
      }
    }
  }

#endif
