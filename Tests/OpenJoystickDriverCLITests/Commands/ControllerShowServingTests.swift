import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// Task 24.5: `ojd controller show` prints the serving route and persona `ServingPolicy` decides.
struct ControllerShowServingTests {
  /// The fixture as the service describes it; a controller with output off reports why.
  private static func device(_ fixture: ServingFixture) -> ApplicationServiceDeviceDescription {
    var device = fixture.device
    if !fixture.outputEnabled {
      device.publication = ApplicationServicePublicationStatus.notPublished(.outputDisabled)
    }
    return device
  }

  private static func show(_ fixture: ServingFixture, _ options: [String]) async throws -> CLIRun {
    let service = try FakeService(devices: [device(fixture)])
    return await service.run(["controller", "show", token("serving-fixture")] + options)
  }

  @Test(arguments: ServingFixture.all)
  func jsonCarriesTheRoutePersonaAndReasonOfThePolicy(_ fixture: ServingFixture) async throws {
    let decision = ServingPolicy.decision(ServingInput(Self.device(fixture)))
    let result = try await Self.show(fixture, ["--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let serving = try #require(try result.json()["serving"] as? [String: Any])
    #expect(serving["route"] as? String == decision.route.id, "\(fixture.name)")
    #expect(serving["persona"] as? String == decision.selection?.profileID.rawValue)
    #expect(serving["reason"] as? String == decision.route.disabledReason?.rawValue)
    // The route is the one the fixture names.
    #expect(decision.route.id == fixture.route.id, "\(fixture.name)")
  }

  @Test(arguments: ServingFixture.all)
  func plainAndHumanOutputNameTheRoute(_ fixture: ServingFixture) async throws {
    let decision = ServingPolicy.decision(ServingInput(Self.device(fixture)))
    let plain = try await Self.show(fixture, ["--plain"])
    let reason = decision.route.disabledReason.map { CommandLineName.kebab($0.rawValue) } ?? ""
    #expect(
      plain.standardOutput.contains(
        "serving-route\t\(CommandLineName.kebab(decision.route.id))\t\(reason)\n"
      ),
      "\(fixture.name)"
    )
    let persona = decision.selection.map { CommandLineName.kebab($0.profileID.rawValue) } ?? ""
    #expect(plain.standardOutput.contains("persona\t\(persona)\n"), "\(fixture.name)")
    let human = try await Self.show(fixture, [])
    #expect(
      human.standardOutput.contains(CommandLineName.kebab(decision.route.id)),
      "\(fixture.name)"
    )
  }

  @Test
  func humanRowsHaveDistinctLabels() async throws {
    var device = ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    device.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: .sdlCompatible,
      source: .override,
      override: .sdlCompatible,
      unavailable: false
    )
    let service = try FakeService(devices: [device])
    let human = await service.run(["controller", "show", token("pad-1")])
    #expect(human.code == 0, "\(human.standardError)")
    let labels = human.standardOutput.split(separator: "\n").compactMap { line in
      line.components(separatedBy: "  ").first.map {
        $0.trimmingCharacters(in: .whitespaces)
      }
    }.filter { !$0.isEmpty }
    #expect(labels.contains(CLILocalized.text("cli.controller.show.labelVirtual")))
    #expect(Set(labels).count == labels.count, "\(labels)")
  }

  @Test
  func everyRouteAppearsAcrossTheFixtures() {
    let ids = Set(ServingFixture.all.map(\.route.id))
    #expect(ids == ["NativePassThrough", "VirtualHID", "ExtensionOwned", "OutputDisabled"])
  }
}
