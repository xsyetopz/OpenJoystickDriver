import Foundation
import OJDSDL3Shim

private let sdl3MaxGamepads = 64
private let sdl3PollIntervalNanoseconds: UInt64 = 8_000_000

public struct SDL3ConnectedGamepad: Sendable {
  public let identity: SDL3DeviceIdentity
  public let identifier: DeviceIdentifier
  public let snapshot: SDL3GamepadSnapshot
  public let supportsRumble: Bool
}

private final class SDL3OpenGamepad: @unchecked Sendable {
  let identity: SDL3DeviceIdentity
  let identifier: DeviceIdentifier
  let handle: OJDSDL3GamepadRef
  var snapshot: SDL3GamepadSnapshot
  var supportsRumble: Bool

  init(
    identity: SDL3DeviceIdentity,
    identifier: DeviceIdentifier,
    handle: OJDSDL3GamepadRef,
    snapshot: SDL3GamepadSnapshot,
    supportsRumble: Bool = true
  ) {
    self.identity = identity
    self.identifier = identifier
    self.handle = handle
    self.snapshot = snapshot
    self.supportsRumble = supportsRumble
  }
}

public final class SDL3GamepadSource: @unchecked Sendable {
  public typealias EventSink = @Sendable (DeviceIdentifier, [ControllerEvent]) async -> Void
  public typealias LifecycleSink = @Sendable (DeviceIdentifier) async -> Void

  private let lock = NSLock()
  private var didInitialize = false
  private var openGamepads: [Int32: SDL3OpenGamepad] = [:]

  public init() {}

  deinit { close() }

  public var linkedVersion: String {
    let raw = ojd_sdl3_linked_version()
    let major = raw / 1_000_000
    let minor = (raw / 1_000) % 1_000
    let patch = raw % 1_000
    return "\(major).\(minor).\(patch)"
  }

  public func start() -> Bool {
    lock.withLock {
      guard !didInitialize else { return true }
      didInitialize = ojd_sdl3_init()
      if !didInitialize {
        let message = String(cString: ojd_sdl3_error())
        print("[SDL3GamepadSource] SDL_Init failed: \(message)")
      } else {
        print("[SDL3GamepadSource] SDL initialized version=\(linkedVersion)")
        if !hasSDL3MacOSLibUSBBaseline {
          print(
            "[SDL3GamepadSource] SDL3 \(linkedVersion) is older than the macOS libusb gamepad "
              + "baseline (3.4.12); controllers that need SDL HIDAPI/libusb may not enumerate."
          )
        }
      }
      return didInitialize
    }
  }

  public func close() {
    lock.withLock {
      for entry in openGamepads.values { ojd_sdl3_close_gamepad(entry.handle) }
      openGamepads.removeAll()
      if didInitialize { ojd_sdl3_quit() }
      didInitialize = false
    }
  }

  public func connectedGamepads() -> [SDL3ConnectedGamepad] {
    lock.withLock {
      openGamepads.values.map {
        SDL3ConnectedGamepad(
          identity: $0.identity,
          identifier: $0.identifier,
          snapshot: $0.snapshot,
          supportsRumble: $0.supportsRumble
        )
      }
    }
  }

  public func inputState(for identifier: DeviceIdentifier) -> DeviceInputState? {
    lock.withLock {
      guard let entry = openGamepads.values.first(where: { $0.identifier.modelMatches(identifier) })
      else { return nil }
      var state = DeviceInputState(
        vendorID: entry.identifier.vendorID,
        productID: entry.identifier.productID
      )
      let neutral = SDL3GamepadSnapshot.neutral(
        vendorID: entry.identifier.vendorID,
        productID: entry.identifier.productID
      )
      state.apply(events: SDL3GamepadMapper.events(
        previous: neutral,
        current: entry.snapshot
      ))
      return state
    }
  }

  public func sendRumble(
    for identifier: DeviceIdentifier,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) -> Bool {
    lock.withLock {
      guard let entry = openGamepads.values.first(where: { $0.identifier.modelMatches(identifier) })
      else { return false }
      let duration = UInt32(max(0, min(durationMs, 5_000)))
      let low = UInt16(left) * 257
      let high = UInt16(right) * 257
      let triggerLeft = UInt16(lt) * 257
      let triggerRight = UInt16(rt) * 257
      let bodyOK = ojd_sdl3_rumble_gamepad(entry.handle, low, high, duration)
      let triggerOK = ojd_sdl3_rumble_gamepad_triggers(
        entry.handle,
        triggerLeft,
        triggerRight,
        duration
      )
      entry.supportsRumble = bodyOK || triggerOK
      return bodyOK || triggerOK
    }
  }

  public func pollOnce(onEvents: EventSink, onRemoved: LifecycleSink) async {
    let actions = lock.withLock { pollLocked() }
    for removed in actions.removed {
      await onEvents(removed.identifier, removed.neutralizingEvents)
      await onRemoved(removed.identifier)
    }
    for connected in actions.connected {
      await onEvents(connected, [])
    }
    for eventBatch in actions.events where !eventBatch.events.isEmpty {
      await onEvents(eventBatch.identifier, eventBatch.events)
    }
  }

  public static var pollIntervalNanoseconds: UInt64 { sdl3PollIntervalNanoseconds }

  private var hasSDL3MacOSLibUSBBaseline: Bool {
    ojd_sdl3_linked_version() >= 3_004_012
  }

  private struct RemovedAction {
    let identifier: DeviceIdentifier
    let neutralizingEvents: [ControllerEvent]
  }

  private struct PollActions {
    var connected: [DeviceIdentifier] = []
    var removed: [RemovedAction] = []
    var events: [(identifier: DeviceIdentifier, events: [ControllerEvent])] = []
  }

  private func pollLocked() -> PollActions {
    var actions = PollActions()
    guard didInitialize else { return actions }

    ojd_sdl3_pump()
    var idBuffer = [Int32](repeating: 0, count: sdl3MaxGamepads)
    let count = ojd_sdl3_get_gamepad_ids(&idBuffer, Int32(sdl3MaxGamepads))
    let currentIDs = Set(idBuffer.prefix(Int(count)))

    for removedID in Set(openGamepads.keys).subtracting(currentIDs) {
      guard let entry = openGamepads.removeValue(forKey: removedID) else { continue }
      let neutral = SDL3GamepadSnapshot.neutral(
        vendorID: entry.identifier.vendorID,
        productID: entry.identifier.productID
      )
      let events = SDL3GamepadMapper.events(previous: entry.snapshot, current: neutral)
      ojd_sdl3_close_gamepad(entry.handle)
      actions.removed.append(
        RemovedAction(identifier: entry.identifier, neutralizingEvents: events)
      )
    }

    for id in currentIDs where openGamepads[id] == nil {
      guard let identity = readIdentity(instanceID: id), !identity.isOpenJoystickDriverVirtualDevice
      else { continue }
      guard let handle = ojd_sdl3_open_gamepad(id) else {
        print("[SDL3GamepadSource] Open failed id=\(id): \(String(cString: ojd_sdl3_error()))")
        continue
      }
      let identifier = identity.deviceIdentifier
      let snapshot = readSnapshot(
        handle: handle,
        vendorID: identifier.vendorID,
        productID: identifier.productID
      )
        ?? .neutral(vendorID: identifier.vendorID, productID: identifier.productID)
      openGamepads[id] = SDL3OpenGamepad(
        identity: identity,
        identifier: identifier,
        handle: handle,
        snapshot: snapshot
      )
      print("[SDL3GamepadSource] Gamepad connected: \(identity.name) (\(identifier))")
      actions.connected.append(identifier)
      let initialEvents = SDL3GamepadMapper.events(
        previous: .neutral(vendorID: identifier.vendorID, productID: identifier.productID),
        current: snapshot
      )
      if !initialEvents.isEmpty { actions.events.append((identifier, initialEvents)) }
    }

    for (id, entry) in openGamepads {
      guard currentIDs.contains(id), let snapshot = readSnapshot(
        handle: entry.handle,
        vendorID: entry.identifier.vendorID,
        productID: entry.identifier.productID
      ) else { continue }
      let events = SDL3GamepadMapper.events(previous: entry.snapshot, current: snapshot)
      entry.snapshot = snapshot
      actions.events.append((entry.identifier, events))
    }

    return actions
  }

  private func readIdentity(instanceID: Int32) -> SDL3DeviceIdentity? {
    var raw = OJDSDL3DeviceIdentity()
    guard ojd_sdl3_get_identity(instanceID, &raw), raw.is_gamepad else { return nil }
    let name = withUnsafePointer(to: raw.name) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
    }
    let serial = withUnsafePointer(to: raw.serial) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: 128) { String(cString: $0) }
    }
    let guid = withUnsafePointer(to: raw.guid) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: 64) { String(cString: $0) }
    }
    return SDL3DeviceIdentity(
      instanceID: raw.instance_id,
      vendorID: raw.vendor_id,
      productID: raw.product_id,
      version: raw.version,
      name: name.isEmpty ? "SDL3 Gamepad" : name,
      serial: serial.isEmpty ? nil : serial,
      guid: guid.isEmpty ? nil : guid,
      locationID: nil
    )
  }

  private func readSnapshot(
    handle: OJDSDL3GamepadRef,
    vendorID: UInt16,
    productID: UInt16
  ) -> SDL3GamepadSnapshot? {
    var raw = OJDSDL3GamepadSnapshotRaw()
    guard ojd_sdl3_read_snapshot(handle, &raw) else { return nil }
    var axes: [SDL3GamepadAxis: Int16] = [:]
    withUnsafeBytes(of: raw.axes) { buffer in
      let values = buffer.bindMemory(to: Int16.self)
      for axis in SDL3GamepadAxis.allCases where axis.rawValue < values.count {
        axes[axis] = values[axis.rawValue]
      }
    }
    var buttons = Set<SDL3GamepadButton>()
    withUnsafeBytes(of: raw.buttons) { buffer in
      let values = buffer.bindMemory(to: UInt8.self)
      for button in SDL3GamepadButton.allCases where button.rawValue < values.count {
        if values[button.rawValue] != 0 { buttons.insert(button) }
      }
    }
    return SDL3GamepadSnapshot(
      vendorID: vendorID,
      productID: productID,
      buttons: buttons,
      axes: axes
    )
  }
}
