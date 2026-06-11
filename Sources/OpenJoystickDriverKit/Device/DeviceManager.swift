import Foundation

private let devicePermissionWatchNanoseconds: UInt64 = 1_000_000_000

/// Manages SDL3-backed physical gamepad detection and lifecycle.
///
/// SDL3 owns real-controller access. OJD keeps the daemon lifecycle,
/// canonical state boundary, foreground output gate, and virtual output routing.
public actor DeviceManager {
  private let dispatcher: any OutputDispatcher
  private let permissionManager: PermissionManager
  private let sdlSource: SDL3GamepadSource
  private var detectionTask: Task<Void, Never>?
  private var permissionWatchTask: Task<Void, Never>?
  private var externalOutputAllowed = true
  private var outputStates: [DeviceIdentifier: DeviceInputState] = [:]
  private var waitingForExternalNeutral: Set<DeviceIdentifier> = []

  public init(dispatcher: any OutputDispatcher, virtualProfile _: VirtualDeviceProfile = .default) {
    self.dispatcher = dispatcher
    self.permissionManager = PermissionManager()
    self.sdlSource = SDL3GamepadSource()
  }

  public func start() async {
    let state = await permissionManager.checkAccess()
    switch state {
    case .unknown, .denied:
      print("[DeviceManager] Input Monitoring not granted; SDL3 may see fewer controllers")
    case .granted:
      print("[DeviceManager] Input Monitoring granted")
    }

    guard sdlSource.start() else {
      print("[DeviceManager] SDL3 input startup failed")
      return
    }

    detectionTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        await self.pollSDL3InputOnce()
        try? await Task.sleep(nanoseconds: SDL3GamepadSource.pollIntervalNanoseconds)
      }
    }

    permissionWatchTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        _ = await self.permissionManager.checkAccess()
        try? await Task.sleep(nanoseconds: devicePermissionWatchNanoseconds)
      }
    }

    print("[DeviceManager] Started - SDL3 physical input active")
  }

  public func inputState(for identifier: DeviceIdentifier) -> DeviceInputState? {
    sdlSource.inputState(for: identifier)
  }

  public func packetLog(for _: DeviceIdentifier) -> [PacketLogEntry] { [] }

  public func sendRumble(
    for identifier: DeviceIdentifier,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) -> Bool {
    sdlSource.sendRumble(
      for: identifier,
      left: left,
      right: right,
      lt: lt,
      rt: rt,
      durationMs: durationMs
    )
  }

  public func connectedDeviceDescriptions() -> [XPCDeviceDescription] {
    sdlSource.connectedGamepads().map { gamepad in
      XPCDeviceDescription(
        name: gamepad.identity.name,
        vendorID: gamepad.identifier.vendorID,
        productID: gamepad.identifier.productID,
        parser: "SDL3",
        connection: "SDL3",
        serialNumber: gamepad.identifier.serialNumber,
        protocolVariant: "sdl3Gamepad",
        mappingFlags: [],
        inputEndpoint: 0,
        outputEndpoint: 0,
        needsSetConfiguration: false,
        postHandshakeSettleMs: 0,
        preferredBackends: [],
        supportsPhysicalRumble: gamepad.supportsRumble
      )
    }
  }

  public func connectedDeviceIdentifiers() -> [DeviceIdentifier] {
    sdlSource.connectedGamepads().map(\.identifier)
  }

  public func stop() async {
    detectionTask?.cancel()
    detectionTask = nil
    permissionWatchTask?.cancel()
    permissionWatchTask = nil

    for identifier in Array(outputStates.keys) {
      await neutralizeOutput(for: identifier)
      if let listener = dispatcher as? any ControllerLifecycleListener {
        listener.controllerDidStop(identifier)
      }
    }
    outputStates.removeAll()
    waitingForExternalNeutral.removeAll()
    sdlSource.close()
    await permissionManager.stopPolling()
    print("[DeviceManager] Stopped")
  }

  public func setExternalOutputAllowed(_ allowed: Bool) async {
    guard externalOutputAllowed != allowed else { return }
    externalOutputAllowed = allowed
    if !allowed {
      waitingForExternalNeutral.removeAll()
      for identifier in Array(outputStates.keys) { await neutralizeOutput(for: identifier) }
      print("[DeviceManager] Output gated by foreground consumer")
      return
    }

    for gamepad in sdlSource.connectedGamepads() where !gamepad.snapshot.isEffectivelyNeutral {
      waitingForExternalNeutral.insert(gamepad.identifier)
    }
    print("[DeviceManager] Output ungated by foreground consumer")
  }

  private func pollSDL3InputOnce() async {
    await sdlSource.pollOnce(
      onEvents: { [weak self] identifier, events in
        guard let self else { return }
        await self.handleSDLEvents(events, from: identifier)
      },
      onRemoved: { [weak self] identifier in
        guard let self else { return }
        await self.handleSDLRemoval(identifier)
      }
    )
  }

  private func handleSDLEvents(
    _ events: [ControllerEvent],
    from identifier: DeviceIdentifier
  ) async {
    if outputStates[identifier] == nil {
      outputStates[identifier] = DeviceInputState(
        vendorID: identifier.vendorID,
        productID: identifier.productID
      )
      await dispatcher.dispatch(events: [], from: identifier)
    }

    if var state = outputStates[identifier] {
      state.apply(events: events)
      outputStates[identifier] = state
    }

    guard externalOutputAllowed else { return }
    if waitingForExternalNeutral.contains(identifier) {
      guard outputStates[identifier]?.isEffectivelyNeutral == true else { return }
      waitingForExternalNeutral.remove(identifier)
    }
    await dispatcher.dispatch(events: events, from: identifier)
  }

  private func handleSDLRemoval(_ identifier: DeviceIdentifier) {
    outputStates.removeValue(forKey: identifier)
    waitingForExternalNeutral.remove(identifier)
    if let listener = dispatcher as? any ControllerLifecycleListener {
      listener.controllerDidStop(identifier)
    }
    print("[DeviceManager] SDL3 gamepad removed: \(identifier)")
  }

  private func neutralizeOutput(for identifier: DeviceIdentifier) async {
    guard let state = outputStates[identifier] else { return }
    let neutralizingEvents = state.neutralizingEvents()
    guard !neutralizingEvents.isEmpty else { return }
    await dispatcher.dispatch(events: neutralizingEvents, from: identifier)
    var neutral = state
    neutral.apply(events: neutralizingEvents)
    outputStates[identifier] = neutral
  }
}

extension SDL3GamepadSnapshot {
  var isEffectivelyNeutral: Bool {
    buttons.isEmpty && axes.values.allSatisfy { abs(Int($0)) < 1_000 }
  }
}
