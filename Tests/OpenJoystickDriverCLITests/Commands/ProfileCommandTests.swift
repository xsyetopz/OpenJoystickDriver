import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ProfileCommandTests {
  private static func service(
    _ library: FakeProfileLibrary,
    devices: [ApplicationServiceDeviceDescription] = []
  ) throws -> FakeService { try FakeService(devices: devices, respond: library.respond) }

  @Test
  func listReportsEachProfileAndWhetherItIsActive() async throws {
    let racing = FakeProfileLibrary.profile("Racing")
    let library = FakeProfileLibrary(
      [racing, FakeProfileLibrary.profile("Menus")],
      active: [racing.id]
    )
    let service = try Self.service(library)

    let json = await service.run(["profile", "list", "--json"])
    let plain = await service.run(["profile", "list", "--plain"])

    #expect(json.code == 0, "\(json.standardError)")
    let profiles = try #require(try json.json()["profiles"] as? [[String: Any]])
    #expect(profiles.map { $0["name"] as? String } == ["Racing", "Menus"])
    #expect(profiles.map { $0["active"] as? Bool } == [true, false])
    #expect(profiles.first?["controller"] as? String == "045E:028E")
    #expect(plain.standardOutput.split(separator: "\n").count == 2)
  }

  @Test
  func aNameSelectorIgnoresCaseAndAnAmbiguousNameListsTheIDs() async throws {
    let first = FakeProfileLibrary.profile("Pad")
    let second = FakeProfileLibrary.profile("pad")
    let service = try Self.service(
      FakeProfileLibrary([first, FakeProfileLibrary.profile("Solo"), second])
    )

    let found = await service.run(["profile", "show", "SOLO", "--json"])
    let ambiguous = await service.run(["profile", "show", "PAD"])
    let missing = await service.run(["profile", "show", "Nope"])

    #expect(found.code == 0, "\(found.standardError)")
    #expect((try found.json()["profile"] as? [String: Any])?["name"] as? String == "Solo")
    #expect(ambiguous.code == 1)
    #expect(ambiguous.standardError.contains(first.id.uuidString))
    #expect(ambiguous.standardError.contains(second.id.uuidString))
    #expect(missing.code == 1)
    #expect(missing.standardError.hasPrefix("error[E2012]: "))
    #expect(missing.standardError.contains("Nope"))
  }

  @Test
  func createMakesAPassthroughProfileForTheModel() async throws {
    let library = FakeProfileLibrary([])
    let service = try Self.service(library)

    let result = await service.run([
      "profile", "create", "Racing", "--controller", "054c:0ce6", "--app", "com.example.game",
      "--json",
    ])

    #expect(result.code == 0, "\(result.standardError)")
    let created = try #require(library.stored.first)
    #expect(created.name == "Racing")
    #expect(created.device == RemappingDeviceScope(vendorID: 0x054C, productID: 0x0CE6))
    #expect(created.applicationScope == .application(bundleIdentifier: "com.example.game"))
    #expect(created.outputPolicy.virtualGamepad == .passthrough)
    let profile = try #require(try result.json()["profile"] as? [String: Any])
    #expect(profile["id"] as? String == created.id.uuidString)
    #expect(profile["scope"] as? String == "app:com.example.game")
  }

  @Test
  func duplicateAndRenameKeepTheOriginalContents() async throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let original = FakeProfileLibrary.profile("Pad", bindings: [binding])
    let library = FakeProfileLibrary([original])
    let service = try Self.service(library)

    let duplicate = await service.run(["profile", "duplicate", "Pad", "Pad Copy", "--json"])
    let rename = await service.run(["profile", "rename", original.id.uuidString, "Main", "--json"])

    #expect(duplicate.code == 0, "\(duplicate.standardError)")
    #expect(rename.code == 0, "\(rename.standardError)")
    let stored = library.stored
    #expect(stored.map(\.name) == ["Main", "Pad Copy"])
    #expect(stored[0].id == original.id)
    #expect(stored[1].id != original.id)
    #expect(stored[1].bindings == [binding])
    let update = try #require(service.arguments(of: .updateRemappingProfile).first)
    let arguments = try JSONDecoder().decode(
      ApplicationServiceRemappingProfileUpdateArguments.self,
      from: update
    )
    #expect(arguments.expectedCurrent == original)
  }

  @Test
  func deleteNeedsForceWithoutATerminalAndDryRunChangesNothing() async throws {
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad")])
    let service = try Self.service(library)

    let refused = await service.run(["profile", "delete", "Pad", "--no-input"])
    let dryRun = await service.run(["profile", "delete", "Pad", "-n", "--json"])
    #expect(library.stored.count == 1)
    let deleted = await service.run(["profile", "delete", "Pad", "-f"])

    #expect(refused.code == 64)
    #expect(refused.standardError.contains("--force"))
    #expect(dryRun.code == 0, "\(dryRun.standardError)")
    #expect(try dryRun.json()["dryRun"] as? Bool == true)
    #expect(deleted.code == 0, "\(deleted.standardError)")
    #expect(library.stored.isEmpty)
  }

  @Test
  func recoverActsOnEachIssueAndNeedsForceWithoutATerminal() async throws {
    let damaged = ApplicationServiceRemappingProfileIssue(id: UUID(), message: "damaged")
    let selections = ApplicationServiceRemappingProfileIssue(
      id: UUID(),
      kind: .unusableLibrary,
      message: "selections"
    )
    let library = FakeProfileLibrary([], issues: [damaged, selections])
    let service = try Self.service(library)

    let listed = await service.run(["profile", "list"])
    let refused = await service.run(["profile", "recover", "--no-input"])
    let dryRun = await service.run(["profile", "recover", "-n", "--json"])
    #expect(library.storedIssues.count == 2)
    let recovered = await service.run(["profile", "recover", "-f", "--json"])
    let again = await service.run(["profile", "recover", "-f"])

    #expect(listed.standardError.contains("ojd profile recover"))
    #expect(refused.code == 64)
    #expect(refused.standardError.contains("--force"))
    #expect(dryRun.code == 0, "\(dryRun.standardError)")
    #expect(try dryRun.json()["dryRun"] as? Bool == true)
    #expect(recovered.code == 0, "\(recovered.standardError)")
    let ids = try #require(try recovered.json()["recovered"] as? [[String: Any]]).map {
      $0["id"] as? String
    }
    #expect(ids == [damaged.id.uuidString, selections.id.uuidString])
    #expect(library.storedIssues.isEmpty)
    #expect(service.arguments(of: .deleteDamagedRemappingProfile).count == 1)
    #expect(service.arguments(of: .resetRemappingProfileLibrary).count == 1)
    #expect(again.code == 0, "\(again.standardError)")
    #expect(!again.standardOutput.isEmpty)
    #expect(service.arguments(of: .deleteDamagedRemappingProfile).count == 1)
    #expect(service.arguments(of: .resetRemappingProfileLibrary).count == 1)
  }

  @Test
  func activateRefusesAProfileThatBlocksAllInputUnlessAllowed() async throws {
    let empty = FakeProfileLibrary.profile("Empty", virtualGamepad: .mapped)
    let library = FakeProfileLibrary([empty])
    let service = try Self.service(library)

    let refused = await service.run(["profile", "activate", "Empty"])
    #expect(service.arguments(of: .activateRemappingProfile).isEmpty)
    let allowed = await service.run(["profile", "activate", "Empty", "--allow-empty", "--json"])
    let again = await service.run(["profile", "activate", "Empty", "--allow-empty", "--json"])
    let deactivated = await service.run(["profile", "deactivate", "Empty", "--json"])

    #expect(refused.code == 64)
    #expect(refused.standardError.contains("--allow-empty"))
    #expect(allowed.code == 0, "\(allowed.standardError)")
    #expect(try allowed.json()["changed"] as? Bool == true)
    #expect(try again.json()["changed"] as? Bool == false)
    #expect(deactivated.code == 0, "\(deactivated.standardError)")
    #expect(try deactivated.json()["changed"] as? Bool == true)
    #expect(service.arguments(of: .deactivateRemappingProfileByID).count == 1)
  }

  @Test
  func exportWritesADocumentThatImportReadsBackFromStandardInput() async throws {
    let binding = RemappingBinding(source: .button(.east), destination: .mouseButton(.left))
    let original = FakeProfileLibrary.profile("Pad", bindings: [binding])
    let library = FakeProfileLibrary([original])
    let service = try Self.service(library)

    let export = await service.run(["profile", "export", "Pad"])
    #expect(export.code == 0, "\(export.standardError)")
    let document = Data(export.standardOutput.utf8)
    #expect(try RemappingProfileFileStore.load(from: document) == original)

    let replaced = await RecordStore.$standardInput.withValue(
      { document },
      operation: { await service.run(["profile", "import", "-", "--json"]) }
    )
    let invalid = await RecordStore.$standardInput.withValue(
      { Data("{}".utf8) },
      operation: { await service.run(["profile", "import", "-"]) }
    )

    #expect(replaced.code == 0, "\(replaced.standardError)")
    #expect(try replaced.json()["replaced"] as? Bool == true)
    #expect(invalid.code == 64)
    #expect(invalid.standardError.hasPrefix("error[E2003]: "))
    #expect(service.arguments(of: .importRemappingProfile).count == 1)
  }

  @Test
  func validateChecksAFileWithoutTheService() async throws {
    let profile = FakeProfileLibrary.profile("Pad")
    let document = Data(try RemappingProfileFileStore.encodedJSON(profile).utf8)
    let run = { (data: Data, arguments: [String]) in
      await RecordStore.$standardInput.withValue(
        { data },
        operation: { await CLIRun.run(["profile", "validate", "-"] + arguments) }
      )
    }

    let json = await run(document, ["--json"])
    let plain = await run(document, ["--plain"])
    let human = await run(document, [])
    let invalidJSON = await run(Data(#"{"name":"Pad"}"#.utf8), ["--json"])
    let invalid = await run(Data("{}".utf8), [])

    #expect(json.code == 0, "\(json.standardError)")
    #expect(try json.json()["valid"] as? Bool == true)
    #expect(try json.json()["id"] as? String == profile.id.uuidString)
    #expect(plain.standardOutput == "\(profile.id.uuidString)\tPad\t045E:028E\tglobal\n")
    #expect(human.code == 0)
    #expect(human.standardOutput.contains("Pad"))
    #expect(human.standardOutput.contains("045E:028E"))
    #expect(invalidJSON.code == 1)
    #expect(try invalidJSON.json()["valid"] as? Bool == false)
    #expect(try invalidJSON.json()["problem"] is String)
    #expect(invalid.code == 1)
    #expect(invalid.standardError.hasPrefix("error[E2011]: "))
  }

  @Test
  func getPrintsOneValueAndSetSavesAValidChange() async throws {
    let binding = RemappingBinding(source: .button(.east), destination: .mouseButton(.left))
    let original = FakeProfileLibrary.profile("Pad", bindings: [binding])
    let library = FakeProfileLibrary([original])
    let service = try Self.service(library)

    let name = await service.run(["profile", "get", "Pad", "name"])
    let device = await service.run(["profile", "get", "Pad", "device", "--json"])
    let missing = await service.run(["profile", "get", "Pad", "physicalColor"])
    let behavior = await service.run([
      "profile", "set", "Pad", "bindings.0.behavior", "tap_on_press", "--json",
    ])
    let color = await service.run([
      "profile", "set", "Pad", "physicalColor", #"{"red":1,"green":2,"blue":3}"#,
    ])
    let same = await service.run(["profile", "set", "Pad", "physicalColor.red", "1", "--json"])
    let invalid = await service.run(["profile", "set", "Pad", "physicalColor.red", "256"])
    let noParent = await service.run(["profile", "set", "Pad", "motionTuning.space", "world"])
    let id = await service.run(["profile", "set", "Pad", "id", UUID().uuidString])
    let removed = await service.run(["profile", "set", "Pad", "physicalColor", "null"])

    #expect(name.code == 0, "\(name.standardError)")
    #expect(name.standardOutput == "Pad\n")
    let value = try #require(try device.json()["value"] as? [String: Any])
    #expect(value["vendorID"] as? Int == 0x045E)
    #expect(missing.code == 1)
    #expect(behavior.code == 0, "\(behavior.standardError)")
    #expect(try behavior.json()["changed"] as? Bool == true)
    #expect(color.code == 0, "\(color.standardError)")
    #expect(try same.json()["changed"] as? Bool == false)
    #expect(invalid.code == 64)
    #expect(noParent.code == 64)
    #expect(id.code == 64)
    #expect(removed.code == 0, "\(removed.standardError)")
    let saved = try #require(library.stored.first)
    #expect(saved.id == original.id)
    #expect(saved.bindings.first?.behavior == .tapOnPress)
    #expect(saved.physicalColor == nil)
    #expect(service.arguments(of: .updateRemappingProfile).count == 3)
  }

  @Test
  func profileValueAddsAndRemovesArrayItemsAndReadsJSONOrText() {
    let tree = ProfileValue.object(["items": .array([.integer(1), .integer(2)])])
    let key = { (text: String) in ProfileKey(argument: text)?.components[...] ?? [] }

    #expect(
      tree.setting(.integer(3), at: key("items.2"))
        == .object(["items": .array([.integer(1), .integer(2), .integer(3)])])
    )
    #expect(tree.setting(.null, at: key("items.0")) == .object(["items": .array([.integer(2)])]))
    #expect(tree.setting(.integer(3), at: key("items.3")) == nil)
    #expect(tree.setting(.integer(3), at: key("other.0")) == nil)
    #expect(tree.value(at: key("items.1")) == .integer(2))
    #expect(ProfileKey(argument: "items..1") == nil)
    #expect(ProfileValue(argument: "0.5") == .number(0.5))
    #expect(ProfileValue(argument: "true") == .bool(true))
    #expect(ProfileValue(argument: "space") == .string("space"))
    #expect(ProfileValue(argument: #""true""#) == .string("true"))
    #expect(ProfileValue.array([.integer(1), .string("a")]).text == #"[1,"a"]"#)
  }

  @Test
  func editReturnsTheSavedProfileAndRejectsAChangedID() throws {
    let original = FakeProfileLibrary.profile("Pad")
    let renamed = ProfileEditor.$open.withValue(
      { url in
        let text = try String(contentsOf: url, encoding: .utf8)
        try text.replacingOccurrences(of: "\"Pad\"", with: "\"Main\"").write(
          to: url,
          atomically: true,
          encoding: .utf8
        )
      },
      operation: { Result { try ProfileEditCommand.edit(original) } }
    )
    let reidentified = ProfileEditor.$open.withValue(
      { url in
        let copy = original.copy(id: UUID(), name: "Pad")
        try RemappingProfileFileStore.write(copy, to: url)
      },
      operation: { Result { try ProfileEditCommand.edit(original) } }
    )

    #expect(try renamed.get().name == "Main")
    #expect(try renamed.get().id == original.id)
    #expect(throws: CLIFailure.self) { try reidentified.get() }
    #expect(ProfileEditor.command(environment: ["EDITOR": "nano"]) == "nano")
    #expect(
      ProfileEditor.command(environment: ["VISUAL": "code -w", "EDITOR": "nano"]) == "code -w"
    )
    #expect(ProfileEditor.command(environment: [:]) == "vi")
  }

  @Test
  func editNeedsATerminal() async throws {
    let service = try Self.service(FakeProfileLibrary([FakeProfileLibrary.profile("Pad")]))
    let result = await service.run(["profile", "edit", "Pad", "--no-input"])
    #expect(result.code == 64)
    #expect(service.arguments(of: .getRemappingSnapshot).isEmpty)
  }
}
