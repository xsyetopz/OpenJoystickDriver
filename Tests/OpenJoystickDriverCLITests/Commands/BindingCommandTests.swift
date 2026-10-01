import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct BindingCommandTests {
  @Test
  func setAddsABindingAndReplacingItKeepsItsID() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let added = await service.run(["binding", "set", "Pad", "button:south", "key:space", "--json"])
    let firstID = try #require(library.stored.first?.bindings.first?.id)
    let replaced = await service.run([
      "binding", "set", "Pad", "button:south", "mouse:left", "--behavior", "pulse", "--pulse-ms",
      "250", "--json",
    ])

    #expect(added.code == 0, "\(added.standardError)")
    #expect(try added.json()["replaced"] as? Bool == false)
    #expect(replaced.code == 0, "\(replaced.standardError)")
    #expect(try replaced.json()["replaced"] as? Bool == true)
    let bindings = try #require(library.stored.first?.bindings)
    #expect(bindings.count == 1)
    #expect(bindings.first?.id == firstID)
    #expect(bindings.first?.destination == .mouseButton(.left))
    #expect(bindings.first?.behavior == .pulse)
    #expect(bindings.first?.pulseDurationMs == 250)
    let binding = try #require(try replaced.json()["binding"] as? [String: Any])
    #expect(binding["source"] as? String == "button:south")
    #expect(binding["target"] as? String == "mouse:left")
  }

  @Test
  func setBuildsAxisTuningTurboAndAlternateTargets() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let axis = await service.run([
      "binding", "set", "Pad", "axis:left_stick_x:positive", "key:d", "--deadzone", "0.2",
      "--invert",
    ])
    let turbo = await service.run([
      "binding", "set", "Pad", "button:west", "key:j", "--turbo-rate", "10", "--turbo-duty", "0.5",
    ])
    let alternates = await service.run([
      "binding", "set", "Pad", "button:north", "key:k", "--long-hold", "500:key:b", "--double-tap",
      "300:key:c",
    ])

    #expect(axis.code == 0, "\(axis.standardError)")
    #expect(turbo.code == 0, "\(turbo.standardError)")
    #expect(alternates.code == 0, "\(alternates.standardError)")
    let bindings = try #require(library.stored.first?.bindings)
    #expect(bindings.count == 3)
    #expect(bindings.first?.axisTuning?.deadzone == 0.2)
    #expect(bindings.first?.axisTuning?.inverted == true)
    #expect(bindings.dropFirst().first?.turbo == RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5))
    #expect(bindings.last?.longHold?.durationMs == 500)
    #expect(bindings.last?.longHold?.destination == .keyboard(key: .b, modifiers: []))
    #expect(bindings.last?.doubleTap?.windowMs == 300)
  }

  @Test
  func listPrintsEachBinding() async throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad", bindings: [binding])])
    let service = try FakeService(devices: [], respond: library.respond)

    let json = await service.run(["binding", "list", "Pad", "--json"])
    let human = await service.run(["binding", "list", "Pad"])

    #expect(json.code == 0, "\(json.standardError)")
    let bindings = try #require(try json.json()["bindings"] as? [[String: Any]])
    #expect(bindings.first?["id"] as? String == binding.id.uuidString)
    #expect(human.standardOutput == "button:south -> key:space\n")
  }

  @Test
  func clearRemovesNamedSourcesAndFailsForAnUnboundOne() async throws {
    let bindings = [
      RemappingBinding(source: .button(.south), destination: .keyboard(key: .space, modifiers: [])),
      RemappingBinding(source: .button(.east), destination: .keyboard(key: .escape, modifiers: [])),
    ]
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad", bindings: bindings)])
    let service = try FakeService(devices: [], respond: library.respond)

    let missing = await service.run(["binding", "clear", "Pad", "button:west"])
    let cleared = await service.run(["binding", "clear", "Pad", "button:south", "--json"])

    #expect(missing.code == 1)
    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(try cleared.json()["removed"] as? [String] == ["button:south"])
    #expect(library.stored.first?.bindings.map(\.source) == [.button(.east)])
  }

  @Test
  func clearAllNeedsForceAndKeepsTheOutputPolicy() async throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let library = FakeProfileLibrary([
      FakeProfileLibrary.profile("Pad", virtualGamepad: .disabled, bindings: [binding])
    ])
    let service = try FakeService(devices: [], respond: library.respond)

    let refused = await service.run(["binding", "clear", "Pad", "--all", "--no-input"])
    let dryRun = await service.run(["binding", "clear", "Pad", "--all", "-n", "--json"])
    #expect(library.stored.first?.bindings.count == 1)
    let cleared = await service.run(["binding", "clear", "Pad", "--all", "-f"])

    #expect(refused.code == 64)
    #expect(try dryRun.json()["removed"] as? [String] == ["button:south"])
    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(library.stored.first?.bindings.isEmpty == true)
    #expect(library.stored.first?.outputPolicy.virtualGamepad == .disabled)
  }

  @Test(arguments: [
    (RemappingVirtualGamepadPolicy.mapped, true, true), (.mapped, false, false),
    (.passthrough, true, false),
  ])
  func clearAllWarnsWhenAnActiveProfileNowBlocksAConnectedController(
    policy: RemappingVirtualGamepadPolicy,
    connected: Bool,
    warns: Bool
  ) async throws {
    let binding = RemappingBinding(source: .button(.south), destination: .gamepadButton(.south))
    let profile = FakeProfileLibrary.profile("Pad", virtualGamepad: policy, bindings: [binding])
    let library = FakeProfileLibrary(
      [profile],
      active: [profile.id],
      connected: connected ? [FakeService.device(id: "pad-1")] : []
    )
    let service = try FakeService(devices: [], respond: library.respond)

    let cleared = await service.run(["binding", "clear", "Pad", "--all", "-f", "--json"])

    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(try cleared.json()["all"] as? Bool == true)
    #expect(cleared.standardError.contains("now blocks all of its input") == warns)
    #expect(cleared.standardError.contains("'ojd profile deactivate'") == warns)
  }
}
