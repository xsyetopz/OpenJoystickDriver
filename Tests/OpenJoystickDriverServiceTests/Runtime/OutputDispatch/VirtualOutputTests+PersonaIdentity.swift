import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  /// A persona directory holding one custom persona for vendor 1, product 2.
  private func personaStore(in directory: URL) throws -> VirtualHIDProfileOverrideStore {
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": VirtualHIDProfileOverrideStore.kind,
      "match": ["vendorID": 1, "productID": 2],
      "persona": "Generic", "labels": "Xbox",
      "identity": [
        "vendorID": 0x1234, "productID": 0x5678, "productName": "Custom Pad",
        "manufacturer": "Custom Maker",
      ] as [String: Any],
    ]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try PropertyListFixture.data(tree: document).write(
      to: directory.appendingPathComponent("0001-0002.plist")
    )
    return VirtualHIDProfileOverrideStore(directory: directory)
  }

  private func personaDispatcher(
    _ identifiers: [LogicalControllerID],
    store: VirtualHIDProfileOverrideStore,
    log: RetargetEventLog
  ) -> AutomaticUserSpaceOutputDispatcher {
    AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(
        dispatcher: LoggingOutputDispatcher(),
        installationKey: testPortKeyInstallationKey
      ),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { profile in
        log.record("built \(profile.rawValue)")
        return RetargetBackendProbe(
          profile: profile,
          log: log,
          failsActivation: false,
          activationGate: nil
        )
      },
      descriptionsProvider: provider(identifiers),
      overrideProvider: {
        store.override(vendorID: $0.vendorID, productID: $0.productID, unit: $0.portKey?.rawValue)
      },
      identityProvider: {
        store.persona(vendorID: $0.vendorID, productID: $0.productID, unit: $0.portKey?.rawValue)?
          .identity
      },
      identityBuilder: { profile, identity in
        let name = "\(identity.vendorID):\(identity.productID) \(identity.productName)"
        log.record("built \(profile.rawValue) as \(name)")
        return RetargetBackendProbe(
          profile: profile,
          log: log,
          failsActivation: false,
          activationGate: nil
        )
      }
    )
  }

  @Test
  func customPersonaIdentityReachesOnlyItsControllersBackend() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("persona-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let custom = LogicalControllerID(vendorID: 1, productID: 2)
    let plain = LogicalControllerID(vendorID: 3, productID: 4)
    let log = RetargetEventLog()
    let dispatcher = personaDispatcher(
      [custom, plain],
      store: try personaStore(in: directory),
      log: log
    )

    try await dispatcher.activate(for: [custom, plain])

    let builds = log.snapshot().filter { $0.hasPrefix("built") }
    #expect(builds == ["built Generic as 4660:22136 Custom Pad", "built SDLCompatible"])
    await dispatcher.close()
  }

  /// Rewrites the persona file of `personaStore(in:)` with `productName` as its identity.
  private func rewritePersona(in directory: URL, productName: String) throws {
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": VirtualHIDProfileOverrideStore.kind,
      "match": ["vendorID": 1, "productID": 2],
      "persona": "Generic", "labels": "Xbox",
      "identity": [
        "vendorID": 0x1234, "productID": 0x5678, "productName": productName,
        "manufacturer": "Custom Maker",
      ] as [String: Any],
    ]
    try PropertyListFixture.data(tree: document).write(
      to: directory.appendingPathComponent("0001-0002.plist")
    )
  }

  @Test
  func personaIdentityChangeRebuildsTheLiveDeviceAndAnUnchangedOneDoesNot() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("persona-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let custom = LogicalControllerID(vendorID: 1, productID: 2)
    let plain = LogicalControllerID(vendorID: 3, productID: 4)
    let log = RetargetEventLog()
    let dispatcher = personaDispatcher(
      [custom, plain],
      store: try personaStore(in: directory),
      log: log
    )
    try await dispatcher.activate(for: [custom, plain])
    func builds() -> [String] { log.snapshot().filter { $0.hasPrefix("built") } }
    #expect(builds().count == 2)

    // The same persona again, and a controller whose persona did not change: no new device.
    try rewritePersona(in: directory, productName: "Custom Pad")
    try await dispatcher.retarget(controller: custom)
    try await dispatcher.retarget(controller: plain)
    #expect(builds().count == 2)

    // The same descriptor with a new identity: the device is created again with it.
    try rewritePersona(in: directory, productName: "Renamed Pad")
    try await dispatcher.retarget(controller: plain)
    #expect(builds().count == 2)
    try await dispatcher.retarget(controller: custom)
    #expect(builds().count == 3)
    #expect(builds().last == "built Generic as 4660:22136 Renamed Pad")

    // The change is applied once.
    try await dispatcher.retarget(controller: custom)
    #expect(builds().count == 3)

    // A removed persona returns the controller to the built-in identity.
    try FileManager.default.removeItem(at: directory.appendingPathComponent("0001-0002.plist"))
    try await dispatcher.retarget(controller: custom)
    #expect(builds().count == 4)
    #expect(builds().last == "built SDLCompatible")
    await dispatcher.close()
  }
}
