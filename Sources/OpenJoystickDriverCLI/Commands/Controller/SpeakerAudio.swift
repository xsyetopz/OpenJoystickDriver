import Foundation

/// A PCM WAV file read as mono samples at a speaker's rate.
struct SpeakerAudio: Equatable {
  /// The file is not a PCM WAV file the speaker can play.
  struct Unsupported: Error {}

  /// Mono 16-bit samples at the requested rate, at most the requested length.
  let samples: [Int16]
  /// Whether the clip was longer than the limit and was cut.
  let isTrimmed: Bool

  /// Mixes the channels of `wav` down to mono, resamples to `rate`, scales by `volume` and keeps
  /// at most `maxSeconds`.
  ///
  /// Downsampling averages the source frames under each output sample; upsampling interpolates.
  ///
  /// - Throws: ``Unsupported`` unless `wav` is RIFF WAVE with 8, 16, 24 or 32-bit integer PCM.
  init(wav: Data, rate: Int, maxSeconds: Int, volume: Double) throws {
    let bytes = [UInt8](wav)
    func little(_ offset: Int, _ count: Int) -> Int {
      (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
    }
    guard bytes.count >= 12, bytes[0..<4].elementsEqual("RIFF".utf8),
      bytes[8..<12].elementsEqual("WAVE".utf8)
    else { throw Unsupported() }
    var format: (channels: Int, rate: Int, bits: Int)?
    var offset = 12
    while offset + 8 <= bytes.count {
      let name = String(bytes: bytes[offset..<offset + 4], encoding: .utf8) ?? ""
      let start = offset + 8
      let size = min(little(offset + 4, 4), bytes.count - start)
      if name == "fmt " {
        guard size >= 16, little(start, 2) == 1 else { throw Unsupported() }
        format = (little(start + 2, 2), little(start + 4, 4), little(start + 14, 2))
      } else if name == "data" {
        guard let format, [8, 16, 24, 32].contains(format.bits), format.channels > 0,
          format.rate > 0
        else { throw Unsupported() }
        let width = format.bits / 8
        let frames = size / (width * format.channels)
        guard frames > 0 else { throw Unsupported() }
        let signBit = 1 << (format.bits - 1)
        func frame(_ index: Int) -> Double {
          let sum = (0..<format.channels).reduce(0.0) { sum, channel in
            let raw = little(start + (index * format.channels + channel) * width, width)
            // 8-bit PCM is unsigned; wider PCM is two's complement.
            let value = width == 1 ? raw - signBit : (raw ^ signBit) - signBit
            return sum + Double(value) / Double(signBit)
          }
          return sum / Double(format.channels)
        }
        let ratio = Double(format.rate) / Double(rate)
        let available = Int(Double(frames) / ratio)
        let count = min(available, maxSeconds * rate)
        isTrimmed = available > count
        samples = (0..<count).map { index in
          let from = Double(index) * ratio
          let low = Int(from)
          let value: Double
          if ratio > 1 {
            let high = min(frames, max(low + 1, Int(from + ratio)))
            value = (low..<high).reduce(0.0) { $0 + frame($1) } / Double(high - low)
          } else {
            let weight = from - Double(low)
            value = frame(low) * (1 - weight) + frame(min(low + 1, frames - 1)) * weight
          }
          return Int16(max(-1, min(1, value * volume)) * 32_767)
        }
        return
      }
      offset = start + size + size % 2
    }
    throw Unsupported()
  }
}
