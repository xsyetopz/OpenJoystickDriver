import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

extension VirtualCommandTests {
  /// A controller with `outputs` that `profile` serves by override.
  private static func pad(
    _ profile: VirtualHIDProfileID,
    outputs: PhysicalControllerOutputCapabilities
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription.fixture(id: "pad-1", outputs: outputs)
    device.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: profile,
      source: .override,
      override: profile,
      unavailable: false
    )
    return device
  }

  @Test
  func onlyGenericCarriesNoRumble() {
    #expect(VirtualHIDProfileID.allCases.filter { !$0.carriesRumble } == [.generic])
  }

  @Test(arguments: [
    (VirtualHIDProfileID.generic, PhysicalControllerOutputCapabilities.dualMainRumble, true),
    (.generic, .none, false), (.sdlCompatible, .dualMainRumble, false),
    (.gameControllerCompatible, .dualMainRumble, false),
  ])
  func showStatesWhenGamesCannotRumbleController(
    profile: VirtualHIDProfileID,
    outputs: PhysicalControllerOutputCapabilities,
    lost: Bool
  ) async throws {
    let service = try FakeService(devices: [Self.pad(profile, outputs: outputs)])

    let human = await service.run(["virtual", "show"])
    let json = try await service.run(["virtual", "show", "--json"]).json()
    let detail = try await service.run(["controller", "show", token("pad-1"), "--json"]).json()
    let detailHuman = await service.run(["controller", "show", token("pad-1")])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.contains(noGameRumbleNote(profile)) == lost)
    #expect(detailHuman.standardOutput.contains(noGameRumbleNote(profile)) == lost)
    let controller = try #require((json["controllers"] as? [[String: Any]])?.first)
    #expect(controller["gameRumbleUnavailable"] as? Bool == lost)
    let virtual = try #require(detail["virtual"] as? [String: Any])
    #expect(virtual["gameRumbleUnavailable"] as? Bool == lost)
  }

  @Test
  func noteNamesThePersonaAndEachPersonaThatCarriesRumble() {
    let note = noGameRumbleNote(.generic)

    #expect(note.contains("generic"))
    #expect(note.contains("sdl-compatible, game-controller-compatible"))
  }

  @Test(arguments: [(PhysicalControllerOutputCapabilities.dualMainRumble, true), (.none, false)])
  func setToGenericStatesWhenGamesCannotRumbleController(
    outputs: PhysicalControllerOutputCapabilities,
    lost: Bool
  ) async throws {
    let device = ApplicationServiceDeviceDescription.fixture(id: "pad-1", outputs: outputs)
    let service = try FakeService(devices: [device]) { method, _ in
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

    let result = await service.run(["virtual", "set", "generic", token("pad-1")])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains(noGameRumbleNote(.generic)) == lost)
  }
}
