import Foundation

struct RemappingEngineState {
  var devices: [DeviceIdentifier: RemappingDeviceState] = [:]
  var keyReferences: [RemappingKeyboardKey: Int] = [:]
  var modifierReferences: [RemappingKeyModifier: Int] = [:]
  var mouseButtonReferences: [RemappingMouseButton: Int] = [:]

  mutating func setProfile(
    _ profile: RemappingProfile?,
    for identifier: DeviceIdentifier
  ) -> [RemappingSystemInputAction] {
    guard devices[identifier]?.profile != profile else { return [] }
    let actions = releaseController(identifier)
    if let profile {
      devices[identifier] = RemappingDeviceState(profile: profile)
    }
    return actions
  }

  mutating func process(
    events: [ControllerEvent],
    from identifier: DeviceIdentifier,
    profile: RemappingProfile,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    var actions = setProfile(profile, for: identifier)
    for event in events {
      actions += process(
        event: event,
        from: identifier,
        at: uptimeNanoseconds
      )
    }
    return actions
  }

  private mutating func process(
    event: ControllerEvent,
    from identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    switch event {
    case .buttonPressed(let button):
      guard let source = Self.source(for: button) else { return [] }
      return setSource(
        source,
        isActive: true,
        for: identifier,
        at: uptimeNanoseconds
      )
    case .buttonReleased(let button):
      guard let source = Self.source(for: button) else { return [] }
      return setSource(
        source,
        isActive: false,
        for: identifier,
        at: uptimeNanoseconds
      )
    case .dpadChanged(let direction):
      return setDpad(direction, for: identifier, at: uptimeNanoseconds)
    case .leftStickChanged(let x, let y):
      return processAxes(
        [(.leftStickX, x), (.leftStickY, y)],
        for: identifier,
        at: uptimeNanoseconds
      )
    case .rightStickChanged(let x, let y):
      return processAxes(
        [(.rightStickX, x), (.rightStickY, y)],
        for: identifier,
        at: uptimeNanoseconds
      )
    case .leftTriggerChanged(let value):
      return processAxes(
        [(.leftTrigger, value)],
        for: identifier,
        at: uptimeNanoseconds
      )
    case .rightTriggerChanged(let value):
      return processAxes(
        [(.rightTrigger, value)],
        for: identifier,
        at: uptimeNanoseconds
      )
    }
  }

  private mutating func setDpad(
    _ direction: DpadDirection,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let nextDirections = Self.cardinalDirections(for: direction)
    let removed = device.dpadDirections.subtracting(nextDirections)
    let added = nextDirections.subtracting(device.dpadDirections)
    device.dpadDirections = nextDirections
    devices[identifier] = device

    var actions: [RemappingSystemInputAction] = []
    for direction in removed.sorted(by: Self.dpadLessThan) {
      actions += setSource(
        .dpad(direction),
        isActive: false,
        for: identifier,
        at: uptimeNanoseconds
      )
    }
    for direction in added.sorted(by: Self.dpadLessThan) {
      actions += setSource(
        .dpad(direction),
        isActive: true,
        for: identifier,
        at: uptimeNanoseconds
      )
    }
    return actions
  }

  private mutating func processAxes(
    _ values: [(RemappingAxis, Float)],
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    var actions: [RemappingSystemInputAction] = []
    for (axis, value) in values {
      actions += processAxis(
        axis,
        value: value,
        for: identifier,
        at: uptimeNanoseconds
      )
    }
    return actions
  }

  private mutating func processAxis(
    _ axis: RemappingAxis,
    value rawValue: Float,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let oldContinuous = continuousTotals()
    var actions: [RemappingSystemInputAction] = []

    if let binding = device.binding(for: .axis(axis)),
      let tuning = binding.axisTuning,
      let continuousDestination = RemappingContinuousDestination(binding.destination)
    {
      let transformed = RemappingTransform.value(rawValue, tuning: tuning)
      if transformed == 0 {
        device.continuous.removeValue(forKey: binding.id)
      } else {
        device.continuous[binding.id] = RemappingContinuousOutput(
          destination: continuousDestination,
          amount: transformed
        )
      }
    }

    for direction in [RemappingAxisDirection.negative, .positive] {
      let source = RemappingSource.axisDirection(axis, direction)
      guard let binding = device.binding(for: source), let tuning = binding.axisTuning else {
        continue
      }
      let transformed = RemappingTransform.value(rawValue, tuning: tuning)
      let wasActive = device.activeSources.contains(source)
      let isActive = RemappingTransform.isDirectionActive(
        value: transformed,
        direction: direction,
        threshold: tuning.digitalActivationThreshold,
        wasActive: wasActive
      )
      devices[identifier] = device
      actions += setSource(
        source,
        isActive: isActive,
        for: identifier,
        at: uptimeNanoseconds
      )
      guard let updated = devices[identifier] else { return actions }
      device = updated
    }
    devices[identifier] = device
    actions += stoppedContinuousActions(previous: oldContinuous)
    return actions
  }

  private mutating func setSource(
    _ source: RemappingSource,
    isActive: Bool,
    for identifier: DeviceIdentifier,
    at uptimeNanoseconds: UInt64
  ) -> [RemappingSystemInputAction] {
    guard var device = devices[identifier] else { return [] }
    let wasActive = device.activeSources.contains(source)
    guard wasActive != isActive else { return [] }
    if isActive {
      device.activeSources.insert(source)
    } else {
      device.activeSources.remove(source)
    }
    guard let binding = device.binding(for: source) else {
      devices[identifier] = device
      return []
    }

    var actions: [RemappingSystemInputAction] = []
    if let turbo = binding.turbo {
      if isActive {
        device.turbos[binding.id] = RemappingTurboOutput(
          destination: binding.destination,
          configuration: turbo,
          startedAt: uptimeNanoseconds,
          outputIsDown: true
        )
        actions += setBinding(
          binding.id,
          destination: binding.destination,
          isDown: true,
          device: &device
        )
      } else {
        device.turbos.removeValue(forKey: binding.id)
        actions += setBinding(
          binding.id,
          destination: binding.destination,
          isDown: false,
          device: &device
        )
      }
    } else {
      actions += setBinding(
        binding.id,
        destination: binding.destination,
        isDown: isActive,
        device: &device
      )
    }
    devices[identifier] = device
    return actions
  }

  static func source(for button: Button) -> RemappingSource? {
    switch button {
    case .a, .cross: .button(.south)
    case .b, .circle: .button(.east)
    case .x, .square: .button(.west)
    case .y, .triangle: .button(.north)
    case .leftBumper, .l1: .button(.leftShoulder)
    case .rightBumper, .r1: .button(.rightShoulder)
    case .leftStick: .button(.leftStick)
    case .rightStick: .button(.rightStick)
    case .start: .button(.start)
    case .back: .button(.back)
    case .guide, .ps: .button(.guide)
    case .share: .button(.share)
    case .options: .button(.options)
    case .touchpad: .button(.touchpad)
    case .l2Digital: .button(.auxiliary1)
    case .r2Digital: .button(.auxiliary2)
    case .genericButton1: .button(.auxiliary1)
    case .genericButton2: .button(.auxiliary2)
    case .genericButton3: .button(.auxiliary3)
    case .genericButton4: .button(.auxiliary4)
    case .genericButton5: .button(.auxiliary5)
    case .genericButton6: .button(.auxiliary6)
    case .genericButton7: .button(.auxiliary7)
    case .genericButton8: .button(.auxiliary8)
    case .dpadUp: .dpad(.up)
    case .dpadDown: .dpad(.down)
    case .dpadLeft: .dpad(.left)
    case .dpadRight: .dpad(.right)
    }
  }

  private static func cardinalDirections(
    for direction: DpadDirection
  ) -> Set<RemappingDpadDirection> {
    switch direction {
    case .neutral: []
    case .north: [.up]
    case .northEast: [.up, .right]
    case .east: [.right]
    case .southEast: [.down, .right]
    case .south: [.down]
    case .southWest: [.down, .left]
    case .west: [.left]
    case .northWest: [.up, .left]
    }
  }

  private static func dpadLessThan(
    _ lhs: RemappingDpadDirection,
    _ rhs: RemappingDpadDirection
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

struct RemappingDeviceState {
  let profile: RemappingProfile
  var activeSources: Set<RemappingSource> = []
  var dpadDirections: Set<RemappingDpadDirection> = []
  var heldBindings: [UUID: RemappingDestination] = [:]
  var turbos: [UUID: RemappingTurboOutput] = [:]
  var continuous: [UUID: RemappingContinuousOutput] = [:]

  func binding(for source: RemappingSource) -> RemappingBinding? {
    profile.bindings.first { $0.source == source }
  }
}
