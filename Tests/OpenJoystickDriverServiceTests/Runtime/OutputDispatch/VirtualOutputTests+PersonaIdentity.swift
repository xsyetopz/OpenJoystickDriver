import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  /// A persona directory holding one custom persona for vendor 1, product 2.
  private func personaStore(in directory: URL) throws -> VirtualHIDProfileOverrideStore {
    let document: [String: Any] = [
      "$schema": VirtualHIDProfileOverrideStore.schemaID,
      "match": ["vendorID": 1, "productID": 2],
      "descriptor": "hid-generic",
      "identity": [
        "vendorID": 0x1234, "productID": 0x5678, "productName": "Custom Pad",
        "manufacturer": "Custom Maker", "glyphFamily": "xbox",
      ] as [String: Any],
    ]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: document).write(
      to: directory.appendingPathComponent("0001-0002.json")
    )
    return VirtualHIDProfileOverrideStore(directory: directory)
  }

  private func personaDispatcher(
    _ identifiers: [DeviceIdentifier],
    store: VirtualHIDProfileOverrideStore,
    log: RetargetEventLog
  ) -> AutomaticUserSpaceOutputDispatcher {
    AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
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
      descriptionsProvider: provider(identifiers.map { description($0) }),
      overrideProvider: {
        store.override(vendorID: $0.vendorID, productID: $0.productID, unit: $0.unitIdentifier)
      },
      identityProvider: {
        store.persona(vendorID: $0.vendorID, productID: $0.productID, unit: $0.unitIdentifier)?
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
    let custom = DeviceIdentifier(vendorID: 1, productID: 2)
    let plain = DeviceIdentifier(vendorID: 3, productID: 4)
    let log = RetargetEventLog()
    let dispatcher = personaDispatcher(
      [custom, plain],
      store: try personaStore(in: directory),
      log: log
    )

    try await dispatcher.activate(for: [custom, plain])

    let builds = log.snapshot().filter { $0.hasPrefix("built") }
    #expect(builds == ["built hid-generic as 4660:22136 Custom Pad", "built hid-xbox-one-s-bt"])
    await dispatcher.close()
  }

  /// Rewrites the persona file of `personaStore(in:)` with `productName` as its identity.
  private func rewritePersona(in directory: URL, productName: String) throws {
    let document: [String: Any] = [
      "$schema": VirtualHIDProfileOverrideStore.schemaID,
      "match": ["vendorID": 1, "productID": 2],
      "descriptor": "hid-generic",
      "identity": [
        "vendorID": 0x1234, "productID": 0x5678, "productName": productName,
        "manufacturer": "Custom Maker", "glyphFamily": "xbox",
      ] as [String: Any],
    ]
    try JSONSerialization.data(withJSONObject: document).write(
      to: directory.appendingPathComponent("0001-0002.json")
    )
  }

  @Test
  func personaIdentityChangeRebuildsTheLiveDeviceAndAnUnchangedOneDoesNot() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("persona-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let custom = DeviceIdentifier(vendorID: 1, productID: 2)
    let plain = DeviceIdentifier(vendorID: 3, productID: 4)
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
    #expect(builds().last == "built hid-generic as 4660:22136 Renamed Pad")

    // The change is applied once.
    try await dispatcher.retarget(controller: custom)
    #expect(builds().count == 3)

    // A removed persona returns the controller to the built-in identity.
    try FileManager.default.removeItem(at: directory.appendingPathComponent("0001-0002.json"))
    try await dispatcher.retarget(controller: custom)
    #expect(builds().count == 4)
    #expect(builds().last == "built hid-xbox-one-s-bt")
    await dispatcher.close()
  }
}
