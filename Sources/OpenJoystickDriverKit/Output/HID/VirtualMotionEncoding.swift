enum VirtualMotionEncoding {
  static func signed16(_ value: Double, unitsPerCount: Double) -> (UInt8, UInt8) {
    guard value.isFinite, unitsPerCount.isFinite, unitsPerCount > 0 else { return (0, 0) }
    let scaled = value / unitsPerCount
    let rounded = scaled.rounded()
    let clamped = max(Double(Int16.min), min(Double(Int16.max), rounded))
    let bits = UInt16(bitPattern: Int16(clamped))
    return (UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8))
  }

  static func writeSonyMotion(
    _ state: VirtualGamepadState,
    into report: inout [UInt8],
    at offset: Int
  ) {
    guard let motion = state.motion else { return }
    write(motion.gyroscopeDegreesPerSecond, unitsPerCount: 1.0 / 16, into: &report, at: offset)
    write(motion.accelerationG, unitsPerCount: 1.0 / 8192, into: &report, at: offset + 6)
  }

  static func writeNintendoMotion(
    _ state: VirtualGamepadState,
    into report: inout [UInt8],
    at offset: Int
  ) {
    let samples =
      state.motionSamples.count == 3
      ? state.motionSamples : Array(repeating: state.motion, count: 3).compactMap { $0 }
    guard samples.count == 3 else { return }
    for (sample, motion) in samples.enumerated() {
      let gyro = nintendoRaw(motion.gyroscopeDegreesPerSecond, unitsPerCount: 1.0 / 14.2842)
      let acceleration = nintendoRaw(motion.accelerationG, unitsPerCount: 1.0 / 4096)
      let start = offset + sample * 12
      writeRaw(acceleration, into: &report, at: start)
      writeRaw(gyro, into: &report, at: start + 6)
    }
  }

  static func writeUnsigned<T: FixedWidthInteger>(
    _ value: T,
    into report: inout [UInt8],
    at offset: Int
  ) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { bytes in
      report.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }
  }

  static func ticks(nanoseconds: UInt64, numerator: UInt64, denominator: UInt64) -> UInt64 {
    nanoseconds / denominator * numerator + nanoseconds % denominator * numerator / denominator
  }

  private static func write(
    _ vector: ControllerMotionVector,
    unitsPerCount: Double,
    into report: inout [UInt8],
    at offset: Int
  ) {
    writeRaw(
      (
        signed16(vector.x, unitsPerCount: unitsPerCount),
        signed16(vector.y, unitsPerCount: unitsPerCount),
        signed16(vector.z, unitsPerCount: unitsPerCount)
      ),
      into: &report,
      at: offset
    )
  }

  private static func nintendoRaw(
    _ vector: ControllerMotionVector,
    unitsPerCount: Double
  ) -> ((UInt8, UInt8), (UInt8, UInt8), (UInt8, UInt8)) {
    (
      signed16(-vector.z, unitsPerCount: unitsPerCount),
      signed16(-vector.x, unitsPerCount: unitsPerCount),
      signed16(vector.y, unitsPerCount: unitsPerCount)
    )
  }

  private static func writeRaw(
    _ vector: ((UInt8, UInt8), (UInt8, UInt8), (UInt8, UInt8)),
    into report: inout [UInt8],
    at offset: Int
  ) {
    report[offset] = vector.0.0
    report[offset + 1] = vector.0.1
    report[offset + 2] = vector.1.0
    report[offset + 3] = vector.1.1
    report[offset + 4] = vector.2.0
    report[offset + 5] = vector.2.1
  }
}
