#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  extension InputTestViewModel {
    enum SessionState: Equatable {
      case idle
      case starting
      case live
      case stale
      case disconnected
      case permissionRequired
      case unavailable
      case error
    }

    enum OutputOperation: Equatable {
      case rumble
      case playerIndicator
      case color
      case brightness
    }

    enum OutputState: Equatable {
      case idle
      case running(OutputOperation)
      case succeeded(OutputOperation)
      case failed(OutputOperation)
    }

    typealias Sleep = @Sendable (UInt64) async throws -> Void

    var rumbleIntensities: [PhysicalRumbleMotor: Double] {
      get { outputSettings.rumbleIntensities }
      set { outputSettings.rumbleIntensities = newValue }
    }

    var rumbleDurationMilliseconds: Double {
      get { outputSettings.rumbleDurationMilliseconds }
      set { outputSettings.rumbleDurationMilliseconds = newValue }
    }

    var playerIndicator: PhysicalPlayerIndicator {
      get { outputSettings.playerIndicator }
      set { outputSettings.playerIndicator = newValue }
    }

    var red: Double {
      get { outputSettings.red }
      set { outputSettings.red = newValue }
    }

    var green: Double {
      get { outputSettings.green }
      set { outputSettings.green = newValue }
    }

    var blue: Double {
      get { outputSettings.blue }
      set { outputSettings.blue = newValue }
    }

    var brightness: Double {
      get { outputSettings.brightness }
      set { outputSettings.brightness = newValue }
    }

    var capabilities: PhysicalControllerOutputCapabilities {
      device?.physicalOutputCapabilities ?? .none
    }

    var latestInput: ControllerState { liveState.snapshot }

    var isSampling: Bool { samplingTask != nil }

    var isOutputBusy: Bool {
      if case .running = outputState { return true }
      return false
    }

    var canSendOutput: Bool { isDeviceConnected && device != nil }
    var canStopRumble: Bool { outputMayRequireRumbleStop }

    func selectDevice(_ selectedDevice: ApplicationServiceDeviceDescription) {
      motionCalibration.select(RuntimeDeviceSelector(device: selectedDevice))
      guard device?.runtimeIdentifier != selectedDevice.runtimeIdentifier else {
        device = selectedDevice
        startSamplingIfNeeded()
        return
      }
      let oldSelector = device.map(RuntimeDeviceSelector.init(device:))
      cancelSampling(nextState: .idle)
      cancelOutput(stopSelector: oldSelector)
      device = selectedDevice
      isDeviceConnected = true
      liveState.reset(
        labels: ControllerButtonLabels(protocolID: selectedDevice.protocolBinding.protocolID)
      )
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

    func reconcileConnectedDevices(_ devices: [ApplicationServiceDeviceDescription]) {
      guard let current = device else { return }
      guard
        let refreshed = devices.first(where: { $0.runtimeIdentifier == current.runtimeIdentifier })
      else {
        isDeviceConnected = false
        motionCalibration.select(nil)
        cancelSampling(nextState: .disconnected)
        cancelOutput(stopSelector: RuntimeDeviceSelector(device: current))
        return
      }
      device = refreshed
      isDeviceConnected = true
      motionCalibration.select(RuntimeDeviceSelector(device: refreshed))
      if sessionState == .disconnected || sessionState == .permissionRequired {
        sessionState = .idle
      }
      startSamplingIfNeeded()
    }

    func reconcileStatus(_ status: RuntimeStatusPresentation) {
      reconcileConnectedDevices(status.devices)
      guard !isDeviceConnected, status.permissions.inputMonitoring != .granted,
        device?.discoverySource == .hid
      else { return }
      sessionState = .permissionRequired
    }

    func open() {
      isWindowActive = true
      startSamplingIfNeeded()
    }

    private func startSamplingIfNeeded() {
      guard isWindowActive, samplingTask == nil, isDeviceConnected else { return }
      guard let device else {
        sessionState = .disconnected
        return
      }
      samplingGeneration &+= 1
      let generation = samplingGeneration
      let selector = RuntimeDeviceSelector(device: device)
      sessionState = .starting
      samplingTask = Task { [weak self] in
        await self?.sampleLoop(selector: selector, generation: generation)
      }
    }

    func close() {
      isWindowActive = false
      cancelSampling(nextState: device == nil ? .disconnected : .idle)
      cancelOutput(stopSelector: device.map(RuntimeDeviceSelector.init(device:)))
      motionCalibration.select(nil)
    }

    func testRumble() {
      guard let device, canSendOutput, capabilities.supportsRumble else { return }
      let command = rumbleCommand()
      let selector = RuntimeDeviceSelector(device: device)
      let duration = max(100, min(2_000, Int(rumbleDurationMilliseconds.rounded())))
      beginOutputOperation(.rumble, selector: selector) { [gateway, rumbleSleep] in
        let intensities = RumbleIntensities(
          leftMain: UnipolarValue(byte: command.left),
          rightMain: UnipolarValue(byte: command.right),
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

    func stopRumble() {
      guard outputMayRequireRumbleStop, let device else { return }
      cancelOutput(stopSelector: RuntimeDeviceSelector(device: device))
    }

    func applyPlayerIndicator() {
      guard let device, canSendOutput, capabilities.supportsPlayerIndicator else { return }
      let selector = RuntimeDeviceSelector(device: device)
      let indicator = playerIndicator
      beginOutputOperation(.playerIndicator, selector: selector) { [gateway] in
        try await gateway.sendControllerOutput(.setPlayerIndicator(indicator), for: selector)
          .isDelivered
      }
    }

    func applyColor() {
      guard let device, canSendOutput, capabilities.lightingFeatures.contains(.programmableColor)
      else { return }
      let selector = RuntimeDeviceSelector(device: device)
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

    func applyBrightness() {
      guard let device, canSendOutput, capabilities.supportsProgrammableBrightness else { return }
      let selector = RuntimeDeviceSelector(device: device)
      let value = Self.byte(brightness)
      beginOutputOperation(.brightness, selector: selector) { [gateway] in
        try await gateway.sendControllerOutput(
          .setLightBrightness(UnipolarValue(byte: value)),
          for: selector
        ).isDelivered
      }
    }

    private func sampleLoop(selector: RuntimeDeviceSelector, generation: UInt64) async {
      var receivedSnapshot = false
      var consecutiveFailures = 0
      while !Task.isCancelled, generation == samplingGeneration {
        do {
          let snapshot = try await gateway.controllerState(for: selector)
          try Task.checkCancellation()
          guard generation == samplingGeneration else { return }
          if let snapshot {
            liveState.update(snapshot)
            if sessionState != .live { sessionState = .live }
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

    private func cancelSampling(nextState: SessionState) {
      samplingGeneration &+= 1
      samplingTask?.cancel()
      samplingTask = nil
      sessionState = nextState
    }

    private func beginOutputOperation(
      _ operation: OutputOperation,
      selector: RuntimeDeviceSelector,
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
              "inputTest.outputRejected"
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

    private func clearOutputOperation() {
      outputTask = nil
      outputSelector = nil
      outputMayRequireRumbleStop = false
    }

    private func cancelOutput(stopSelector selector: RuntimeDeviceSelector?) {
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
