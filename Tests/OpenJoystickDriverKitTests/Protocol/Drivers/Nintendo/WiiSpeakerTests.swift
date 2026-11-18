import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct WiiSpeakerTests {
  private func reports(_ plan: PhysicalOutputPlan) -> [[UInt8]] {
    plan.writes.compactMap { if case .hidOutput(let report) = $0 { report.bytes } else { nil } }
  }

  /// The nibbles `0, 7, F, 7, F, 2, 0, 9` come from ffmpeg's `adpcm_yamaha` step scale, worked
  /// through in a separate script; WiiBrew names the codec but publishes no table.
  @Test
  func encoderMatchesReferenceVector() {
    var encoder = WiiSpeakerEncoder()
    let bytes = encoder.encode([0, 1000, -1000, 32767, -32768, 500, 500, 0])
    #expect(bytes == [0x70, 0x7F, 0x2F, 0x90])
    #expect(encoder.predictor == -406)
    #expect(encoder.step == 3039)
  }

  @Test
  func oddSampleCountEndsWithZeroSample() {
    var encoder = WiiSpeakerEncoder()
    #expect(encoder.encode([0, 1000, -1000]).count == 2)
  }

  @Test
  func twentyByteDataReportCarriesItsLengthInHighBitsAndRumbleBit() throws {
    let driver = WiiDriver(tuning: nil, irFormat: nil)
    let data = [UInt8](repeating: 0xAB, count: 20)
    #expect(reports(try driver.encode(.speaker(.data(data)))) == [[0x18, 0xA0] + data])
    _ = try driver.encode(.setRumble(RumbleIntensities(lowFrequency: .max), duration: .held))
    #expect(reports(try driver.encode(.speaker(.data(data)))) == [[0x18, 0xA1] + data])
    let short = reports(try driver.encode(.speaker(.data([1, 2, 3]))))
    #expect(short == [[0x18, 0x19, 1, 2, 3] + [UInt8](repeating: 0, count: 17)])
  }

  @Test
  func packetOfNoBytesOrMoreThanTwentyIsRefused() {
    let driver = WiiDriver(tuning: nil, irFormat: nil)
    #expect(throws: ControllerOutputError.invalidValue) {
      try driver.encode(.speaker(.data([])))
    }
    #expect(throws: ControllerOutputError.invalidValue) {
      try driver.encode(.speaker(.data([UInt8](repeating: 0, count: 21))))
    }
  }

  @Test(arguments: [false, true])
  func startAndStopScriptsMatchSpeakerFixture(rumbling: Bool) throws {
    let driver = WiiDriver(tuning: nil, irFormat: nil)
    if rumbling {
      _ = try driver.encode(.setRumble(RumbleIntensities(lowFrequency: .max), duration: .held))
    }
    let expected = try WiiFixtureFolder.sequences
      .byteStrings(rumbling ? "speaker-rumble-on" : "speaker-rumble-off").map(Array.init)
    #expect(reports(try driver.encode(.speaker(.start(seconds: 1)))) == expected)
    let stop = reports(try driver.encode(.speaker(.stop)))
    #expect(stop.map { $0[0] } == [0x19, 0x14])
    #expect(stop.allSatisfy { $0[1] & 1 == (rumbling ? 1 : 0) })
  }

  @Test
  func clipLongerThanTuningLimitOrEmptyIsRefused() {
    let driver = WiiDriver(tuning: nil, irFormat: nil)
    #expect(throws: ControllerOutputError.invalidValue) {
      try driver.encode(.speaker(.start(seconds: 10.5)))
    }
    #expect(throws: ControllerOutputError.invalidValue) {
      try driver.encode(.speaker(.start(seconds: 0)))
    }
  }

  @Test
  func speakerRateEqualsDescriptionDivisor() throws {
    let wii = try #require(PhysicalProtocolID.nintendoWii.protocolDescription.wiiRemote)
    let config = wii.scripts.speaker.compactMap { step -> [UInt8]? in
      if case .write(_, let bytes) = step, bytes.count == 7 { bytes } else { nil }
    }
    let divisor = Int(config[0][2]) | Int(config[0][3]) << 8
    #expect(12_000_000 / divisor == PhysicalSpeakerFormat.yamahaADPCM4Bit.sampleRate)
  }

  @Test
  func streamSendsOnePacketPerFortySamplesOnInjectedClock() {
    var stream = WiiSpeakerStream(encoded: [UInt8](repeating: 1, count: 50), rate: 6_000)
    let interval: UInt64 = 40 * 1_000_000_000 / 6_000
    func at(_ nanoseconds: UInt64) -> MonotonicTimestamp { .init(nanoseconds: nanoseconds) }
    #expect(stream.nextDue == nil)
    #expect(stream.due(at: at(1_000)).map(\.count) == [20])
    #expect(stream.nextDue == at(1_000 + interval))
    #expect(stream.due(at: at(1_000 + interval - 1)).isEmpty)
    #expect(stream.due(at: at(1_000 + interval)).map(\.count) == [20])
    #expect(!stream.isFinished)
    #expect(stream.due(at: at(1_000 + 10 * interval)).map(\.count) == [10])
    #expect(stream.isFinished)
    #expect(stream.due(at: at(1_000 + 20 * interval)).isEmpty)
    #expect(stream.nextDue == nil)
  }
}
