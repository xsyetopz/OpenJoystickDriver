import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct StatusVirtualDeviceTests {
  /// The backend status the service reported on macOS 27 for a controller whose session ended.
  private static let endedStatus = VirtualOutputBackendStatus.backend(
    "automatic, publication: controller=LogicalControllerID(VID:0x3537 PID:0x1010 serial=present"
      + " loc=18022400 if=0), session=1, publication=1, target=SDLCompatible,"
      + " last-attempted=88598501741541, last-completed=88598501923333, status=ended,"
      + " recovery=idle"
  )

  private static func device(
    _ id: String,
    name: String,
    publication: ApplicationServicePublicationStatus
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription.fixture(id: id, name: name)
    device.publication = publication
    return device
  }

  private static func runStatus(
    _ arguments: [String],
    devices: [ApplicationServiceDeviceDescription],
    virtualStatus: VirtualOutputBackendStatus
  ) async throws -> CLIRun {
    let service = try FakeService(devices: devices, virtualStatus: virtualStatus)
    let records = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    return await RecordStore.$directory.withValue(records) {
      await StatusCommand.$extensionProbe.withValue(
        { ExtensionStatus(bundle: .present, registration: .absent) },
        operation: { await service.run(["status"] + arguments) }
      )
    }
  }

  private static func virtualLine(_ run: CLIRun) throws -> String {
    let label = CLILocalized.text("cli.status.group.labelVirtualDevice")
    return try #require(run.standardOutput.split(separator: "\n").first { $0.hasPrefix(label) })
      .dropFirst(label.count).trimmingCharacters(in: .whitespaces)
  }

  @Test
  func humanStatusNamesPublishedControllersAndNoEndedSession() async throws {
    let devices = [
      Self.device("pad-1", name: "Razer Wolverine", publication: .published(target: .generic)),
      Self.device("pad-2", name: "DualShock 3", publication: .notPublished(.noInputYet)),
    ]
    let human = try await Self.runStatus([], devices: devices, virtualStatus: Self.endedStatus)
    #expect(human.code == 0, "\(human.standardError)")
    #expect(
      try Self.virtualLine(human)
        == CLILocalized.format("cli.status.group.virtualPublished", "Razer Wolverine")
    )
    #expect(!human.standardOutput.contains("LogicalControllerID"))
    #expect(!human.standardOutput.contains("last-attempted"))

    let json = try await Self.runStatus(
      ["--json"],
      devices: devices,
      virtualStatus: Self.endedStatus
    ).json()
    let virtual = try #require(json["virtualDevice"] as? [String: Any])
    #expect(virtual["status"] as? String == Self.endedStatus.wireValue)
  }

  @Test
  func humanStatusSaysWhenNoControllerIsPublished() async throws {
    let human = try await Self.runStatus(
      [],
      devices: [Self.device("pad-1", name: "Pad", publication: .notPublished(.noInputYet))],
      virtualStatus: Self.endedStatus
    )
    #expect(
      try Self.virtualLine(human) == CLILocalized.text("cli.status.group.virtualNonePublished")
    )
  }

  @Test
  func statusReportsWhichControllerPauseHolds() async throws {
    var paused = ApplicationServiceDeviceDescription.fixture(id: "pad-1", name: "Held")
    paused.paused = true
    let devices = [paused, ApplicationServiceDeviceDescription.fixture(id: "pad-2", name: "Free")]

    let json = try await Self.runStatus(["--json"], devices: devices, virtualStatus: .error("x"))
      .json()
    let controllers = try #require(json["controllers"] as? [[String: Any]])
    #expect(controllers.map { $0["paused"] as? Bool } == [true, false])

    let human = try await Self.runStatus([], devices: devices, virtualStatus: .error("x"))
    #expect(human.standardOutput.contains(CLILocalized.text("ui.controllers.paused.value")))
  }

  @Test
  func humanStatusNamesBackendError() async throws {
    let human = try await Self.runStatus(
      [],
      devices: [],
      virtualStatus: .error("createFailed")
    )
    #expect(
      try Self.virtualLine(human)
        == CLILocalized.format("cli.status.group.virtualError", "createFailed")
    )
  }
}
