import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct VirtualCommandTests {
  @Test
  func setSendsProfileForSelectedControllerAndPrintsResult() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ]) { method, _ in
      method == .setVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: .generic,
            live: .generic,
            source: .override,
            failure: nil
          )
        ) : nil
    }
    let result = await service.run(["virtual", "set", "generic", token("pad-1"), "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["controller"] as? String == token("pad-1"))
    #expect(json["live"] as? String == "Generic")
    #expect(json["source"] as? String == "override")
    let arguments = try #require(service.arguments(of: .setVirtualHIDProfileOverride).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCVirtualHIDProfileOverrideArguments.self,
      from: arguments
    )
    #expect(sent.profile == "Generic")
    #expect(sent.controller == .session(.fixture("pad-1")))
  }

  @Test
  func rejectedProfileFailsWithExitOne() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ]) { method, _ in
      method == .setVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: .generic,
            live: nil,
            source: .automatic,
            failure: .activationFailed(detail: "no fit")
          )
        ) : nil
    }
    let result = await service.run(["virtual", "set", "generic", token("pad-1")])
    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("no fit"))
  }

  /// With virtual output off, the service stores the choice and reports `output-disabled`.
  @Test(arguments: [
    ["virtual", "set", "generic", token("pad-1")], ["virtual", "reset", token("pad-1")],
  ])
  func choiceStoredWhileVirtualOutputIsOffSucceeds(arguments: [String]) async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ]) { method, _ in
      method == .setVirtualHIDProfileOverride || method == .resetVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: arguments[1] == "set" ? .generic : nil,
            live: nil,
            source: .override,
            failure: .outputDisabled
          )
        ) : nil
    }
    let result = await service.run(arguments)
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardError.contains("Test Pad"))
  }

  @Test
  func resetAllWithForceClearsEveryChoice() async throws {
    let service = try FakeService(devices: []) { method, _ in
      method == .resetSettings ? encoded(true) : nil
    }
    let result = await service.run(["virtual", "reset", "--all", "--force", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.details()["reset"] as? String == "All")
    #expect(service.arguments(of: .resetSettings).count == 1)
  }

  @Test
  func resetAllWithoutPromptOrForceIsUsageErrorAndChangesNothing() async throws {
    let service = try FakeService(devices: []) { _, _ in encoded(true) }
    let result = await service.run(["virtual", "reset", "--all", "--no-input"])
    #expect(result.code == 64)
    #expect(result.standardError.contains("--force"))
    #expect(service.arguments(of: .resetSettings).isEmpty)
  }

  @Test(arguments: [
    ["virtual", "reset", "--all", "--dry-run"], ["virtual", "reset", token("pad-1"), "-n"],
  ])
  func dryRunDescribesResetAndChangesNothing(arguments: [String]) async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ]) { _, _ in
      encoded(true)
    }
    let result = await service.run(arguments)
    #expect(result.code == 0, "\(result.standardError)")
    #expect(!result.standardOutput.isEmpty)
    #expect(service.arguments(of: .resetSettings).isEmpty)
    #expect(service.arguments(of: .resetVirtualHIDProfileOverride).isEmpty)
  }

  @Test(arguments: [
    ["virtual", "reset"], ["virtual", "reset", token("pad-1"), "--all"],
    ["virtual", "set", "unknown", token("pad-1")],
  ])
  func missingOrInvalidTargetExitsSixtyFour(arguments: [String]) async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])
    let result = await service.run(arguments)
    #expect(result.code == 64, "\(arguments)")
    #expect(service.arguments(of: .getStatus).isEmpty)
  }

  @Test
  func showListsEachControllersProfileAndChoices() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])
    let result = await service.run(["virtual", "show", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    let controllers = try #require(json["controllers"] as? [[String: Any]])
    #expect(controllers.map { $0["id"] as? String } == [token("pad-1")])
    #expect(json["profiles"] as? [String] == VirtualHIDProfileID.allCases.map(\.rawValue))
    for controller in controllers {
      // A controller carries the mapping of its live persona, and none without one.
      let profile = controller["profile"] as? String
      let sdl = controller["sdl"] as? [String: Any]
      #expect((sdl != nil) == (profile != nil), "\(controller)")
      #expect((controller["w3c"] != nil) == (profile != nil), "\(controller)")
      if let profile, let id = VirtualHIDProfileID(rawValue: profile) {
        #expect(sdl?["mapping"] as? String == (try id.gamepadMapping()).sdlMapping)
      }
    }
  }

  @Test
  func showListsChoicesInHumanOutputAsVirtualSetTakesThem() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])
    let result = await service.run(["virtual", "show"])
    #expect(result.code == 0, "\(result.standardError)")
    let choices = VirtualHIDProfileID.allCases.map { CommandLineName.kebab($0.rawValue) }
    #expect(result.standardOutput.contains(choices.joined(separator: ", ")))
  }

  @Test
  func exportMappingPrintsOneSDLLinePerPersonaByDefault() async throws {
    let service = try FakeService(devices: [])
    let result = await service.run(["virtual", "export-mapping"])
    #expect(result.code == 0, "\(result.standardError)")
    let lines = result.standardOutput.split(separator: "\n").map(String.init)
      .filter { !$0.hasPrefix("#") }
    #expect(lines == (try VirtualHIDProfileID.allCases.map { try $0.gamepadMapping().sdlMapping }))
    #expect(
      lines.contains {
        $0.hasPrefix("03000000091200004f4a000008040000,") && $0.contains(",a:b0,b:b1,x:b2,y:b3,")
      }
    )
  }

  @Test
  func exportMappingJSONCarriesSDLMappingOfEachPersona() async throws {
    let service = try FakeService(devices: [])
    let result = await service.run(["virtual", "export-mapping", "--format", "sdl", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["format"] as? String == "SDL")
    let mappings = try #require(json["mappings"] as? [[String: Any]])
    #expect(
      mappings.map { $0["profile"] as? String } == VirtualHIDProfileID.allCases.map(\.rawValue)
    )
    for entry in mappings {
      let sdl = try #require(entry["sdl"] as? [String: Any])
      let mapping = try #require(sdl["mapping"] as? String)
      #expect(mapping.hasPrefix("\(try #require(sdl["guid"] as? String)),"))
      #expect(entry["w3c"] == nil)
    }
    let generic = try #require(mappings.first { $0["profile"] as? String == "Generic" })
    let sdl = try #require(generic["sdl"] as? [String: Any])
    #expect(sdl["guid"] as? String == "03000000091200004f4a000008040000")
  }

  @Test
  func exportMappingJSONCarriesW3CDescriptionOfOnePersona() async throws {
    let service = try FakeService(devices: [])
    let result = await service.run([
      "virtual", "export-mapping", "generic", "--format", "w3c", "--json",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    let mappings = try #require(json["mappings"] as? [[String: Any]])
    #expect(mappings.count == 1)
    let w3c = try #require(mappings.first?["w3c"] as? [String: Any])
    #expect(mappings.first?["sdl"] == nil)
    let buttons = try #require(w3c["buttons"] as? [[String: Any]])
    let axes = try #require(w3c["axes"] as? [[String: Any]])
    #expect(buttons.first?["control"] as? String == "South")
    #expect(buttons.first?["index"] as? Int == 0)
    #expect(
      axes.map { $0["control"] as? String } == [
        "LeftStickX", "LeftStickY", "RightStickX", "RightStickY",
      ]
    )
  }

  @Test
  func exportMappingRejectsUnknownProfileOrFormatWithExitSixtyFour() async throws {
    let service = try FakeService(devices: [])
    for arguments in [
      ["virtual", "export-mapping", "nope"], ["virtual", "export-mapping", "--format", "x"],
    ] {
      let result = await service.run(arguments)
      #expect(result.code == 64, "\(arguments)")
    }
  }

  @Test
  func exportMappingNotesOnlyProfileThatNeedsSDLHints() async throws {
    let service = try FakeService(devices: [])
    let human = await service.run(["virtual", "export-mapping"])
    let lines = human.standardOutput.split(separator: "\n").map(String.init)
    #expect(
      lines.filter { $0.hasPrefix("#") } == [
        "# Note: game-controller-compatible does not work with SDL's default hints."
      ]
    )
    #expect(lines.count == VirtualHIDProfileID.allCases.count + 1)

    let json = try await service.run(["virtual", "export-mapping", "--json"]).json()
    let mappings = try #require(json["mappings"] as? [[String: Any]])
    let works = try mappings.map { entry in
      try #require((entry["sdl"] as? [String: Any])?["worksWithDefaultSDLHints"] as? Bool)
    }
    #expect(works == VirtualHIDProfileID.allCases.map(\.worksWithDefaultSDLHints))
    #expect(works == [true, true, false])
  }

  @Test
  func showStatesInHumanAndJSONOutputThatSDLNeedsNoHints() async throws {
    var device = ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    device.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .sdlCompatible,
      source: .override,
      override: .sdlCompatible,
      unavailable: false
    )
    let service = try FakeService(devices: [device])
    let human = await service.run(["virtual", "show"])
    #expect(human.code == 0, "\(human.standardError)")
    #expect(!human.standardOutput.contains(sdlHintsNote("SDLCompatible")))

    let json = try await service.run(["virtual", "show", "--json"]).json()
    let controllers = try #require(json["controllers"] as? [[String: Any]])
    let sdl = try #require(controllers.first?["sdl"] as? [String: Any])
    #expect(sdl["worksWithDefaultSDLHints"] as? Bool == true)

    var generic = ApplicationServiceDeviceDescription.fixture(id: "pad-2")
    generic.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .generic,
      source: .override,
      override: .generic,
      unavailable: false
    )
    let other = try FakeService(devices: [generic])
    let quiet = await other.run(["virtual", "show"])
    #expect(!quiet.standardOutput.contains(sdlHintsNote("Generic")))
    let quietJSON = try await other.run(["virtual", "show", "--json"]).json()
    let quietSDL = try #require(
      (quietJSON["controllers"] as? [[String: Any]])?.first?["sdl"] as? [String: Any]
    )
    #expect(quietSDL["worksWithDefaultSDLHints"] as? Bool == true)
  }
}
