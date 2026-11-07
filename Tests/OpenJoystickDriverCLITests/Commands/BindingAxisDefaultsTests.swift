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
      "binding", "set", "Pad", "axis:left-stick-x:positive", "key:key-d", "--invert",
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
      ["binding", "set", "Pad", "axis:left-stick-x:positive", "key:key-d"] + option
    )

    #expect(result.code != 0)
    #expect(library.stored.first?.bindings.isEmpty == true)
  }

  @Test
  func theWiiPointerBindsToMouseMovement() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Wii")])
    let service = try FakeService(devices: [], respond: library.respond)

    let result = await service.run(["binding", "set", "Wii", "axis:pointer-x", "move:x"])

    #expect(result.code == 0, "\(result.standardError)")
    let stored = try #require(library.stored.first?.bindings.first)
    #expect(stored.source == .axis(.pointerX))
    #expect(stored.destination == .mouseMovement(.x))
  }
}
