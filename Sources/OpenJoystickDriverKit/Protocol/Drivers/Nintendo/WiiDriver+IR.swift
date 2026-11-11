import Foundation

extension WiiDriver {
  /// One point the IR camera sees, in the camera's 1024 by 768 raw grid.
  struct IRPoint: Equatable {
    /// The horizontal position.
    let x: Int
    /// The vertical position.
    let y: Int
    /// The size nibble of the extended and full formats; 0 in the basic format.
    let size: Int
  }

  /// The aim the IR points give: each axis runs from -1 to 1, Y positive down.
  struct Pointer: Equatable {
    /// The horizontal position.
    var x: Float = 0
    /// The vertical position.
    var y: Float = 0
    /// Whether two points are visible (`IRPointerLost` clears it and holds `x` and `y`).
    var isTracking = false
  }

  /// The block kinds that carry IR bytes.
  private static let irKinds: Set<ProtocolDescription.WiiRemote.BlockKind> = [
    .irBasic, .irExtended, .irFull,
  ]
  /// The camera's raw grid.
  private static let irGeometry = ControllerTouchGeometry(
    originX: 0,
    originY: 0,
    width: 1024,
    height: 768,
    rawYIncreasesUpward: false
  )
  /// The raw value of both axes of a slot that sees no point.
  private static let irEmptyValue = 1023
  /// The report that carries the third and fourth points of the full format.
  private static let irFullSecondReportID: UInt8 = 0x3F

  /// Decodes the IR block of `mode` into the touch contacts and the pointer; nil for a mode
  /// without one.
  func decodeIR(
    _ mode: ProtocolDescription.WiiRemote.ReportMode,
    _ bytes: [UInt8],
    into next: inout ControllerState,
    at now: MonotonicTimestamp
  ) -> ControllerTouchSample? {
    guard let block = mode.blocks.first(where: { Self.irKinds.contains($0.kind) }) else {
      return nil
    }
    let data = Array(bytes[(1 + block.offset)..<(1 + block.offset + block.length)])
    // A point from its two low bytes and the byte whose bits 5-4 and 7-6 are the high bits of X
    // and Y.
    func point(_ low: ArraySlice<UInt8>, size: Int, high: UInt8) -> IRPoint? {
      let x = Int(low[low.startIndex]) | Int(high >> 4 & 0b11) << 8
      let y = Int(low[low.startIndex + 1]) | Int(high >> 6) << 8
      guard x != Self.irEmptyValue || y != Self.irEmptyValue else { return nil }
      return IRPoint(x: x, y: y, size: size)
    }
    switch block.kind {
    case .irBasic:
      for pair in 0..<2 {
        let chunk = data[(pair * 5)..<(pair * 5 + 5)]
        let high = chunk[chunk.startIndex + 2]
        irPoints[2 * pair] = point(chunk.prefix(2), size: 0, high: high)
        // The second point keeps its high bits in the low nibble of the shared byte.
        irPoints[2 * pair + 1] = point(chunk.suffix(2), size: 0, high: high << 4)
      }
    case .irExtended:
      for slot in 0..<4 {
        let chunk = data[(slot * 3)..<(slot * 3 + 3)]
        let high = chunk[chunk.startIndex + 2]
        irPoints[slot] = point(chunk.prefix(2), size: Int(high & 0x0F), high: high)
      }
    default:
      let base = mode.id == Self.irFullSecondReportID ? 2 : 0
      for slot in 0..<2 {
        let chunk = data[(slot * 9)..<(slot * 9 + 3)]
        let high = chunk[chunk.startIndex + 2]
        irPoints[base + slot] = point(chunk.prefix(2), size: Int(high & 0x0F), high: high)
      }
    }
    updatePointer(&next)
    let contacts = irPoints.enumerated().map { slot, point in
      Self.irGeometry.contact(
        slot: UInt8(slot),
        isActive: point != nil,
        rawX: Int32(point?.x ?? 0),
        rawY: Int32(point?.y ?? 0)
      )
    }
    let frame = ControllerTouchSample(timestamp: now, contacts: contacts)
    next.recordTouch([frame])
    return frame
  }

  /// Sets the pointer from the midpoint of the two largest points, turned by the roll of the
  /// remote and mirrored; with fewer than two points it only clears tracking.
  private func updatePointer(_ next: inout ControllerState) {
    let visible = irPoints.compactMap { $0 }.enumerated()
      .sorted { ($0.element.size, $1.offset) > ($1.element.size, $0.offset) }
      .prefix(2).map(\.element)
    pointer.isTracking = visible.count == 2
    next.set(.pointerTracking, pressed: pointer.isTracking)
    guard visible.count == 2 else { return }
    let dx = Float(visible[0].x + visible[1].x) / 2 - 511.5
    let dy = Float(visible[0].y + visible[1].y) / 2 - 383.5
    let roll = rollAngle()
    let x = dx * cos(roll) - dy * sin(roll)
    let y = dx * sin(roll) + dy * cos(roll)
    pointer.x = min(max(-x / 511.5, -1), 1)
    pointer.y = min(max(-y / 383.5, -1), 1)
    next.pointer = StickPosition(x: pointer.x, y: pointer.y)
  }

  /// The roll about the pointing axis in radians, from the accelerometer reading in units of
  /// gravity; 0 without a reading or a calibration.
  private func rollAngle() -> Float {
    guard let acceleration, let calibration = accelerometerCalibration else { return 0 }
    func gravityUnits(_ raw: Int, _ zero: Int, _ gravity: Int) -> Float {
      Float(raw - zero) / Float(gravity - zero)
    }
    return atan2(
      gravityUnits(acceleration.x, calibration.zero.x, calibration.gravity.x),
      gravityUnits(acceleration.z, calibration.zero.z, calibration.gravity.z)
    )
  }
}
