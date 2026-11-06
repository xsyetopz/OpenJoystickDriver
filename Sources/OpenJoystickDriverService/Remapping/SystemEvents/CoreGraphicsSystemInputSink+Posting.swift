import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OpenJoystickDriverKit

extension CoreGraphicsSystemInputSink {

  /// Posts `action` as a keyboard or pointer event.
  ///
  /// - Throws: ``CoreGraphicsSystemInputSinkError`` when post-event access is not granted, the key
  ///   is unsupported, or CoreGraphics cannot prepare or post the event.
  public func send(_ action: RemappingSystemInputAction) throws {
    lock.lock()
    defer { lock.unlock() }
    guard access.currentState() == .granted else {
      throw CoreGraphicsSystemInputSinkError.postEventAccessNotGranted
    }
    do { try sendAuthorized(action) } catch let error as CoreGraphicsSystemInputSinkError {
      throw error
    } catch CoreGraphicsEventPosterError.eventCreationFailed {
      throw CoreGraphicsSystemInputSinkError.eventPreparationFailed
    } catch { throw CoreGraphicsSystemInputSinkError.eventPostingFailed }
  }

  /// Posts `action` once access is known to be granted.
  private func sendAuthorized(_ action: RemappingSystemInputAction) throws {
    switch action {
    case .modifierDown(let modifier): try postModifier(modifier, isDown: true)
    case .modifierUp(let modifier): try postModifier(modifier, isDown: false)
    case .keyDown(let key): try postKey(key, isDown: true)
    case .keyUp(let key): try postKey(key, isDown: false)
    case .mouseButtonDown(let button): try postMouseButton(button, isDown: true)
    case .mouseButtonUp(let button): try postMouseButton(button, isDown: false)
    case .mouseMoved(let axis, let amount): try postPointer(axis: axis, amount: amount)
    case .pointerDelta(let x, let y): try postPointerDelta(x: x, y: y)
    case .scrolled(let axis, let amount): try postScroll(axis: axis, amount: amount)
    case .scrollDelta(let deltaX, let deltaY): try postScrollDelta(x: deltaX, y: deltaY)
    }
  }

  /// Posts a modifier key press or release and updates the held modifiers.
  private func postModifier(_ modifier: RemappingKeyModifier, isDown: Bool) throws {
    let flag = CoreGraphicsMapping.coreGraphicsFlag(for: modifier)
    var candidate = modifierFlags
    if isDown { candidate.insert(flag) } else { candidate.remove(flag) }
    try poster.post(
      .modifier(virtualKey: CoreGraphicsMapping.virtualKey(for: modifier), flags: candidate)
    )
    modifierFlags = candidate
  }

  /// Posts a key press or release with the held modifiers.
  private func postKey(_ key: RemappingKeyboardKey, isDown: Bool) throws {
    guard let virtualKey = translator.virtualKey(for: key) else {
      throw CoreGraphicsSystemInputSinkError.unsupportedKeyboardKey(key)
    }
    try poster.post(.keyboard(virtualKey: virtualKey, isDown: isDown, flags: modifierFlags))
  }

  /// Posts a mouse button press or release at the current pointer position.
  private func postMouseButton(_ button: RemappingMouseButton, isDown: Bool) throws {
    let location = try poster.currentPointerLocation()
    let cgButton = CoreGraphicsMapping.coreGraphicsButton(for: button)
    try poster.post(.mouseButton(button: cgButton, isDown: isDown, location: location))
  }

  /// Moves the pointer along `axis` by `amount`, from -1 to 1, of the points of a full action.
  ///
  /// The current pointer position is read for each action, so physical mouse movement is kept.
  private func postPointer(axis: RemappingPointerAxis, amount: Double) throws {
    guard amount.isFinite else { throw CoreGraphicsSystemInputSinkError.eventPreparationFailed }
    if amount == 0 { return }
    let delta = CoreGraphicsMapping.clampedNormalized(amount) * Self.pointerPointsPerAction
    // Read every action so physical mouse movement between remapping ticks is
    // never overwritten by a stale synthetic-cursor cache.
    let origin = try poster.currentPointerLocation()
    let deltaX = axis == .x ? delta : 0
    let deltaY = axis == .y ? delta : 0
    let destination = CGPoint(x: origin.x + deltaX, y: origin.y + deltaY)
    try poster.post(.pointer(location: destination, deltaX: deltaX, deltaY: deltaY))
  }

  /// Moves the pointer by `x` and `y` points.
  private func postPointerDelta(x: Double, y: Double) throws {
    guard x.isFinite, y.isFinite else {
      throw CoreGraphicsSystemInputSinkError.eventPreparationFailed
    }
    guard x != 0 || y != 0 else { return }
    let origin = try poster.currentPointerLocation()
    let destination = CGPoint(x: origin.x + x, y: origin.y + y)
    guard destination.x.isFinite, destination.y.isFinite else {
      throw CoreGraphicsSystemInputSinkError.eventPreparationFailed
    }
    try poster.post(.pointer(location: destination, deltaX: x, deltaY: y))
  }

  /// Scrolls along `axis` by `amount`, from -1 to 1, of the lines of a full action.
  ///
  /// The part of a line that is not scrolled yet carries over to the next scroll.
  private func postScroll(axis: RemappingPointerAxis, amount: Double) throws {
    guard amount.isFinite else { throw CoreGraphicsSystemInputSinkError.eventPreparationFailed }
    if amount == 0 {
      if axis == .x { scrollResidualX = 0 } else { scrollResidualY = 0 }
      return
    }
    var candidateX = scrollResidualX
    var candidateY = scrollResidualY
    if axis == .x {
      candidateX += CoreGraphicsMapping.clampedNormalized(amount) * Self.scrollLinesPerAction
    } else {
      candidateY += CoreGraphicsMapping.clampedNormalized(amount) * Self.scrollLinesPerAction
    }
    let deltaX = Int32(candidateX.rounded(.towardZero))

    let deltaY = Int32(candidateY.rounded(.towardZero))
    candidateX -= Double(deltaX)
    candidateY -= Double(deltaY)
    if deltaX != 0 || deltaY != 0 { try poster.post(.scroll(deltaX: deltaX, deltaY: deltaY)) }
    scrollResidualX = candidateX
    scrollResidualY = candidateY
  }

  /// Scrolls by `x` and `y` lines; the part of a line that is not scrolled yet carries over.
  private func postScrollDelta(x: Double, y: Double) throws {
    guard x.isFinite, y.isFinite else {
      throw CoreGraphicsSystemInputSinkError.eventPreparationFailed
    }
    var candidateX = scrollResidualX + x
    var candidateY = scrollResidualY + y
    let deltaX = Int32(clamping: Int64(candidateX.rounded(.towardZero)))
    let deltaY = Int32(clamping: Int64(candidateY.rounded(.towardZero)))
    candidateX -= Double(deltaX)
    candidateY -= Double(deltaY)
    if deltaX != 0 || deltaY != 0 { try poster.post(.scroll(deltaX: deltaX, deltaY: deltaY)) }
    scrollResidualX = candidateX
    scrollResidualY = candidateY
  }
}
