import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

// A mode chosen by its enumerated keys may state `server`, which decides who serves the device
// before any probe runs. An `AwaitsReenumeration` mode states `server: OJD`, so OJD holds a pad
// that changes identity when nothing greets it.
struct ModeServerTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
  private static var defaultMode: [String: Any] {
    ["id": "default", "protocol": ["family": "HIDDescriptor"]]
  }

  private static func mode(
    _ id: String = "switching",
    match: [String: Any] = ["bcdDevice": ["min": 32, "max": 32]],
    idle: String? = nil,
    server: String? = nil
  ) -> [String: Any] {
    var mode: [String: Any] = ["id": id, "protocol": ["family": "HIDDescriptor"], "match": match]
    mode["idle"] = idle
    mode["server"] = server
    return mode
  }

  private static func data(_ modes: [[String: Any]], server: String? = nil) throws -> Data {
    var record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID), "modes": modes,
    ]
    record["server"] = server
    return try PropertyListFixture.data(tree: record)
  }

  private static func problem(_ modes: [[String: Any]]) -> String? {
    do {
      _ = try ControllerRecordSet.validate(data(modes))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func catalog(
    _ modes: [[String: Any]],
    server: String? = nil
  ) throws -> DeviceCatalog {
    let validated = try #require(
      try ControllerRecordSet.validate(data(modes, server: server)).record
    )
    return DeviceCatalog(records: ControllerRecordSet(records: [model: validated], userFiles: []))
  }

  private static func device(release: UInt16) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      deviceRelease: release,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
  }

  private static var awaitingMode: [String: Any] {
    mode(idle: "AwaitsReenumeration", server: "OJD")
  }

  @Test
  func modeServerAppliesWhileItsKeysHold() throws {
    let catalog = try Self.catalog([Self.awaitingMode, Self.defaultMode])
    #expect(catalog.statedServer(of: Self.device(release: 0x0020)) == .ojd)
    #expect(catalog.statedServer(of: Self.device(release: 0x0200)) == nil)
  }

  @Test
  func modeWithoutServerKeepsRecordServer() throws {
    let catalog = try Self.catalog([Self.mode(), Self.defaultMode], server: "System")
    #expect(catalog.statedServer(of: Self.device(release: 0x0020)) == .system)
    #expect(catalog.statedServer(of: Self.device(release: 0x0200)) == .system)
  }

  @Test
  func modeServerOverridesRecordServer() throws {
    let catalog = try Self.catalog(
      [Self.mode(server: "OJD"), Self.defaultMode],
      server: "System"
    )
    #expect(catalog.statedServer(of: Self.device(release: 0x0020)) == .ojd)
  }

  @Test
  func selectedModeProfileCarriesModeServer() throws {
    let catalog = try Self.catalog([Self.mode(server: "OJD"), Self.defaultMode], server: "System")
    let profile = try #require(catalog.record(for: Self.model, modeID: "switching"))
    #expect(profile.server == .ojd)
    #expect(profile.statesServer)
    #expect(catalog.record(for: Self.model, modeID: nil)?.server == .system)
  }

  @Test
  func probeModeAheadKeepsRecordServer() throws {
    let probe: [String: Any] = ["report": 1, "length": 8, "expect": "Answers"]
    let probing = Self.mode(
      "probing",
      match: ["bcdDevice": ["min": 32, "max": 32], "probes": [probe]]
    )
    let catalog = try Self.catalog([probing, Self.mode(server: "OJD"), Self.defaultMode])
    #expect(catalog.statedServer(of: Self.device(release: 0x0020)) == nil)
  }

  @Test
  func awaitingModeClassifiesAsAwaitsReenumeration() throws {
    let catalog = try Self.catalog([Self.awaitingMode, Self.defaultMode])
    #expect(
      ProtocolClassifier.classify(
        Self.device(release: 0x0020),
        backend: .hid,
        catalog: catalog,
        modeID: "switching"
      ) == .unsupported(.awaitsReenumeration)
    )
  }

  @Test
  func defaultModeRefusesServer() {
    var mode = Self.defaultMode
    mode["server"] = "OJD"
    #expect(Self.problem([mode]) != nil)
  }

  @Test
  func probeModeRefusesServer() {
    let probe: [String: Any] = ["report": 1, "length": 8, "expect": "Answers"]
    let mode = Self.mode(match: ["product": "Pad", "probes": [probe]], server: "OJD")
    #expect(Self.problem([mode, Self.defaultMode]) != nil)
  }

  @Test
  func awaitingModeNeedsServerOJD() {
    #expect(Self.problem([Self.awaitingMode, Self.defaultMode]) == nil)
    #expect(Self.problem([Self.mode(idle: "AwaitsReenumeration"), Self.defaultMode]) != nil)
    #expect(
      Self.problem([Self.mode(idle: "AwaitsReenumeration", server: "System"), Self.defaultMode])
        != nil
    )
  }

  @Test
  func unknownModeServerIsRefused() {
    #expect(Self.problem([Self.mode(server: "Mac"), Self.defaultMode]) != nil)
  }

  @Test
  func patchModeMaySetServer() throws {
    let patch = try OrderedJSON.parse(
      Data(
        #"""
        {"apiVersion": "openjoystickdriver/v1alpha3", "kind": "ControllerPatch",
          "selector": {"vendorID": 4660, "productID": 43981},
          "patch": {"modes": [{"id": "switching", "server": "OJD"}]}}
        """#.utf8
      )
    )
    #expect(throws: Never.self) { try ControllerPatch.parse(patch) }
  }
}
