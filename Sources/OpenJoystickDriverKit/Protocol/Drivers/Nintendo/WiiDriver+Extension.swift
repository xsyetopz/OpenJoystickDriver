import Foundation

extension WiiDriver {
  /// Applies the six data bytes of the plugged Nunchuk or Classic Controller to `next`.
  ///
  /// A stick's center is its value in the first sample after the handshake
  /// (`ExtensionCenterFromFirstSample`); the range is the description's `halfRange`. Wire Y grows
  /// upward, the state's grows downward. A button that shares a control with a core button only
  /// adds a press.
  func decodeExtension(_ data: [UInt8], into next: inout ControllerState) {
    guard case .known(let kind) = extensionKind,
      let layout = wii.extensions.first(where: { $0.kind == kind })?.layout
    else { return }
    let core = Set(wii.coreButtons.map(\.control))
    for button in layout.buttons {
      let down = (data[button.field.byte] & button.field.mask != 0) == button.pressedWhenSet
      if down || !core.contains(button.control) { next.set(button.control, pressed: down) }
    }
    for stick in layout.sticks {
      let raw = stick.field.value(in: data)
      let center = extensionCenters[stick.control] ?? raw
      extensionCenters[stick.control] = center
      let value = Float(raw - center) / Float(stick.halfRange)
      switch stick.control {
      case .leftStickX: next.leftStick.x = BipolarValue(normalized: value)
      case .leftStickY: next.leftStick.y = BipolarValue(normalized: -value)
      case .rightStickX: next.rightStick.x = BipolarValue(normalized: value)
      default: next.rightStick.y = BipolarValue(normalized: -value)
      }
    }
    for trigger in layout.triggers {
      let top = Float((1 << trigger.field.bits) - 1)
      let value = UnipolarValue(normalized: Float(trigger.field.value(in: data)) / top)
      if trigger.control == .leftTrigger {
        next.leftTrigger = value
      } else {
        next.rightTrigger = value
      }
    }
  }

  /// The remote's accelerometer reading in metres per second squared.
  ///
  /// The axes keep the remote's own order until Hardware Check 3 records them against the
  /// canonical frame. Empty before the calibration is read.
  func motionSamples(at now: MonotonicTimestamp) -> [ControllerMotionSample] {
    guard let raw = acceleration, let calibration = accelerometerCalibration else { return [] }
    func metres(_ value: Int, _ zero: Int, _ gravity: Int) -> Double {
      Double(value - zero) / Double(gravity - zero) * ControllerMotionUnits.standardGravity
    }
    defer { motionSequence += 1 }
    return ControllerMotionSample(
      timestamp: ControllerSampleTimestamp(
        rawCounter: 0,
        monotonic: now,
        tickNanosecondsNumerator: nil,
        tickNanosecondsDenominator: nil,
        sequenceIndex: motionSequence,
        basis: .hostEstimate
      ),
      acceleration: ControllerMotionVector(
        x: metres(raw.x, calibration.zero.x, calibration.gravity.x),
        y: metres(raw.y, calibration.zero.y, calibration.gravity.y),
        z: metres(raw.z, calibration.zero.z, calibration.gravity.z)
      ),
      angularVelocity: ControllerMotionVector(x: 0, y: 0, z: 0),
      calibrationSource: .deviceFactory
    ).map { [$0] } ?? []
  }
}
