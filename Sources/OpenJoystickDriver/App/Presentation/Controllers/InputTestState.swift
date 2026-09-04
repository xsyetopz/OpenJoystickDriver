#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  protocol InputTestDeviceGateway: Sendable {
    func inputState(for selector: RuntimeDeviceSelector) async throws -> DeviceInputState?
    func sendRumble(
      for selector: RuntimeDeviceSelector,
      left: UInt8,
      right: UInt8,
      leftTrigger: UInt8,
      rightTrigger: UInt8,
      durationMilliseconds: Int
    ) async throws -> Bool
    func setPlayerIndicator(for selector: RuntimeDeviceSelector, indicator: PhysicalPlayerIndicator)
      async throws -> Bool
    func setColor(for selector: RuntimeDeviceSelector, red: UInt8, green: UInt8, blue: UInt8)
      async throws -> Bool
    func setBrightness(for selector: RuntimeDeviceSelector, brightness: UInt8) async throws -> Bool
  }

  enum InputTestButtonPresentation {
    static let standardButtons: Set<Button> = [
      .a, .b, .x, .y, .cross, .circle, .square, .triangle, .leftBumper, .rightBumper, .l1, .r1,
      .l2Digital, .r2Digital, .back, .share, .guide, .ps, .start, .options, .leftStick, .rightStick,
      .dpadUp, .dpadDown, .dpadLeft, .dpadRight
    ]

    /// Classic face/shoulder/stick/dpad controls. Share/Mute/touchpad stay outside this set so
    /// Developer Tools Extra Buttons can confirm packet-mapped non-core controls.
    static let coreDiagnosticButtons: Set<Button> = [
      .a, .b, .x, .y, .cross, .circle, .square, .triangle, .leftBumper, .rightBumper, .l1, .r1,
      .l2Digital, .r2Digital, .back, .guide, .ps, .start, .leftStick, .rightStick, .dpadUp,
      .dpadDown, .dpadLeft, .dpadRight
    ]

    static func isPressed(_ buttons: [Button], in state: DeviceInputState) -> Bool {
      isPressed(buttons, in: Set(state.pressedButtons))
    }

    static func isPressed(_ buttons: [Button], in pressedButtons: Set<String>) -> Bool {
      buttons.contains { pressedButtons.contains($0.rawValue) }
    }

    static func additionalButtons(in state: DeviceInputState) -> [String] {
      let known = Set(standardButtons.map(\.rawValue))
      return state.pressedButtons.filter { !known.contains($0) }.sorted()
    }

    static func localizedTitle(for rawName: String) -> String {
      guard let button = Button(rawValue: rawName) else { return rawName }
      switch button {
      case .mute: return OJDLocalized.string("mapping.mute", fallback: "Mute")
      case .touchpad:
        return OJDLocalized.string("mapping.touchpadClick", fallback: "Touchpad click")
      default: return button.displayName
      }
    }
  }

  /// View-owned physical-output values are isolated from session state so continuous controls do
  /// not invalidate the live input hierarchy or window chrome while they are being dragged.
  @MainActor final class InputTestOutputSettings: ObservableObject {
    @Published var rumbleIntensities: [PhysicalRumbleMotor: Double] = [:]
    @Published var rumbleDurationMilliseconds = 300.0
    @Published var playerIndicator: PhysicalPlayerIndicator = .off
    @Published var red = 0.0
    @Published var green = 122.0
    @Published var blue = 255.0
    @Published var brightness = 255.0
  }

  @MainActor final class InputTestViewModel: ObservableObject {
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

    @Published private(set) var device: ApplicationServiceDeviceDescription?
    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var outputState: OutputState = .idle
    @Published private(set) var outputError: String?
    @Published private(set) var isDeviceConnected = false
    let liveState = InputTestLiveState()
    let outputSettings = InputTestOutputSettings()

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

    private let gateway: any InputTestDeviceGateway
    private let sampleIntervalNanoseconds: UInt64
    private let sleep: Sleep
    private var samplingTask: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?
    private var samplingGeneration: UInt64 = 0
    private var outputGeneration: UInt64 = 0
    private var outputSelector: RuntimeDeviceSelector?
    private var outputMayRequireRumbleStop = false

    init(
      gateway: any InputTestDeviceGateway,
      sampleIntervalNanoseconds: UInt64 = 33_333_333,
      sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
      self.gateway = gateway
      self.sampleIntervalNanoseconds = sampleIntervalNanoseconds
      self.sleep = sleep
    }

    var capabilities: PhysicalControllerOutputCapabilities {
      device?.physicalOutputCapabilities ?? .none
    }

    var latestInput: DeviceInputState { liveState.snapshot }

    var isSampling: Bool {
      switch sessionState {
      case .starting, .live, .stale: return true
      case .idle, .disconnected, .permissionRequired, .unavailable, .error: return false
      }
    }

    var isOutputBusy: Bool {
      if case .running = outputState { return true }
      return false
    }

    var canSendOutput: Bool { isDeviceConnected && device != nil }
    var canStopRumble: Bool { outputMayRequireRumbleStop }

    func selectDevice(_ selectedDevice: ApplicationServiceDeviceDescription) {
      guard device?.runtimeIdentifier != selectedDevice.runtimeIdentifier else {
        device = selectedDevice
        return
      }
      let oldSelector = device.map(RuntimeDeviceSelector.init(device:))
      cancelSampling(nextState: .idle)
      cancelOutput(stopSelector: oldSelector)
      device = selectedDevice
      isDeviceConnected = true
      liveState.reset(vendorID: selectedDevice.vendorID, productID: selectedDevice.productID)
      rumbleIntensities = Dictionary(
        uniqueKeysWithValues: selectedDevice.physicalOutputCapabilities.rumbleMotors.map {
          ($0, 0.0)
        }
      )
      sessionState = .idle
      outputState = .idle
      outputError = nil
    }

    func reconcileConnectedDevices(_ devices: [ApplicationServiceDeviceDescription]) {
      guard let current = device else { return }
      guard
        let refreshed = devices.first(where: { $0.runtimeIdentifier == current.runtimeIdentifier })
      else {
        isDeviceConnected = false
        cancelSampling(nextState: .disconnected)
        cancelOutput(stopSelector: RuntimeDeviceSelector(device: current))
        return
      }
      device = refreshed
      isDeviceConnected = true
      if sessionState == .disconnected { sessionState = .idle }
    }

    func reconcileStatus(_ status: RuntimeStatusPresentation) {
      reconcileConnectedDevices(status.devices)
      guard !isDeviceConnected, status.permissions.inputMonitoring != .granted,
        device?.discoverySource == .hid
      else { return }
      sessionState = .permissionRequired
    }

    func start() {
      guard let device else {
        sessionState = .disconnected
        return
      }
      cancelSampling(nextState: .starting)
      samplingGeneration &+= 1
      let generation = samplingGeneration
      let selector = RuntimeDeviceSelector(device: device)
      sessionState = .starting
      samplingTask = Task { [weak self] in
        await self?.sampleLoop(selector: selector, generation: generation)
      }
    }

    func stop() {
      cancelSampling(nextState: device == nil ? .disconnected : .idle)
      cancelOutput(stopSelector: device.map(RuntimeDeviceSelector.init(device:)))
    }

    func close() { stop() }

    func testRumble() {
      guard let device, canSendOutput, capabilities.supportsRumble else { return }
      let command = rumbleCommand()
      let selector = RuntimeDeviceSelector(device: device)
      let duration = max(100, min(2_000, Int(rumbleDurationMilliseconds.rounded())))
      beginOutputOperation(.rumble, selector: selector) { [gateway] in
        let sent = try await gateway.sendRumble(
          for: selector,
          left: command.left,
          right: command.right,
          leftTrigger: command.leftTrigger,
          rightTrigger: command.rightTrigger,
          durationMilliseconds: duration
        )
        guard sent else { return false }
        do { try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000) } catch {
          _ = try? await gateway.sendRumble(
            for: selector,
            left: 0,
            right: 0,
            leftTrigger: 0,
            rightTrigger: 0,
            durationMilliseconds: 0
          )
          throw error
        }
        return try await gateway.sendRumble(
          for: selector,
          left: 0,
          right: 0,
          leftTrigger: 0,
          rightTrigger: 0,
          durationMilliseconds: 0
        )
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
        try await gateway.setPlayerIndicator(for: selector, indicator: indicator)
      }
    }

    func applyColor() {
      guard let device, canSendOutput, capabilities.lightingFeatures.contains(.programmableColor)
      else { return }
      let selector = RuntimeDeviceSelector(device: device)
      let components = (Self.byte(red), Self.byte(green), Self.byte(blue))
      beginOutputOperation(.color, selector: selector) { [gateway] in
        try await gateway.setColor(
          for: selector,
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
        try await gateway.setBrightness(for: selector, brightness: value)
      }
    }

    private func sampleLoop(selector: RuntimeDeviceSelector, generation: UInt64) async {
      var receivedSnapshot = false
      var consecutiveFailures = 0
      while !Task.isCancelled, generation == samplingGeneration {
        do {
          let snapshot = try await gateway.inputState(for: selector)
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
            _ = try? await gateway.sendRumble(
              for: previousSelector,
              left: 0,
              right: 0,
              leftTrigger: 0,
              rightTrigger: 0,
              durationMilliseconds: 0
            )
          }
          try Task.checkCancellation()
          let succeeded = try await body()
          try Task.checkCancellation()
          guard let self, generation == self.outputGeneration else { return }
          self.outputMayRequireRumbleStop = false
          self.outputState = succeeded ? .succeeded(operation) : .failed(operation)
          if !succeeded {
            self.outputError = OJDLocalized.string(
              "inputTest.outputRejected",
              fallback: "The controller rejected this output test."
            )
          }
        } catch is CancellationError { return } catch {
          guard let self, generation == self.outputGeneration else { return }
          self.outputState = .failed(operation)
          self.outputError = RuntimePresentation.userFacingError(error)
        }
      }
    }

    private func cancelOutput(stopSelector selector: RuntimeDeviceSelector?) {
      outputGeneration &+= 1
      let previousTask = outputTask
      let activeSelector = outputSelector ?? selector
      let shouldStopRumble = outputMayRequireRumbleStop
      previousTask?.cancel()
      outputSelector = nil
      outputMayRequireRumbleStop = false
      outputState = .idle
      outputError = nil
      outputTask = Task { [gateway] in
        await previousTask?.value
        guard shouldStopRumble, let activeSelector else { return }
        _ = try? await gateway.sendRumble(
          for: activeSelector,
          left: 0,
          right: 0,
          leftTrigger: 0,
          rightTrigger: 0,
          durationMilliseconds: 0
        )
      }
    }

    private func rumbleCommand() -> (
      left: UInt8, right: UInt8, leftTrigger: UInt8, rightTrigger: UInt8
    ) {
      var left: UInt8 = 0
      var right: UInt8 = 0
      var leftTrigger: UInt8 = 0
      var rightTrigger: UInt8 = 0
      let binary = Set(capabilities.binaryRumbleMotors)
      for motor in capabilities.rumbleMotors {
        let raw = rumbleIntensities[motor] ?? 0
        let value: UInt8 = binary.contains(motor) ? (raw > 0 ? 255 : 0) : Self.byte(raw)
        switch motor {
        case .leftMain, .leftHaptic: left = max(left, value)
        case .rightMain, .rightHaptic: right = max(right, value)
        case .leftTrigger: leftTrigger = value
        case .rightTrigger: rightTrigger = value
        }
      }
      return (left, right, leftTrigger, rightTrigger)
    }

    private static func byte(_ value: Double) -> UInt8 {
      UInt8(clamping: Int(max(0, min(255, value)).rounded()))
    }
  }

#endif
