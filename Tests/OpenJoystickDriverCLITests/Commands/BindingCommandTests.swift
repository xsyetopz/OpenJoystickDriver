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
  func replacingABindingKeepsItsRemark() async throws {
    let noted = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: []),
      remark: "Jump"
    )
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad", bindings: [noted])])
    let service = try FakeService(devices: [], respond: library.respond)

    let replaced = await service.run(["binding", "set", "Pad", "button:south", "mouse:left"])

    #expect(replaced.code == 0, "\(replaced.standardError)")
    #expect(library.stored.first?.bindings.first?.remark == "Jump")
  }

  @Test
  func setStoresASpokenPhraseWithItsVoiceAndRejectsAVoiceOnAnotherTarget() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let spoken = await service.run([
      "binding", "set", "Pad", "button:south", "speak:Hello: there", "--voice", "com.example.voice",
      "--json",
    ])
    let stray = await service.run([
      "binding", "set", "Pad", "button:north", "key:space", "--voice", "com.example.voice",
    ])

    #expect(spoken.code == 0, "\(spoken.standardError)")
    let binding = try #require(library.stored.first?.bindings.first)
    #expect(binding.destination == .speak(text: "Hello: there", voice: "com.example.voice"))
    let shown = try #require(try spoken.json()["binding"] as? [String: Any])
    #expect(shown["target"] as? String == "speak:Hello: there")
    #expect(stray.code != 0)
    #expect(library.stored.first?.bindings.count == 1)
  }

  @Test
  func setBuildsAxisTuningTurboAndAlternateTargets() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let axis = await service.run([
      "binding", "set", "Pad", "axis:left-stick-x:positive", "key:key-d", "--deadzone", "0.2",
      "--invert",
    ])
    let turbo = await service.run([
      "binding", "set", "Pad", "button:west", "key:key-j", "--turbo-rate", "10", "--turbo-duty",
      "0.5",
    ])
    let alternates = await service.run([
      "binding", "set", "Pad", "button:north", "key:key-k", "--long-hold", "500:key:key-b",
      "--multi-tap", "3:300:key:key-c", "--multi-tap", "2:200:key:key-d",
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
    #expect(bindings.last?.multiTap.map(\.count) == [3, 2])
    #expect(bindings.last?.multiTap.first?.windowMs == 300)
  }

  @Test
  func setBuildsTurboDelayAndCapAndRejectsThemWithoutRateAndDuty() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let turbo = await service.run([
      "binding", "set", "Pad", "button:west", "key:key-j", "--turbo-rate", "10", "--turbo-duty",
      "0.5", "--turbo-delay", "400", "--turbo-max", "20",
    ])
    let alone = await service.run([
      "binding", "set", "Pad", "button:east", "key:key-k", "--turbo-delay", "400",
    ])

    #expect(turbo.code == 0, "\(turbo.standardError)")
    #expect(
      library.stored.first?.bindings.first?.turbo
        == RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: 400, maxRepeats: 20)
    )
    #expect(alone.code != 0)
    #expect(library.stored.first?.bindings.count == 1)
  }

  @Test
  func setRejectsTurboDelayWithoutRateAndDuty() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let result = await service.run([
      "binding", "set", "Pad", "button:south", "key:key-a", "--turbo-delay", "400",
    ])

    #expect(result.code != 0)
    #expect(result.standardError.contains("--turbo-delay"))
    #expect(library.stored.first?.bindings.isEmpty == true)
  }

  @Test
  func setRejectsDoubleTapAndAMalformedMultiTap() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let old = await service.run([
      "binding", "set", "Pad", "button:south", "key:key-a", "--double-tap", "300:key:key-b",
    ])
    let malformed = await service.run([
      "binding", "set", "Pad", "button:south", "key:key-a", "--multi-tap", "300:key:key-b",
    ])

    #expect(old.code != 0)
    #expect(old.standardError.contains("--double-tap"))
    #expect(malformed.code != 0)
    #expect(library.stored.first?.bindings.isEmpty == true)
  }

  @Test
  func listShowsTurboDelayAndMultiTapWithTheAddedWait() async throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: []),
      turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.5, initialDelayMs: 400, maxRepeats: 20),
      multiTap: [
        RemappingMultiTap(count: 3, windowMs: 300, destination: .keyboard(key: .b, modifiers: [])),
        RemappingMultiTap(count: 2, windowMs: 200, destination: .keyboard(key: .a, modifiers: [])),
      ]
    )
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad", bindings: [binding])])
    let service = try FakeService(devices: [], respond: library.respond)

    let human = await service.run(["binding", "list", "Pad"])

    #expect(human.standardOutput.contains("delay:400.0ms max:20"))
    #expect(human.standardOutput.contains("multi-tap:2x200.0ms -> key:key-a"))
    #expect(human.standardOutput.contains("multi-tap:3x300.0ms -> key:key-b  tap-delay:300.0ms"))
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
    let bindings = try #require(try json.json()["items"] as? [[String: Any]])
    #expect(bindings.first?["id"] as? String == binding.id.uuidString)
    #expect((bindings.first?["profile"] as? [String: Any])?["name"] as? String == "Pad")
    #expect(bindings.first?["kind"] == nil)
    #expect((try json.json()["metadata"] as? [String: Any])?.isEmpty == true)
    #expect(human.standardOutput == "button:south -> key:space\n")
  }

  @Test
  func listSpellsABehaviorInKebabCaseForPlainAndAsTheDocumentValueForJSON() async throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: []),
      behavior: .tapOnPress
    )
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad", bindings: [binding])])
    let service = try FakeService(devices: [], respond: library.respond)

    let plain = await service.run(["binding", "list", "Pad", "--plain"])
    let json = await service.run(["binding", "list", "Pad", "--json"])

    #expect(plain.code == 0, "\(plain.standardError)")
    #expect(plain.standardOutput.contains("tap-on-press"))
    #expect(!plain.standardOutput.contains("TapOnPress"))
    let items = try #require(try json.json()["items"] as? [[String: Any]])
    #expect(items.first?["behavior"] as? String == "TapOnPress")
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
    #expect(try cleared.details()["removed"] as? [String] == ["button:south"])
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
    let humanDryRun = await service.run(["binding", "clear", "Pad", "--all", "-n"])
    #expect(library.stored.first?.bindings.count == 1)
    let cleared = await service.run(["binding", "clear", "Pad", "--all", "-f"])

    #expect(refused.code == 64)
    #expect(try dryRun.details()["removed"] as? [String] == ["button:south"])
    #expect(humanDryRun.standardOutput.contains("Pad"))
    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(cleared.standardError.contains("Pad"))
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
      connected: connected ? [ApplicationServiceDeviceDescription.fixture(id: "pad-1")] : []
    )
    let service = try FakeService(devices: [], respond: library.respond)

    let cleared = await service.run(["binding", "clear", "Pad", "--all", "-f", "--json"])

    #expect(cleared.code == 0, "\(cleared.standardError)")
    #expect(try cleared.details()["all"] as? Bool == true)
    #expect(cleared.standardError.contains("ojd profile deactivate") == warns)
    #expect(cleared.standardError.isEmpty == !warns)
  }
}
