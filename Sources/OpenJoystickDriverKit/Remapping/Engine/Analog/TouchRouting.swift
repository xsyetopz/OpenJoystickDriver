import Foundation

/// A touch position on a surface.
struct RemappingTouchPoint: Equatable {
  /// Horizontal position as a fraction of the surface span.
  let x: Double
  /// Vertical position as a fraction of the surface span.
  let y: Double
}

/// Where a touch contact began and where it is.
struct RemappingTouchContactState: Equatable {
  /// Position of the first frame of the contact.
  let start: RemappingTouchPoint
  /// Position of the latest frame of the contact.
  let position: RemappingTouchPoint
}

/// Contacts of one touch surface, keyed by their slot within the surface's frames.
struct RemappingTouchSurfaceState {
  /// Active contacts by slot.
  var contacts: [UInt8: RemappingTouchContactState]
  /// Slot of the primary contact, or `nil` when nothing touches.
  var primaryContactID: UInt8?
}

extension RemappingEngineState {
  /// Applies one touch frame of a controller.
  ///
  /// The primary contact is the lowest slot and stays primary while it touches. The frame changes
  /// the touch contact and touch grid sources. A swipe source fires when the primary contact lifts
  /// after a long enough movement. The pointer or virtual stick mapping of the surface follows the
  /// primary contact.
  mutating func processTouch(
    _ sample: ControllerTouchSample,
    for identifier: LogicalControllerID,
    at uptime: UInt64
  ) -> [RemappingEngineAction] {
    guard var device = devices[identifier] else { return [] }
    let surface = RemappingTouchSurface(sample.surface)
    let previous = device.analog.touchSurfaces[surface]
    let oldContacts = previous?.contacts ?? [:]
    var contacts: [UInt8: RemappingTouchContactState] = [:]
    for contact in sample.contacts where contact.isActive {
      let point = Self.normalizedPoint(contact)
      contacts[contact.slot] = RemappingTouchContactState(
        start: oldContacts[contact.slot]?.start ?? point,
        position: point
      )
    }

    let oldPrimaryID = previous?.primaryContactID
    let primaryID = oldPrimaryID.flatMap { contacts[$0] == nil ? nil : $0 } ?? contacts.keys.min()
    let next = RemappingTouchSurfaceState(contacts: contacts, primaryContactID: primaryID)
    device.analog.touchSurfaces[surface] = next
    devices[identifier] = device
    let endedPrimaryContact = oldPrimaryID.flatMap { id -> RemappingTouchContactState? in
      guard contacts[id] == nil, let old = previous?.contacts[id] else { return nil }
      guard let final = sample.contacts.first(where: { $0.slot == id && !$0.isActive }) else {
        return old
      }
      return RemappingTouchContactState(start: old.start, position: Self.normalizedPoint(final))
    }

    var actions: [RemappingEngineAction] = []
    let possibleSources = device.profile.touchSources(on: surface)
    let oldDiscrete = device.activeSources.filter { $0.touchSurface == surface }
    var nextDiscrete: Set<RemappingSource> = []
    if primaryID != nil {
      nextDiscrete.formUnion(
        possibleSources.filter {
          switch $0 {
          case .touchContact: return true
          case .touchGrid(let grid):
            guard let primaryID, let contact = contacts[primaryID] else { return false }
            return Self.gridCell(for: contact.position, columns: grid.columns, rows: grid.rows) == (
              grid.column, grid.row
            )
          case .touchArea(let area): return contacts.values.contains { area.contains($0.position) }
          case .touchSwipe: return false
          case .button, .dpad, .axis, .axisDirection, .triggerStage, .motionLean, .stickRegion,
            .triggerBand:
            return false
          }
        }
      )
    }
    for source in oldDiscrete.subtracting(nextDiscrete).sorted(by: Self.touchSourceLessThan) {
      actions += setSource(source, isActive: false, for: identifier, at: uptime)
    }
    for source in nextDiscrete.subtracting(oldDiscrete).sorted(by: Self.touchSourceLessThan) {
      actions += setSource(source, isActive: true, for: identifier, at: uptime)
    }

    if let contact = endedPrimaryContact,
      let direction = Self.swipeDirection(from: contact.start, to: contact.position)
    {
      for source in possibleSources.sorted(by: Self.touchSourceLessThan) {
        guard case .touchSwipe(let swipe) = source, swipe.direction == direction,
          Self.swipeDistance(from: contact.start, to: contact.position, direction: direction)
            >= swipe.minimumDistance
        else { continue }
        actions += setSource(source, isActive: true, for: identifier, at: uptime)
        actions += setSource(source, isActive: false, for: identifier, at: uptime)
      }
    }

    guard let mapping = device.profile.touchMappings.first(where: { $0.surface == surface }) else {
      return actions
    }
    switch mapping.mode {
    case .pointer:
      guard let primaryID, primaryID == oldPrimaryID,
        let old = previous?.contacts[primaryID]?.position,
        let current = contacts[primaryID]?.position
      else { return actions }
      let x = (current.x - old.x) * mapping.pointerSensitivity
      let y = (current.y - old.y) * mapping.pointerSensitivity
      if x.isFinite, y.isFinite, x != 0 || y != 0 {
        actions.append(.system(.pointerDelta(x: x, y: y)))
      }
    case .leftStick, .rightStick:
      guard var updated = devices[identifier] else { return actions }
      let axes: [RemappingAxis: Double]
      if let primaryID, let contact = contacts[primaryID] {
        let value = Self.stickValue(contact, mapping: mapping)
        let horizontal: RemappingAxis = mapping.mode == .leftStick ? .leftStickX : .rightStickX
        let vertical: RemappingAxis = mapping.mode == .leftStick ? .leftStickY : .rightStickY
        axes = [horizontal: value.x, vertical: value.y]
      } else {
        axes = [:]
      }
      if let state = updated.outputs.gamepad.update(
        RemappingGamepadState(axes: axes),
        for: mapping.id
      ) {
        actions.append(.gamepad(state, identifier))
      }
      devices[identifier] = updated
    }
    return actions
  }

  /// Normalizes a contact position by the full range of its own axis, so each axis is a fraction of
  /// its own surface span.
  private static func normalizedPoint(_ contact: ControllerTouchContact) -> RemappingTouchPoint {
    let span = Double(UInt16.max)
    return RemappingTouchPoint(x: Double(contact.x) / span, y: Double(contact.y) / span)
  }

  /// Returns the grid cell, as column and row, that a position falls in.
  private static func gridCell(
    for point: RemappingTouchPoint,
    columns: Int,
    rows: Int
  ) -> (Int, Int) {
    (min(columns - 1, Int(point.x * Double(columns))), min(rows - 1, Int(point.y * Double(rows))))
  }

  /// Returns the main direction of a movement, or `nil` when the position did not change.
  private static func swipeDirection(
    from start: RemappingTouchPoint,
    to end: RemappingTouchPoint
  ) -> RemappingTouchSwipeDirection? {
    let x = end.x - start.x
    let y = end.y - start.y
    guard x != 0 || y != 0 else { return nil }
    if abs(x) >= abs(y) { return x < 0 ? .left : .right }
    return y < 0 ? .up : .down
  }

  /// Returns the travel of a swipe along its direction, as a surface fraction.
  private static func swipeDistance(
    from start: RemappingTouchPoint,
    to end: RemappingTouchPoint,
    direction: RemappingTouchSwipeDirection
  ) -> Double {
    switch direction {
    case .left, .right: abs(end.x - start.x)
    case .up, .down: abs(end.y - start.y)
    }
  }

  /// Returns the virtual stick position of a contact.
  ///
  /// The drag from the start point, divided by the stick radius, is limited to the unit circle and
  /// cut by the dead zone.
  private static func stickValue(
    _ contact: RemappingTouchContactState,
    mapping: RemappingTouchMapping
  ) -> RemappingTouchPoint {
    var x = (contact.position.x - contact.start.x) / mapping.stickRadius
    var y = (contact.position.y - contact.start.y) / mapping.stickRadius
    let magnitude = hypot(x, y)
    if magnitude <= mapping.deadzone { return RemappingTouchPoint(x: 0, y: 0) }
    if magnitude > 1 {
      x /= magnitude
      y /= magnitude
    }
    let scaledMagnitude = (min(magnitude, 1) - mapping.deadzone) / (1 - mapping.deadzone)
    return RemappingTouchPoint(
      x: x / min(magnitude, 1) * scaledMagnitude,
      y: y / min(magnitude, 1) * scaledMagnitude
    )
  }

  /// Orders touch sources so that actions are emitted in a stable order.
  private static func touchSourceLessThan(_ lhs: RemappingSource, _ rhs: RemappingSource) -> Bool {
    touchSourceSortKey(lhs) < touchSourceSortKey(rhs)
  }

  /// Returns the sort key of a touch source.
  ///
  /// Touch contacts sort before grids, grids before swipes, and swipes before other sources.
  private static func touchSourceSortKey(_ source: RemappingSource) -> String {
    switch source {
    case .touchContact(let surface): return "0:\(surface.rawValue)"
    case .touchGrid(let grid):
      return "1:\(grid.surface.rawValue):\(grid.columns):\(grid.rows):\(grid.column):\(grid.row)"
    case .touchSwipe(let swipe):
      return "2:\(swipe.surface.rawValue):\(swipe.direction.rawValue):\(swipe.minimumDistance)"
    case .touchArea(let area):
      return "3:\(area.surface.rawValue):\(area.x):\(area.y):\(area.width):\(area.height)"
    case .button, .dpad, .axis, .axisDirection, .triggerStage, .motionLean, .stickRegion,
      .triggerBand:
      return "4"
    }
  }
}

extension RemappingSource {
  /// Touch surface that the source reads, or `nil` for a source that is not a touch source.
  var touchSurface: RemappingTouchSurface? {
    switch self {
    case .touchContact(let surface): surface
    case .touchGrid(let grid): grid.surface
    case .touchSwipe(let swipe): swipe.surface
    case .touchArea(let area): area.surface
    case .button, .dpad, .axis, .axisDirection, .triggerStage, .motionLean, .stickRegion,
      .triggerBand:
      nil
    }
  }
}

extension RemappingProfile {
  /// Returns the touch sources on a surface that any part of the profile uses.
  func touchSources(on surface: RemappingTouchSurface) -> Set<RemappingSource> {
    allSources.filter { $0.touchSurface == surface }
  }
}
