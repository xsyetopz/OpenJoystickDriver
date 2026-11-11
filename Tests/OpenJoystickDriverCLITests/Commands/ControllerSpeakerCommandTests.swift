import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ControllerSpeakerCommandTests {
  private static let wii = PhysicalControllerOutputCapabilities(speaker: .yamahaADPCM4Bit)

  private static func remote(maxSeconds: Int = 10) -> ApplicationServiceDeviceDescription {
    .fixture(
      id: "wii-1",
      outputs: wii,
      tuning: ControllerTuning(speakerMaxSeconds: maxSeconds)
    )
  }

  private static func answering(
    _ outcome: ControllerOutputResult.Outcome = .delivered
  ) -> FakeService.Respond {
    { method, _ in
      [.playControllerSpeaker, .stopControllerSpeaker].contains(method)
        ? encoded(ControllerOutputResult(outcome)) : nil
    }
  }

  /// A 16-bit WAV file of `seconds` of a 440 Hz tone with format tag `format` (1 is PCM), in a
  /// new temporary directory.
  private static func wav(
    seconds: Int,
    rate: Int = 8_000,
    channels: Int = 2,
    format: UInt16 = 1
  ) throws -> String {
    func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
      withUnsafeBytes(of: value.littleEndian) { unsafe Array($0) }
    }
    let frames = seconds * rate
    var data: [UInt8] = []
    for index in 0..<frames {
      let sample = Int16(16_000 * sin(2 * Double.pi * 440 * Double(index) / Double(rate)))
      for _ in 0..<channels { data += le(sample) }
    }
    var bytes = Array("RIFF".utf8) + le(UInt32(36 + data.count)) + Array("WAVEfmt ".utf8)
    bytes += le(UInt32(16)) + le(format) + le(UInt16(channels)) + le(UInt32(rate))
    bytes += le(UInt32(rate * channels * 2)) + le(UInt16(channels * 2)) + le(UInt16(16))
    bytes += Array("data".utf8) + le(UInt32(data.count)) + data
    return try write(Data(bytes), named: "clip.wav")
  }

  private static func write(_ data: Data, named name: String) throws -> String {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    try data.write(to: url)
    return url.path
  }

  private static func played(_ service: FakeService) throws -> LocalServiceRPCSpeakerArguments {
    let all = service.arguments(of: .playControllerSpeaker)
    #expect(all.count == 1)
    return try JSONDecoder().decode(LocalServiceRPCSpeakerArguments.self, from: all[0])
  }

  @Test
  func playMixesDownResamplesAndSendsEncodedAudio() async throws {
    let service = try FakeService(devices: [Self.remote()], respond: Self.answering())
    let path = try Self.wav(seconds: 1)
    let result = await service.run(["controller", "speaker", "play", token("wii-1"), path])
    #expect(result.code == 0, "\(result.standardError)")
    let audio = try Self.played(service).audio
    #expect(audio.count == 3_000, "one second at 6000 Hz is 3000 ADPCM bytes")
    #expect(audio.contains { $0 != 0 })
  }

  @Test
  func volumeZeroSendsSilence() async throws {
    let service = try FakeService(devices: [Self.remote()], respond: Self.answering())
    let path = try Self.wav(seconds: 1)
    let result = await service.run(
      ["controller", "speaker", "play", token("wii-1"), path, "--volume", "0"]
    )
    #expect(result.code == 0, "\(result.standardError)")
    let silence = PhysicalSpeakerFormat.yamahaADPCM4Bit.encode([Int16](repeating: 0, count: 6_000))
    #expect(try Self.played(service).audio == Data(silence))
  }

  @Test
  func playCutsTheClipAtSpeakerMaxSeconds() async throws {
    let service = try FakeService(devices: [Self.remote(maxSeconds: 1)], respond: Self.answering())
    let path = try Self.wav(seconds: 3, channels: 1)
    let result = await service.run(["controller", "speaker", "play", token("wii-1"), path])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try Self.played(service).audio.count == 3_000)
    #expect(result.standardError.contains("1"))
  }

  @Test
  func aVolumeAboveOneIsRefused() async throws {
    let service = try FakeService(devices: [Self.remote()], respond: Self.answering())
    let path = try Self.wav(seconds: 1)
    let result = await service.run(
      ["controller", "speaker", "play", token("wii-1"), path, "--volume", "2"]
    )
    #expect(result.code == 64)
    #expect(service.arguments(of: .playControllerSpeaker).isEmpty)
  }

  @Test
  func aFileThatIsNotWAVIsRefusedAndNothingIsSent() async throws {
    let service = try FakeService(devices: [Self.remote()], respond: Self.answering())
    let path = try Self.write(Data("not audio".utf8), named: "clip.mp3")
    let result = await service.run(["controller", "speaker", "play", token("wii-1"), path])
    #expect(result.code == 1)
    #expect(result.standardError.contains("error[E2039]"), "\(result.standardError)")
    #expect(service.arguments(of: .playControllerSpeaker).isEmpty)
  }

  @Test
  func aWAVFileThatIsNotPCMIsRefused() async throws {
    let service = try FakeService(devices: [Self.remote()], respond: Self.answering())
    let path = try Self.wav(seconds: 1, format: 3)
    let result = await service.run(["controller", "speaker", "play", token("wii-1"), path])
    #expect(result.code == 1)
    #expect(result.standardError.contains("error[E2039]"), "\(result.standardError)")
    #expect(service.arguments(of: .playControllerSpeaker).isEmpty)
  }

  @Test
  func aControllerWithoutASpeakerFailsWithSpeakerUnavailable() async throws {
    let service = try FakeService(
      devices: [.fixture(id: "pad-1")],
      respond: Self.answering()
    )
    let path = try Self.wav(seconds: 1)
    let play = await service.run(["controller", "speaker", "play", token("pad-1"), path])
    let stop = await service.run(["controller", "speaker", "stop", token("pad-1")])
    for result in [play, stop] {
      #expect(result.code == 1)
      #expect(result.standardError.contains("error[E2038]"), "\(result.standardError)")
    }
    #expect(service.arguments(of: .playControllerSpeaker).isEmpty)
    #expect(service.arguments(of: .stopControllerSpeaker).isEmpty)
  }

  @Test
  func stopSendsTheStopRequestForTheController() async throws {
    let service = try FakeService(devices: [Self.remote()], respond: Self.answering())
    let result = await service.run(["controller", "speaker", "stop", token("wii-1")])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(service.arguments(of: .stopControllerSpeaker).count == 1)
  }

  @Test
  func playCutByStopEndsWithSuccess() async throws {
    let service = try FakeService(
      devices: [Self.remote()],
      respond: Self.answering(.cancelled)
    )
    let path = try Self.wav(seconds: 1)
    let result = await service.run(["controller", "speaker", "play", token("wii-1"), path])
    #expect(result.code == 0, "\(result.standardError)")
  }
}
