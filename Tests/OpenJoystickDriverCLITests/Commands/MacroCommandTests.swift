import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct MacroCommandTests {
  private static let combo = [
    "--step", "tap:key:key-a", "--step", "wait:50", "--step", "chord:20:key:key-b+key:key-c",
  ]

  @Test
  func setCreatesMacroAndReplacingItKeepsItsIDAndOptions() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let created = await service.run(
      ["macro", "set", "Pad", "Combo", "--repeat", "3", "--interrupt-on-release", "--json"]
        + Self.combo
    )
    let id = try #require(library.stored.first?.macros.first?.id)
    let replaced = await service.run(
      ["macro", "set", "Pad", "combo", "--step", "tap:key:key-z", "--json"]
    )

    #expect(created.code == 0, "\(created.standardError)")
    #expect(try created.json()["replaced"] as? Bool == false)
    #expect(replaced.code == 0, "\(replaced.standardError)")
    #expect(try replaced.json()["replaced"] as? Bool == true)
    let macros = try #require(library.stored.first?.macros)
    #expect(macros.count == 1)
    #expect(macros.first?.id == id)
    #expect(macros.first?.name == "combo")
    #expect(macros.first?.repeatMode == .count(3))
    #expect(macros.first?.interruptOnRelease == true)
    #expect(macros.first?.steps == [.tap(.keyboard(key: .z, modifiers: []))])
  }

  @Test
  func showAndListPrintStepsInStepForm() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)
    _ = await service.run(["macro", "set", "Pad", "Combo", "--repeat", "while-held"] + Self.combo)

    let show = await service.run(["macro", "show", "Pad", "COMBO", "--json"])
    let list = await service.run(["macro", "list", "Pad", "--json"])
    let human = await service.run(["macro", "list", "Pad"])

    #expect(show.code == 0, "\(show.standardError)")
    let macro = try #require(try show.json()["macro"] as? [String: Any])
    #expect(macro["repeat"] as? String == "while-held")
    #expect(
      macro["steps"] as? [String] == [
        "tap:key:key-a", "wait:50.0", "chord:20.0:key:key-b+key:key-c",
      ]
    )
    #expect(try show.json()["replaced"] == nil)
    let items = try #require(try list.json()["items"] as? [[String: Any]])
    #expect(items.count == 1)
    #expect(human.standardOutput.contains("Combo"))
  }

  @Test
  func removeDeletesMacroAndFailsForMissingOrBoundOne() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)
    _ = await service.run(["macro", "set", "Pad", "Combo"] + Self.combo)
    _ = await service.run(["binding", "set", "Pad", "button:south", "macro:Combo"])

    let bound = await service.run(["macro", "remove", "Pad", "Combo", "-f"])
    _ = await service.run(["binding", "clear", "Pad", "button:south"])
    let missing = await service.run(["macro", "remove", "Pad", "Nope", "-f"])
    let removed = await service.run(["macro", "remove", "Pad", "Combo", "-f", "--json"])

    #expect(bound.code != 0)
    #expect(missing.code == 1)
    #expect(removed.code == 0, "\(removed.standardError)")
    #expect(try removed.details()["removed"] as? String == "Combo")
    #expect(library.stored.first?.macros.isEmpty == true)
  }

  @Test(arguments: [
    ["--step", "jump:key:key-a"], ["--step", "wait:soon"], ["--step", "tap"],
    ["--step", "tap:key:key-a", "--repeat", "often"],
  ])
  func setRejectsBadStepOrRepeatBeforeSaving(arguments: [String]) async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)

    let result = await service.run(["macro", "set", "Pad", "Combo"] + arguments)

    #expect(result.code == 64, "\(result.standardError)")
    #expect(library.stored.first?.macros.isEmpty == true)
  }

  @Test
  func bindingSetTargetsMacroByNameAndKeepsMacrosAcrossBindingChanges() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try FakeService(devices: [], respond: library.respond)
    _ = await service.run(["macro", "set", "Pad", "Combo"] + Self.combo)

    let missing = await service.run(["binding", "set", "Pad", "button:south", "macro:Nope"])
    let saved = await service.run([
      "binding", "set", "Pad", "button:south", "macro:combo", "--json",
    ])
    let list = await service.run(["binding", "list", "Pad"])
    _ = await service.run(["binding", "set", "Pad", "button:east", "key:space"])
    _ = await service.run(["binding", "clear", "Pad", "button:east"])

    #expect(missing.code == 1)
    #expect(missing.standardError.contains("Nope"))
    #expect(saved.code == 0, "\(saved.standardError)")
    let binding = try #require(try saved.json()["binding"] as? [String: Any])
    #expect(binding["target"] as? String == "macro:Combo")
    #expect(list.standardOutput.contains("macro:Combo"))
    let stored = try #require(library.stored.first)
    #expect(stored.macros.count == 1)
    #expect(stored.bindings.map(\.source) == [.button(.south)])
    #expect(stored.bindings.first?.destination == .macro(stored.macros[0].id))
  }
}
