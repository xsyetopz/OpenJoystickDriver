/// Encoder of 16-bit samples to 4-bit Yamaha ADPCM, the speaker's format.
///
/// WiiBrew's Wiimote page names the codec and the packet layout but publishes no table; the step
/// scale `indexScale` and the limits are those of ffmpeg's `adpcm_yamaha`. The first sample of a
/// byte is in the low nibble.
struct WiiSpeakerEncoder: Equatable {
  /// The step multiplier of each magnitude, in 1/256.
  private static let indexScale = [230, 230, 230, 230, 307, 409, 512, 614]
  /// The smallest step.
  private static let minimumStep = 127
  /// The largest step.
  private static let maximumStep = 24_576

  /// The sample the decoder holds after the latest nibble.
  private(set) var predictor = 0
  /// The size of one quantizer step.
  private(set) var step = minimumStep

  /// The nibble for `sample`, advancing the state the way the decoder does.
  mutating func nibble(for sample: Int16) -> UInt8 {
    let delta = Int(sample) - predictor
    let magnitude = min(7, abs(delta) * 4 / step)
    let change = step * (2 * magnitude + 1) / 8
    predictor = min(32_767, max(-32_768, predictor + (delta < 0 ? -change : change)))
    step = min(Self.maximumStep, max(Self.minimumStep, (step * Self.indexScale[magnitude]) >> 8))
    return UInt8(magnitude | (delta < 0 ? 8 : 0))
  }

  /// The packed bytes of `samples`; an odd count ends with a zero sample.
  mutating func encode(_ samples: [Int16]) -> [UInt8] {
    stride(from: 0, to: samples.count, by: 2).map { index in
      let low = nibble(for: samples[index])
      let high = nibble(for: index + 1 < samples.count ? samples[index + 1] : 0)
      return low | high << 4
    }
  }
}

/// Paces encoded audio into packets at the speaker's rate.
struct WiiSpeakerStream {
  /// The data bytes of one packet.
  static let packetBytes = 20

  private let packets: [[UInt8]]
  private let interval: UInt64
  private var started: MonotonicTimestamp?
  private var sent = 0

  /// Splits `encoded` into packets of 20 bytes, each lasting 40 samples at `rate`.
  init(encoded: [UInt8], rate: Int) {
    packets = stride(from: 0, to: encoded.count, by: Self.packetBytes).map {
      Array(encoded[$0..<min($0 + Self.packetBytes, encoded.count)])
    }
    interval = UInt64(Self.packetBytes * 2) * 1_000_000_000 / UInt64(rate)
  }

  /// Whether every packet is out.
  var isFinished: Bool { sent == packets.count }

  /// The time the next packet falls due; nil before the first call of `due(at:)` and when
  /// finished.
  var nextDue: MonotonicTimestamp? {
    guard let started, !isFinished else { return nil }
    return MonotonicTimestamp(nanoseconds: started.nanoseconds + UInt64(sent) * interval)
  }

  /// The packets due at `now`: the first call starts the clock and sends the first packet, and
  /// each later packet falls due one packet duration after the one before.
  mutating func due(at now: MonotonicTimestamp) -> [[UInt8]] {
    let start = started ?? now
    started = start
    let count = min(packets.count, Int((now.nanoseconds - start.nanoseconds) / interval) + 1)
    defer { sent = max(sent, count) }
    return Array(packets[sent..<max(sent, count)])
  }
}
