import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerTuningLayersTests {
  /// A directory that holds `Controllers/` and its `all.patch.plist` for one test.
  private final class Root {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-layers-\(UUID().uuidString)",
      isDirectory: true
    )
    var controllers: URL { url.appendingPathComponent("Controllers", isDirectory: true) }
    var defaultsFile: URL { ControllerDefaults.file(in: controllers) }

    func writeDefaults(
      _ tuning: String,
      apiVersion: String = OpenJoystickDriverAPI.version
    ) throws {
      try writeDefaultsPatch(#"{"tuning":\#(tuning)}"#, apiVersion: apiVersion)
    }

    func writeDefaultsPatch(
      _ set: String,
      apiVersion: String = OpenJoystickDriverAPI.version
    ) throws {
      try FileManager.default.createDirectory(at: controllers, withIntermediateDirectories: true)
      let json =
        #"{"apiVersion":"\#(apiVersion)","kind":"ControllerPatch","selector":{"all":true},"#
        + #""patch":\#(set)}"#
      try OrderedJSON.parse(Data(json.utf8)).plistData().write(to: defaultsFile)
    }

    func writePatch(
      _ set: String,
      remove: [String] = [],
      for identity: ControllerModelID
    ) throws {
      try FileManager.default.createDirectory(at: controllers, withIntermediateDirectories: true)
      let paths = remove.map { "\"" + $0 + "\"" }.joined(separator: ",")
      let removed = remove.isEmpty ? "" : #""remove":[\#(paths)],"#
      let json =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"ControllerPatch","#
        + #""selector":{"vendorID":\#(identity.vendorID),"productID":\#(identity.productID)},"#
        + #"\#(removed)"patch":\#(set)}"#
      try OrderedJSON.parse(Data(json.utf8)).plistData().write(
        to: controllers.appendingPathComponent(
          ControllerPatch.Selector.identity(identity).fileName
        )
      )
    }

    func load() -> ControllerRecordSet { ControllerRecordSet.load(userDirectory: controllers) }

    deinit { try? FileManager.default.removeItem(at: url) }
  }

  /// A bundled GIP record that sets no stick deadzone of its own.
  private func bareRecord() throws -> ControllerRecord {
    try #require(
      ControllerRecordSet.bundled.records.values.first {
        $0.family == "XboxGIP" && $0.tuning.stickDeadzone == nil
      }
    )
  }

  @Test
  func withoutAFileEveryKeyIsADriverDefault() throws {
    let root = Root()
    let record = try #require(root.load().records[try bareRecord().model])

    #expect(record.tuning.stickDeadzone == nil)
    #expect(record.tuningLayers["stickDeadzone"] == nil)
    #expect(root.load().defaults?.problem == nil)
  }

  @Test
  func aGlobalDefaultFillsAKeyTheRecordLeavesUnset() throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)
    let bare = try bareRecord()

    let record = try #require(root.load().records[bare.model])

    #expect(record.tuning.stickDeadzone == 0.2)
    #expect(record.tuningLayers["stickDeadzone"] == .global)
  }

  @Test
  func aUserRecordBeatsTheGlobalDefaultAndKeysLayerIndividually() throws {
    let root = Root()
    let bare = try bareRecord()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)
    try root.writePatch(#"{"tuning":{"stickDeadzone":0.3}}"#, for: bare.model)

    let record = try #require(root.load().records[bare.model])

    #expect(record.tuning.stickDeadzone == 0.3)
    #expect(record.tuningLayers["stickDeadzone"] == .user)
  }

  @Test
  func aPatchOverridesTheFrameQueueCapacityOfOneModelOnly() throws {
    let root = Root()
    let bare = try bareRecord()
    try root.writeDefaults(#"{"frameQueueCapacity":16}"#)
    try root.writePatch(#"{"tuning":{"frameQueueCapacity":4}}"#, for: bare.model)

    let set = root.load()
    let patched = try #require(set.records[bare.model])
    let other = try #require(set.records.values.first { $0.model != bare.model })

    #expect(patched.tuning.frameQueueCapacity == 4)
    #expect(patched.tuningLayers["frameQueueCapacity"] == .user)
    #expect(other.tuning.frameQueueCapacity == 16)
    #expect(other.tuningLayers["frameQueueCapacity"] == .global)
  }

  @Test
  func aGlobalDefaultBeatsTheBundledTuningOfAKey() throws {
    let root = Root()
    // The bundled HID record 11C1:5600 sets `stickDeadzone` to 0.02.
    let identity = ControllerModelID(vendorID: 0x11C1, productID: 0x5600)
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)

    let record = try #require(root.load().records[identity])

    #expect(record.tuning.stickDeadzone == 0.2)
    #expect(record.tuningLayers["stickDeadzone"] == .global)
  }

  @Test
  func aRemoveOfATuningKeyDeletesItFromTheBundledRecord() throws {
    let root = Root()
    let identity = ControllerModelID(vendorID: 0x11C1, productID: 0x5600)
    try root.writePatch(
      #"{"tuning":{"hidStartupIntervalMs":20}}"#,
      remove: ["tuning.stickDeadzone"],
      for: identity
    )

    let record = try #require(root.load().records[identity])

    #expect(record.tuning.stickDeadzone == nil)
    #expect(record.tuningLayers["stickDeadzone"] == nil)
    #expect(record.tuningLayers["hidStartupIntervalMs"] == .user)
  }

  @Test
  func aRemoveOfTheTuningSectionClearsEveryKeyLayer() throws {
    let root = Root()
    let identity = ControllerModelID(vendorID: 0x11C1, productID: 0x5600)
    try root.writePatch(
      #"{"tuning":{"hidStartupIntervalMs":20}}"#,
      remove: ["tuning"],
      for: identity
    )

    let record = try #require(root.load().records[identity])

    #expect(record.tuning.stickDeadzone == nil)
    #expect(record.tuningLayers["stickDeadzone"] == nil)
    #expect(record.tuning.hidStartupIntervalMilliseconds == 20)
    #expect(record.tuningLayers["hidStartupIntervalMs"] == .user)
  }

  @Test
  func anAllPatchOfAnotherSectionMakesTheDefaultsFileInvalid() throws {
    let root = Root()
    try root.writeDefaultsPatch(#"{"usb":{"interface":1}}"#)

    #expect(root.load().defaults?.problem != nil)
  }

  @Test
  func aUserPatchOfOneTuningKeyKeepsTheBundledOthers() throws {
    let root = Root()
    // The bundled HID record 11C1:5600 sets `stickDeadzone` to 0.02.
    let identity = ControllerModelID(vendorID: 0x11C1, productID: 0x5600)
    let bundled = try #require(ControllerRecordSet.bundled.records[identity])
    try root.writePatch(#"{"tuning":{"hidStartupIntervalMs":20}}"#, for: identity)

    let record = try #require(root.load().records[identity])

    #expect(record.tuning.stickDeadzone == bundled.tuning.stickDeadzone)
    #expect(record.tuning.hidStartupIntervalMilliseconds == 20)
    #expect(record.tuningLayers["stickDeadzone"] == .bundled)
    #expect(record.tuningLayers["hidStartupIntervalMs"] == .user)
  }

  @Test
  func aGlobalKeyOutsideTheFamilyScopeDoesNotApply() throws {
    let root = Root()
    try root.writeDefaults(#"{"inputLivenessTimeoutMs":2500}"#)
    let bare = try bareRecord()

    let record = try #require(root.load().records[bare.model])

    #expect(record.tuning.inputLivenessTimeoutMilliseconds == nil)
    #expect(record.tuningLayers["inputLivenessTimeoutMs"] == nil)
  }

  @Test(arguments: [
    #"{"stickDeadzone":3}"#, #"{"unknownKey":1}"#, #"{"stickDeadzone":"0.2"}"#,
  ])
  func anInvalidDefaultsFileIsIgnoredWholeAndReported(tuning: String) throws {
    let root = Root()
    try root.writeDefaults(tuning)
    let bare = try bareRecord()

    let set = root.load()

    #expect(set.defaults?.problem != nil)
    #expect(set.records[bare.model]?.tuning.stickDeadzone == nil)
  }

  @Test
  func anUnsupportedAPIVersionMakesTheDefaultsFileInvalid() throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#, apiVersion: "unsupported.example/v9")

    let problem = root.load().defaults?.problem
    #expect(problem?.hasPrefix("E5001: ") == true)
    #expect(problem?.contains("unsupported.example/v9") == true)
  }

  @Test
  func layersAreOrderedLowestFirst() {
    #expect(
      ControllerRecordLayer.allCases == [.driver, .bundled, .package, .global, .user, .profile]
    )
  }
}
