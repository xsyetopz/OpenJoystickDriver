import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct BindingAxisDefaultsTests {
  @Test
  func anAxisBindingWithoutTuningOptionsUsesTheKitDefaults() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let result = await service.run([
      "binding", "set", "Pad", "axis:left_stick_x:positive", "key:d", "--invert",
    ])

    #expect(result.code == 0, "\(result.standardError)")
    let tuning = try #require(library.stored.first?.bindings.first?.axisTuning)
    #expect(tuning.deadzone == RemappingAxisTuning.defaultDeadzone)
    #expect(tuning.gain == RemappingAxisTuning.defaultGain)
    #expect(
      tuning.digitalActivationThreshold
        == RemappingAxisTuning.defaultDigitalActivationThreshold
    )
  }

  @Test(arguments: [
    ["--deadzone", "0.96"], ["--gain", "0.05"], ["--digital-threshold", "0"],
  ])
  func aValueOutsideTheKitRangeIsRejected(option: [String]) async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let result = await service.run(
      ["binding", "set", "Pad", "axis:left_stick_x:positive", "key:d"] + option
    )

    #expect(result.code != 0)
    #expect(library.stored.first?.bindings.isEmpty == true)
  }
}
