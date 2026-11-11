import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordSetTests {
  /// A bundled `XboxGIP` record with no protocol options.
  private static let bundledGIP = ControllerModelID(vendorID: 0x366C, productID: 0x0005)
  /// A bundled `SonyDualShock4` record, a HID family.
  private static let bundledHID = ControllerModelID(vendorID: 0x2C22, productID: 0x2000)
  private static let unbundled = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func json(_ object: [String: Any]) throws -> Data {
    try PropertyListFixture.data(tree: object)
  }

  private static func patch(_ identity: ControllerModelID, set: [String: Any]) throws -> Data {
    try json(ControllerPatch.document(selector: .identity(identity), body: set))
  }

  private static func add(_ identity: ControllerModelID, family: String) throws -> Data {
    try json([
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(identity.vendorID),
      "productID": Int(identity.productID),
      "modes": [["id": "default", "protocol": ["family": family]]],
    ])
  }

  private static func problem(_ data: Data) -> String? {
    do {
      _ = try ControllerRecordSet.validate(data)
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func record(_ data: Data) throws -> ControllerRecord {
    try #require(try ControllerRecordSet.validate(data).record)
  }

  private static func problemCode(_ data: Data) -> ErrorCode? {
    do {
      _ = try ControllerRecordSet.validate(data)
      return nil
    } catch { return ControllerRecordSet.problemCode(error) }
  }

  @Test
  func patchReplacesOnlyItsFieldsAndMarksThemUser() throws {
    let validated = try ControllerRecordSet.validate(
      Self.patch(
        Self.bundledGIP,
        set: [
          "modes": [["id": "default", "protocol": ["family": "XboxGIP", "keepAlive": false]]]
        ]
      )
    )
    let record = try #require(validated.record)
    #expect(validated.operation == .patch)
    #expect(validated.fileName == "366c-0005.patch.plist")
    #expect(record.fieldLayers == ["modes": .user])
    #expect(record.profile.gipKeepAlivePolicy == .disabled)
    #expect(record.usesRawUSB)
    let bundled = try #require(ControllerRecordSet.bundled.records[Self.bundledGIP])
    #expect(bundled.layer == .bundled)
    #expect(bundled.fieldLayers == ["modes": .bundled])
  }

  /// xpad `MAP_SHARE_BUTTON` rows and the GameSir G7 SE, whose Share is payload byte 14 of its
  /// 32-byte input (captured 2026-10-23), read Share 18 bytes from the packet end.
  @Test
  func shareButtonPadsDeclareTheirShareOffset() throws {
    for model in [
      ControllerModelID(vendorID: 0x3537, productID: 0x1010),
      ControllerModelID(vendorID: 0x20D6, productID: 0x2064),
    ] {
      let record = try #require(ControllerRecordSet.bundled.records[model])
      #expect(record.profile.parameters == ProtocolParameters(shareButton: .init(fromEnd: 18)))
    }
  }

  /// A patch overrides `modes` as an array, so a restated default mode keeps only the parameters it
  /// names.
  @Test
  func modesPatchOverridesTheDefaultModeWholesale() throws {
    let shareOffsetGIP = ControllerModelID(vendorID: 0x045E, productID: 0x0B12)
    let bundledShare = try #require(ControllerRecordSet.bundled.records[shareOffsetGIP])
    #expect(bundledShare.profile.parameters == ProtocolParameters(shareButton: .init(fromEnd: 26)))
    let replaced = try Self.record(
      Self.patch(
        shareOffsetGIP,
        set: [
          "modes": [["id": "default", "protocol": ["family": "XboxGIP", "keepAlive": false]]]
        ]
      )
    )
    #expect(replaced.profile.parameters == ProtocolParameters())
    #expect(replaced.profile.gipKeepAlivePolicy == .disabled)
    let refamilied = try Self.record(
      Self.patch(
        Self.bundledHID,
        set: ["modes": [["id": "default", "protocol": ["family": "HIDDescriptor"]]]]
      )
    )
    #expect(refamilied.profile.physicalProtocolID == .hidDescriptor)
  }

  /// A same-family patch adds its parameters to the bundled parameters instead of replacing them.
  @Test
  func modesPatchOverridesTheBundledParameters() throws {
    let dualShock4 = ControllerModelID(vendorID: 0x054C, productID: 0x09CC)
    let patched = try Self.record(
      Self.patch(
        dualShock4,
        set: [
          "modes": [
            [
              "id": "default",
              "protocol": [
                "family": "SonyDualShock4", "parameters": ["motionScale": "StrikePad"],
              ],
            ]
          ]
        ]
      )
    )
    #expect(patched.profile.parameters == ProtocolParameters(motionScale: .strikePad))
  }

  @Test
  func tuningPatchSetsTheRecordTuning() throws {
    let record = try Self.record(
      Self.patch(Self.bundledHID, set: ["tuning": ["inputLivenessTimeoutMs": 2_500]])
    )
    #expect(record.fieldLayers["tuning"] == .user)
    #expect(record.profile.tuning == ControllerTuning(inputLivenessTimeoutMilliseconds: 2_500))
  }

  @Test
  func aControllerFileForANewIdentityIsAUserRecord() throws {
    let validated = try ControllerRecordSet.validate(Self.add(Self.unbundled, family: "XboxGIP"))
    let record = try #require(validated.record)
    #expect(validated.operation == .add)
    #expect(validated.fileName == "1234-abcd.plist")
    #expect(record.model == Self.unbundled)
    #expect(record.fieldLayers == ["modes": .user])
    #expect(record.family == "XboxGIP")
  }

  @Test
  func recordsThatDoNotFitTheCatalogAreRejected() throws {
    #expect(
      Self.problem(try Self.add(Self.bundledGIP, family: "XboxGIP"))
        == "366C:0005 is a bundled controller; use a patch to change it"
    )
    #expect(
      Self.problem(
        try Self.patch(
          Self.unbundled,
          set: ["modes": [["id": "default", "protocol": ["family": "XboxGIP"]]]]
        )
      )
        == "1234:ABCD is not a known controller; use a Controller file"
    )
    #expect(
      Self.problem(
        try Self.patch(
          Self.bundledGIP,
          set: [
            "modes": [
              [
                "id": "default",
                "protocol": [
                  "family": "XboxGIP", "parameters": ["shareButton": ["fromEnd": 18]],
                ],
              ]
            ]
          ]
        )
      )
        == "the patch changes nothing in the record"
    )
    #expect(
      Self.problem(
        try Self.patch(
          Self.bundledHID,
          set: ["usb": ["configuration": "SetConfiguration1BeforeClaim"]]
        )
      )
        == "record.usb: USB overrides require a raw-USB protocol family"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["capabilities": ["rumble": "Absent"]]))
        == "patch must hold modes, usb, bluetoothLE, server, "
        + "route, input, or tuning"
    )
    #expect(
      Self.problem(try Self.patch(Self.bundledGIP, set: ["tuning": ["hidStartupIntervalMs": 5]]))
        == "record.tuning: hidStartupIntervalMs is not read by the XboxGIP driver"
    )
    #expect(Self.problem(PropertyListFixture.bytes(json: "[]")) == "the file is not a dictionary")
    var withNote = ControllerPatch.document(
      selector: .identity(Self.bundledGIP),
      body: ["usb": ["configuration": "SetConfiguration1BeforeClaim"]]
    )
    withNote["note"] = "x"
    #expect(
      Self.problem(try Self.json(withNote))
        == "the file must hold apiVersion, kind, selector, and patch or remove"
    )
    let badFamily = try Self.add(Self.unbundled, family: "xbox.unknown")
    #expect(Self.problem(badFamily) == "record.modes.[0].protocol: unknown family xbox.unknown")
  }

  /// A file declares its version through `apiVersion` and its type through `kind`.
  ///
  /// A missing or unsupported version, or a kind that is not one it is read as, is rejected and
  /// named.
  @Test
  func aMissingOrUnsupportedHeaderIsRejected() throws {
    let supported = "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    let unsupportedAPIVersionValue = "unsupported.example/v9"
    let body = ControllerPatch.document(
      selector: .identity(Self.bundledGIP),
      body: ["usb": ["configuration": "SetConfiguration1BeforeClaim"]]
    )
    let noVersion = body.filter { $0.key != "apiVersion" }
    #expect(
      Self.problem(try Self.json(noVersion)) == "E5001: no apiVersion found; \(supported)"
    )
    #expect(Self.problemCode(try Self.json(noVersion)) == .unsupportedAPIVersion)
    let unsupportedVersion = body.merging(["apiVersion": unsupportedAPIVersionValue]) { $1 }
    #expect(
      Self.problem(try Self.json(unsupportedVersion))
        == "E5001: apiVersion \(unsupportedAPIVersionValue) is not supported; \(supported)"
    )
    #expect(Self.problemCode(try Self.json(unsupportedVersion)) == .unsupportedAPIVersion)
    let noKind = body.filter { $0.key != "kind" }
    #expect(
      Self.problem(try Self.json(noKind)) == "no kind found; expected \(ControllerPatch.kind)"
    )
    for other in ["NotAKind", "OtherKind"] {
      let wrongKind = body.merging(["kind": other]) { $1 }
      #expect(
        Self.problem(try Self.json(wrongKind))
          == "expected \(ControllerPatch.kind), found \(other)"
      )
    }
    let unsupportedRecord = try Self.json([
      "apiVersion": unsupportedAPIVersionValue, "kind": ControllerRecordDocument.kind,
      "vendorID": 0x1234,
      "productID": 0xABCD, "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
    ])
    #expect(
      Self.problem(unsupportedRecord)?.contains(
        "apiVersion \(unsupportedAPIVersionValue) is not supported"
      ) == true
    )
    #expect(Self.problemCode(unsupportedRecord) == .unsupportedAPIVersion)
    let unsupportedDefaults = try Self.json(
      ControllerPatch.document(selector: .all, body: ["tuning": ["stickDeadzone": 0.1]])
        .merging(["apiVersion": unsupportedAPIVersionValue]) { $1 }
    )
    do {
      _ = try ControllerDefaults.validate(unsupportedDefaults)
      Issue.record("the defaults with an unsupported apiVersion were accepted")
    } catch { #expect(ControllerRecordSet.problemCode(error) == .unsupportedAPIVersion) }
    let defaultsWrongKind = PropertyListFixture.bytes(
      json:
        #"{"apiVersion": "\#(OpenJoystickDriverAPI.version)", "kind": "NotAKind", "tuning": {}}"#
    )
    do {
      _ = try ControllerDefaults.validate(defaultsWrongKind)
      Issue.record("the wrong kind was accepted")
    } catch { #expect(ControllerRecordSet.problemCode(error) == .invalidControllerRecord) }
  }

  @Test
  func loadAppliesValidFilesAndReportsTheRest() throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Self.add(Self.unbundled, family: "XboxGIP").write(
      to: directory.appendingPathComponent("1234-abcd.plist")
    )
    try Self.patch(Self.bundledGIP, set: ["usb": ["configuration": "SetConfiguration1BeforeClaim"]])
      .write(
        to: directory.appendingPathComponent("wrong-name.plist")
      )
    try Data("{".utf8).write(to: directory.appendingPathComponent("broken.plist"))

    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(
      set.userFiles.map(\.url.lastPathComponent) == [
        "1234-abcd.plist", "broken.plist", "wrong-name.plist",
      ]
    )
    #expect(set.records[Self.unbundled]?.layer == .user)
    #expect(set.records[Self.bundledGIP]?.layer == .bundled)
    #expect(set.problems.map(\.url.lastPathComponent) == ["broken.plist", "wrong-name.plist"])
    #expect(set.problems.last?.problem == "the file name must be 366c-0005.patch.plist")
    #expect(set.records.count == ControllerRecordSet.bundled.records.count + 1)

    let catalog = DeviceCatalog(records: set)
    let unit = LogicalControllerID(vendorID: 0x1234, productID: 0xABCD, serialNumber: "S")
    #expect(catalog.record(for: unit.model)?.physicalProtocolID == .xboxGIP)
    #expect(
      catalog.rawUSBModels.contains(
        ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
      )
    )
  }

  @Test
  func aUserPatchWithTheSupportedAPIVersionLoadsWithoutProblems() throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-supported-patch-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let document =
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"ControllerPatch","#
      + #""selector":{"vendorID":13932,"productID":5},"patch":{"modes":[{"id":"default","#
      + #""protocol":{"family":"XboxGIP","keepAlive":false}}]}}"#
    try PropertyListFixture.bytes(json: document).write(
      to: directory.appendingPathComponent("366c-0005.patch.plist")
    )

    let set = ControllerRecordSet.load(userDirectory: directory)

    #expect(set.problems.isEmpty)
    #expect(set.userFiles.map(\.url.lastPathComponent) == ["366c-0005.patch.plist"])
  }

  @Test(arguments: [
    #"{"kind":"ControllerPatch","selector":{"vendorID":13932,"productID":5},"patch":{}}"#,
    #"{"apiVersion":"unsupported.example/v9","kind":"ControllerPatch","#
      + #""selector":{"vendorID":13932,"productID":5},"patch":{}}"#,
  ])
  func aUserPatchWithoutTheSupportedAPIVersionIsReportedWithE5001(document: String) throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-stored-patch-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try PropertyListFixture.bytes(json: document).write(
      to: directory.appendingPathComponent("366c-0005.patch.plist")
    )

    let set = ControllerRecordSet.load(userDirectory: directory)

    #expect(set.problems.count == 1)
    #expect(set.problems.first?.problem?.hasPrefix("E5001: ") == true)
  }

  /// The stored-file rule: OJD does not migrate a stored file.
  ///
  /// A file it can read keeps working; a file it cannot read is dropped, reported with its reason,
  /// and left as it was.
  @Test
  func aStoredFileKeepsWorkingOrIsDroppedUnchanged() throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-stored-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let current = PropertyListFixture.bytes(
      json: (#"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","#
        + #""kind":"ControllerPatch","selector":{"vendorID":13932,"productID":5},"#
        + #""patch":{"modes":[{"id":"default","#
        + #""protocol":{"family":"XboxGIP","keepAlive":false}}]}}"#)
    )
    let currentURL = directory.appendingPathComponent("366c-0005.patch.plist")
    try current.write(to: currentURL)
    // A Controller file with an unsupported apiVersion.
    let unsupported = PropertyListFixture.bytes(
      json: (#"{"apiVersion":"unsupported.example/v9","#
        + #""kind":"\#(ControllerRecordDocument.kind)","vendorID":4660,"productID":43981,"#
        + #""modes":[{"id":"default","protocol":{"family":"XboxGIP"}}]}"#)
    )
    let unsupportedURL = directory.appendingPathComponent("1234-abcd.plist")
    try unsupported.write(to: unsupportedURL)
    // A file of an unknown kind.
    let wrongKind = PropertyListFixture.bytes(
      json: (#"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"NotAKind","#
        + #""operation":"patch","vendorID":13932,"productID":5,"set":{"usb":{}}}"#)
    )
    let wrongKindURL = directory.appendingPathComponent("366c-0005.plist")
    try wrongKind.write(to: wrongKindURL)

    let set = ControllerRecordSet.load(userDirectory: directory)

    let kept = try #require(set.records[ControllerModelID(vendorID: 0x366C, productID: 0x0005)])
    #expect(kept.fieldLayers["modes"] == .user)
    #expect(kept.profile.gipKeepAlivePolicy == .disabled)
    #expect(set.records[Self.unbundled] == nil)
    #expect(set.problems.map(\.url.lastPathComponent) == ["1234-abcd.plist", "366c-0005.plist"])
    #expect(
      set.problems.first?.problem
        == "E5001: 1234-abcd.plist: apiVersion unsupported.example/v9 is not supported; "
        + "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    )
    #expect(
      set.problems.last?.problem
        == "366c-0005.plist: expected ControllerPatch, found NotAKind"
    )
    #expect(try Data(contentsOf: unsupportedURL) == unsupported)
    #expect(try Data(contentsOf: currentURL) == current)
    #expect(try Data(contentsOf: wrongKindURL) == wrongKind)
  }

  @Test
  func aMissingDirectoryHoldsNoRecords() {
    let set = ControllerRecordSet.load(
      userDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    )
    #expect(set.userFiles.isEmpty)
    #expect(set.records.count == ControllerRecordSet.bundled.records.count)
  }

  @Test
  func loadIgnoresFilesThatAreNotPropertyLists() throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-records-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("notes".utf8).write(to: directory.appendingPathComponent("README.txt"))
    try Data("{".utf8).write(to: directory.appendingPathComponent("1234-abcd.plist.bak"))

    #expect(ControllerRecordSet.load(userDirectory: directory).userFiles.isEmpty)
  }

  @Test
  func anUnreadableDirectoryIsReportedAndKeepsTheBundledRecords() throws {
    // A regular file stands in for a directory that cannot be listed.
    let path = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      "ojd-records-\(UUID().uuidString)"
    )
    try Data().write(to: path)
    defer { try? FileManager.default.removeItem(at: path) }

    let set = ControllerRecordSet.load(userDirectory: path)
    #expect(set.problems.map(\.url) == [path])
    #expect(set.problems.first?.problem?.hasPrefix("cannot read the directory: ") == true)
    #expect(set.records.count == ControllerRecordSet.bundled.records.count)
  }

  @Test
  func activatingTheSameRecordsChangesNothing() {
    #expect(ControllerRecordSet.bundled.activate().isEmpty)
  }

  /// The merged record keeps the member order of the bundled record where the patch merges into an
  /// object and appends the members the patch adds in the patch's order.
  ///
  /// An array the patch replaces has the patch's order.
  @Test
  func aPatchMergeWritesTheMergedRecordAsAPropertyList() throws {
    let record = try Self.record(
      PropertyListFixture.bytes(
        json: """
          {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ControllerPatch",
           "selector": {"vendorID": 13932, "productID": 5},
           "patch": {"tuning": {"stickDeadzone": 0.08},
                     "modes": [{"protocol": {"keepAlive": false, "family": "XboxGIP"},
                                "id": "default"}]}}
          """
      )
    )
    let expected = PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
         "vendorID": 13932, "productID": 5,
         "modes": [{"protocol": {"keepAlive": false, "family": "XboxGIP"}, "id": "default"}],
         "tuning": {"stickDeadzone": 0.08}}
        """
    )
    #expect(record.text == String(decoding: expected, as: UTF8.self))
  }

  @Test
  func idRangeMessageNamesFileKeyPathRuleAndFix() throws {
    let document: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": 70_000, "productID": 1,
      "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
    ]
    let data = try Self.json(document)
    let english = Localization(preferredLanguages: ["en-US"])
    let error = try #require(throws: ControllerRecordProblem.self) {
      try ControllerRecordSet.validate(data)
    }
    #expect(error.key == "error.E5007.record.idRange")
    #expect(
      ControllerRecordSet.problemDescription(
        error,
        includingCode: false,
        document: "record",
        localization: english,
        file: "1234-abcd.plist"
      )
        == "1234-abcd.plist, vendorID and productID: vendorID must be 1...65535 and productID "
        + "0...65535. Fix: set each to a whole number in its range."
    )
    #expect(
      ControllerRecordSet.problemDescription(error, document: "record")
        == "vendorID must be 1...65535 and productID 0...65535"
    )
    for locale in english.availableLocalizations where locale != "en-US" && locale != "C" {
      let text = ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: [locale]),
        file: "1234-abcd.plist"
      )
      #expect(text.contains("1234-abcd.plist"), "\(locale)")
      #expect(text.contains("vendorID"), "\(locale)")
      #expect(text != error.description, "\(locale)")
    }
  }

  @Test
  func fileNameMessageNamesTheExpectedName() {
    let error = ControllerRecordProblem(
      code: .invalidControllerRecord,
      key: "error.E5007.record.fileName",
      arguments: ["1234-abcd.plist"],
      "filename must be 1234-abcd.plist"
    )
    #expect(
      ControllerRecordSet.problemDescription(
        error,
        document: "record",
        localization: Localization(preferredLanguages: ["en-US"]),
        file: "wrong.plist"
      )
        == "wrong.plist, vendorID and productID: the file name must be 1234-abcd.plist, the two "
        + "IDs in hex. Fix: rename the file to 1234-abcd.plist, or correct the IDs in it."
    )
  }
}
