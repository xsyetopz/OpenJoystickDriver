import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A reader that answers every read with `reply` and counts the reads.
private final class CountingProbeReader: ControllerModeProbeReader {
  private let reply: PhysicalHIDReportResult<Data>
  private let reads = Locked(0)

  init(_ reply: PhysicalHIDReportResult<Data> = .success(Data([1]))) { self.reply = reply }

  var readCount: Int { reads.withLock { $0 } }

  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    reads.withLock { $0 += 1 }
    return reply
  }
}

/// The cheap keys of a mode's `match`: link kind, interface signature, strings, `bcdDevice`, and
/// the `interface` and `session` a mode sets.
struct ControllerModeMatchTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)
  private static var answers: [String: Any] { ["report": 7, "length": 8, "expect": "Answers"] }

  private static func recordData(
    modes: [[String: Any]],
    family: String = "SonySixaxis"
  ) throws
    -> Data
  {
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID),
      "modes": [["id": "default", "protocol": ["family": family]]] + modes,
    ]
    return try JSONSerialization.data(withJSONObject: record)
  }

  private static func mode(
    _ id: String,
    match: [String: Any],
    family: String = "SonySixaxis",
    extras: [String: Any] = [:]
  )
    -> [String: Any]
  {
    ["id": id, "protocol": ["family": family], "match": match].merging(extras) { $1 }
  }

  private static func profile(
    _ modes: [[String: Any]],
    family: String = "SonySixaxis"
  ) throws -> DeviceRuntimeProfile {
    try #require(
      try ControllerRecordSet.validate(recordData(modes: modes, family: family)).record
    ).profile
  }

  private static func problem(
    _ modes: [[String: Any]],
    family: String = "SonySixaxis"
  ) throws
    -> String?
  {
    do {
      _ = try ControllerRecordSet.validate(recordData(modes: modes, family: family))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func signature(endpoints: [[String: Any]]) -> [String: Any] {
    [
      "interfaceClass": 255, "interfaceSubclass": 93, "interfaceProtocol": 1,
      "endpoints": endpoints,
    ]
  }

  private static func device(
    link: PhysicalTransport = .usb,
    release: UInt16? = nil,
    manufacturer: String? = nil,
    product: String? = nil,
    interfaces: [PhysicalInterfaceSignature]? = nil
  ) -> PhysicalDevice {
    PhysicalDevice(
      vendorID: model.vendorID,
      productID: model.productID,
      deviceRelease: release,
      manufacturer: manufacturer,
      productName: product,
      interfaces: interfaces
        ?? [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: link)]
    )
  }

  private static func select(
    _ profile: DeviceRuntimeProfile,
    _ device: PhysicalDevice,
    backend: DeviceAccessBackend = .hid,
    reader: CountingProbeReader = CountingProbeReader()
  ) async -> ControllerModeSelection {
    await ControllerModeSelector.select(
      from: profile,
      model: model,
      backend: backend,
      reader: reader,
      device: device
    ) { _ in }
  }

  /// "One model, two modes": the wired and the Bluetooth link of one record are two modes.
  @Test
  func aWiredAndABluetoothLinkSelectTheirOwnMode() async throws {
    let profile = try Self.profile([
      Self.mode("wired", match: ["link": "USB"]),
      Self.mode("bluetooth", match: ["link": "BluetoothClassic"]),
    ])
    let wired = await Self.select(profile, Self.device(link: .usb))
    let bluetooth = await Self.select(profile, Self.device(link: .bluetoothClassic))
    let other = await Self.select(profile, Self.device(link: .bluetoothLE))
    #expect(wired == .matched("wired"))
    #expect(bluetooth == .matched("bluetooth"))
    #expect(other == .noModeMatched)
  }

  /// "Dongle and wired": a receiver link and a USB link of one model each run their own mode.
  @Test
  func aDongleAndAWiredLinkSelectTheirOwnMode() async throws {
    let profile = try Self.profile([
      Self.mode("dongle", match: ["link": "ProprietaryRadioReceiver"]),
      Self.mode("wired", match: ["link": "USB"]),
    ])
    let dongle = await Self.select(profile, Self.device(link: .proprietaryRadioReceiver))
    let wired = await Self.select(profile, Self.device(link: .usb))
    #expect(dongle == .matched("dongle"))
    #expect(wired == .matched("wired"))
  }

  /// A receiver or dongle record is the evidence of the radio link: macOS reports the dongle as a
  /// USB device, so discovery sees the host link `usb` and the record supplies the controller-side
  /// link.
  ///
  /// A model whose record is no receiver never reports it.
  @Test
  func aReceiverRecordReportsTheRadioLinkAndSelectsItsMode() async throws {
    func profile(variant: String?) throws -> DeviceRuntimeProfile {
      var protocolKeys: [String: Any] = ["family": "ValveSteamController"]
      protocolKeys["variant"] = variant
      let radio: [String: Any] = [
        "id": "radio", "protocol": protocolKeys, "match": ["link": "ProprietaryRadioReceiver"],
        "interface": ["first": 2, "last": 5],
      ]
      let record: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": Int(Self.model.vendorID), "productID": Int(Self.model.productID),
        "modes": [["id": "default", "protocol": protocolKeys], radio],
      ]
      return try #require(
        try ControllerRecordSet.validate(JSONSerialization.data(withJSONObject: record)).record
      ).profile
    }
    let dongle = try profile(variant: "Dongle")
    let wired = try profile(variant: "Wired")
    let discovered = Self.device(link: .usb)
    #expect(await Self.select(dongle, discovered) == .matched("radio"))
    #expect(await Self.select(wired, discovered) == .noModeMatched)
    // An observed controller-side link outranks the record's evidence.
    let observed = Self.device(
      interfaces: [
        PhysicalInterfaceSignature(
          interfaceNumber: 0,
          hostTransport: .usb,
          physicalTransport: .usb
        )
      ]
    )
    #expect(await Self.select(dongle, observed) == .noModeMatched)
  }

  @Test
  func aLinkKeyNeedsEveryInterfaceOnThatLink() async throws {
    let profile = try Self.profile([Self.mode("bluetooth", match: ["link": "BluetoothClassic"])])
    let mixed = Self.device(
      interfaces: [
        PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .bluetoothClassic),
        PhysicalInterfaceSignature(interfaceNumber: 1, hostTransport: .usb),
      ]
    )
    #expect(await Self.select(profile, mixed) == .noModeMatched)
    #expect(await Self.select(profile, PhysicalDevice()) == .noModeMatched)
  }

  @Test
  func stringsMatchExactly() async throws {
    let profile = try Self.profile([
      Self.mode("named", match: ["manufacturer": "Sony", "product": "Wireless Controller"])
    ])
    let right = Self.device(manufacturer: "Sony", product: "Wireless Controller")
    #expect(await Self.select(profile, right) == .matched("named"))
    let wrongProduct = Self.device(manufacturer: "Sony", product: "Controller")
    #expect(await Self.select(profile, wrongProduct) == .noModeMatched)
    #expect(await Self.select(profile, Self.device(manufacturer: "Sony")) == .noModeMatched)
  }

  @Test
  func aBCDDeviceRangeIsInclusive() async throws {
    let profile = try Self.profile([
      Self.mode("early", match: ["bcdDevice": ["min": 0x0100, "max": 0x0200]])
    ])
    for (release, expected) in [
      (UInt16?(0x00FF), ControllerModeSelection.noModeMatched), (0x0100, .matched("early")),
      (0x0200, .matched("early")), (0x0201, .noModeMatched), (nil, .noModeMatched),
    ] {
      let selection = await Self.select(profile, Self.device(release: release))
      #expect(selection == expected, Comment(rawValue: "release \(release ?? 0)"))
    }
  }

  @Test
  func anInterfaceSignatureNeedsOneInterfaceThatHoldsEveryField() async throws {
    let profile = try Self.profile([
      Self.mode(
        "hid",
        match: [
          "interfaceSignature": [
            "interfaceClass": 3, "interfaceSubclass": 0, "interfaceProtocol": 0,
          ]
        ]
      )
    ])
    let hid = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0
    )
    let vendor = PhysicalInterfaceSignature(
      interfaceNumber: 1,
      interfaceClass: 255,
      interfaceSubclass: 71,
      interfaceProtocol: 208
    )
    #expect(await Self.select(profile, Self.device(interfaces: [vendor, hid])) == .matched("hid"))
    #expect(await Self.select(profile, Self.device(interfaces: [vendor])) == .noModeMatched)
  }

  /// Two interfaces of one class triple are told apart by their endpoint sets: the listed
  /// endpoints must pair one-to-one with the interface's and none may be left over.
  @Test
  func anEndpointSetTellsApartInterfacesOfOneClassTriple() async throws {
    func signature(_ endpoints: [[String: Any]]) -> [String: Any] {
      [
        "interfaceClass": 255, "interfaceSubclass": 93, "interfaceProtocol": 1,
        "endpoints": endpoints,
      ]
    }
    let profile = try Self.profile(
      [
        Self.mode(
          "pair",
          match: [
            "interfaceSignature": signature([
              ["direction": "In", "transferType": "Interrupt"],
              ["direction": "Out", "transferType": "Interrupt"],
            ])
          ],
          family: "XboxGIP"
        ),
        Self.mode(
          "single",
          match: [
            "interfaceSignature": signature([
              ["address": 129, "direction": "In", "transferType": "Bulk", "maxPacketSize": 64]
            ])
          ],
          family: "XboxGIP"
        ),
      ],
      family: "XboxGIP"
    )
    func interface(_ endpoints: [PhysicalEndpointSignature]?) -> PhysicalDevice {
      Self.device(
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            interfaceClass: 255,
            interfaceSubclass: 93,
            interfaceProtocol: 1,
            hostTransport: .usb,
            endpoints: endpoints
          )
        ]
      )
    }
    let input = PhysicalEndpointSignature(
      address: 129,
      direction: .in,
      transferType: .interrupt,
      maxPacketSize: 32
    )
    let output = PhysicalEndpointSignature(
      address: 1,
      direction: .out,
      transferType: .interrupt,
      maxPacketSize: 32
    )
    let bulk = PhysicalEndpointSignature(
      address: 129,
      direction: .in,
      transferType: .bulk,
      maxPacketSize: 64
    )
    #expect(await Self.select(profile, interface([output, input])) == .matched("pair"))
    #expect(await Self.select(profile, interface([bulk])) == .matched("single"))
    // A leftover endpoint, a missing one, a wrong fact, and unreported endpoints all fail.
    #expect(await Self.select(profile, interface([input, output, bulk])) == .noModeMatched)
    #expect(await Self.select(profile, interface([input])) == .noModeMatched)
    #expect(await Self.select(profile, interface([input, input])) == .noModeMatched)
    #expect(await Self.select(profile, interface(nil)) == .noModeMatched)
  }

  /// A HID route reports no endpoint set, so a HID mode that names `endpoints` could never be
  /// selected; the record is refused.
  ///
  /// The same signature on a raw-USB mode is accepted.
  @Test
  func aHIDModeWithEndpointsIsRefusedAndARawUSBModeIsNot() throws {
    let endpoints: [[String: Any]] = [["direction": "In", "transferType": "Interrupt"]]
    let match: [String: Any] = ["interfaceSignature": Self.signature(endpoints: endpoints)]
    let hid = try Self.problem([Self.mode("x", match: match)])
    #expect(hid?.contains("endpoints") == true)
    let rawUSB = try Self.problem(
      [Self.mode("x", match: match, family: "XboxGIP")],
      family: "XboxGIP"
    )
    #expect(rawUSB == nil)
    let withoutEndpoints = try Self.problem([
      Self.mode(
        "x",
        match: [
          "interfaceSignature": [
            "interfaceClass": 255, "interfaceSubclass": 93, "interfaceProtocol": 1,
          ]
        ]
      )
    ])
    #expect(withoutEndpoints == nil)
  }

  /// A probe is the costly key: it is read only after every cheap key of its mode holds.
  @Test
  func aProbeIsReadOnlyAfterTheCheapKeysHold() async throws {
    let profile = try Self.profile([
      Self.mode("probed", match: ["link": "BluetoothClassic", "probes": [Self.answers]])
    ])
    let reader = CountingProbeReader()
    let usb = await Self.select(profile, Self.device(link: .usb), reader: reader)
    #expect(usb == .noModeMatched)
    #expect(reader.readCount == 0)
    let bluetooth = await Self.select(
      profile,
      Self.device(link: .bluetoothClassic),
      reader: reader
    )
    #expect(bluetooth == .matched("probed"))
    #expect(reader.readCount == 1)
  }

  /// A mode with no probe is selectable on a route that cannot read one.
  @Test
  func aModeWithoutAProbeIsSelectableWithoutAnIOHIDRoute() async throws {
    let profile = try Self.profile([
      Self.mode("bluetooth", match: ["link": "BluetoothClassic"]),
      Self.mode("probed", match: ["probes": [Self.answers]]),
    ])
    let reader = CountingProbeReader()
    let direct = await Self.select(
      profile,
      Self.device(link: .bluetoothClassic),
      backend: .rawUSB,
      reader: reader
    )
    #expect(direct == .matched("bluetooth"))
    let probed = await Self.select(
      profile,
      Self.device(link: .usb),
      backend: .rawUSB,
      reader: reader
    )
    #expect(probed == .noProbeRoute)
    #expect(reader.readCount == 0)
  }

  /// A mode runs the steps of its own `session` only; a mode without a session runs none.
  @Test
  func aModeRunsOnlyItsOwnSession() throws {
    let write: [String: Any] = [
      "report": ["kind": "Feature", "id": 244, "length": 5], "bytes": "42 03 00 00",
    ]
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(Self.model.vendorID), "productID": Int(Self.model.productID),
      "modes": [
        [
          "id": "default", "protocol": ["family": "SonySixaxis"],
          "session": [
            "startup": [["report": ["kind": "Output", "id": 0, "length": 2], "bytes": "01 02"]]
          ],
        ],
        Self.mode("plain", match: ["link": "USB"]),
        Self.mode(
          "session",
          match: ["link": "BluetoothClassic"],
          extras: ["session": ["startup": [write]]]
        ),
      ],
    ]
    let profile = try #require(
      try ControllerRecordSet.validate(JSONSerialization.data(withJSONObject: record)).record
    ).profile
    #expect(profile.startupWrites.count == 1)
    #expect(profile.applying(modeID: "plain")?.startupWrites.isEmpty == true)
    let session = try #require(profile.applying(modeID: "session"))
    #expect(
      session.startupWrites.map(\.write) == [
        .hidFeature(PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 3, 0, 0]))
      ]
    )
  }

  /// The DS3 record holds Bluetooth as a link of its own mode, with the enable report as that
  /// mode's session.
  @Test
  func theDS3RecordSelectsItsBluetoothModeByLink() async throws {
    let ds3 = ControllerModelID(vendorID: 0x054C, productID: 0x0268)
    let profile = try #require(DeviceCatalog().record(for: ds3))
    #expect(profile.startupWrites.isEmpty)
    let bluetooth = PhysicalDevice(
      vendorID: ds3.vendorID,
      productID: ds3.productID,
      interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .bluetoothClassic)]
    )
    let usb = PhysicalDevice(
      vendorID: ds3.vendorID,
      productID: ds3.productID,
      interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: .usb)]
    )
    let selected = await ControllerModeSelector.select(
      from: profile,
      model: ds3,
      backend: .hid,
      reader: CountingProbeReader(),
      device: bluetooth
    ) { _ in }
    #expect(selected == .matched("bluetooth"))
    let session = try #require(profile.applying(modeID: selected.modeID))
    #expect(
      session.startupWrites.map(\.write) == [
        .hidFeature(PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 3, 0, 0]))
      ]
    )
    let wired = await ControllerModeSelector.select(
      from: profile,
      model: ds3,
      backend: .hid,
      reader: CountingProbeReader(),
      device: usb
    ) { _ in }
    #expect(wired != .matched("bluetooth"))
  }

  /// A mode's `interface` range picks the interface the driver binds to.
  @Test
  func aModeInterfaceRangeChoosesTheBoundInterface() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ojd-modes-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let ranged = Self.mode(
      "ranged",
      match: ["link": "USB"],
      extras: ["interface": ["first": 2, "last": 3]]
    )
    try Self.recordData(modes: [ranged]).write(
      to: directory.appendingPathComponent("1234-abcd.json")
    )
    let set = ControllerRecordSet.load(userDirectory: directory)
    #expect(set.problems.isEmpty)
    let catalog = DeviceCatalog(records: set)
    let device = Self.device(
      interfaces: (0...4).map {
        PhysicalInterfaceSignature(interfaceNumber: UInt8($0), hostTransport: .usb)
      }
    )
    func bound(_ modeID: String?) -> UInt8? {
      guard
        case .bound(let binding) = ProtocolClassifier.classify(
          device,
          backend: .hid,
          catalog: catalog,
          modeID: modeID
        )
      else { return nil }
      return binding.interfaceNumber
    }
    #expect(bound("ranged") == 2)
    #expect(bound(nil) == nil)
  }

  // MARK: Decoder rejections, matched by the Python schema tests

  @Test
  func theDecoderRejectsTheSameBadModesAsTheSchema() throws {
    let usb = ["link": "USB"]
    let cases: [(String, [[String: Any]], String)] = [
      ("no match", [["id": "x", "protocol": ["family": "SonySixaxis"]]], "match"),
      ("empty match", [Self.mode("x", match: [:])], "match"),
      ("unknown link", [Self.mode("x", match: ["link": "serial"])], "link"),
      (
        "bcdDevice min above max",
        [Self.mode("x", match: ["bcdDevice": ["min": 5, "max": 4]])], "bcdDevice"
      ),
      (
        "bcdDevice above 16 bits",
        [Self.mode("x", match: ["bcdDevice": ["min": 0, "max": 65_536]])], "bcdDevice"
      ),
      ("empty manufacturer", [Self.mode("x", match: ["manufacturer": ""])], "manufacturer"),
      (
        "signature without a class",
        [Self.mode("x", match: ["interfaceSignature": ["interfaceSubclass": 1]])], "interfaceClass"
      ),
      ("unknown match key", [Self.mode("x", match: usb.merging(["serial": "1"]) { $1 })], "serial"),
      (
        "interface first above last",
        [Self.mode("x", match: usb, extras: ["interface": ["first": 2, "last": 1]])], "interface"
      ),
      (
        "session with an empty startup",
        [Self.mode("x", match: usb, extras: ["session": ["startup": [[String: Any]]()]])],
        "startup"
      ),
      ("unknown mode key", [Self.mode("x", match: usb, extras: ["keepAlive": 1])], "keepAlive"),
      ("default with a match", [Self.mode("default", match: usb)], "default"),
      (
        "empty endpoint list",
        [Self.mode("x", match: ["interfaceSignature": Self.signature(endpoints: [])])],
        "at least one endpoint"
      ),
      (
        "endpoint without a key",
        [Self.mode("x", match: ["interfaceSignature": Self.signature(endpoints: [[:]])])],
        "at least one key"
      ),
      (
        "endpoint with a bad direction",
        [
          Self.mode(
            "x",
            match: ["interfaceSignature": Self.signature(endpoints: [["direction": "both"]])]
          )
        ], "direction"
      ),
      (
        "endpoint with an unknown transfer type",
        [
          Self.mode(
            "x",
            match: ["interfaceSignature": Self.signature(endpoints: [["transferType": "unknown"]])]
          )
        ], "transferType"
      ),
      (
        "endpoint address above 255",
        [
          Self.mode(
            "x",
            match: ["interfaceSignature": Self.signature(endpoints: [["address": 256]])]
          )
        ], "address"
      ),
      (
        "endpoint packet size above 16 bits",
        [
          Self.mode(
            "x",
            match: ["interfaceSignature": Self.signature(endpoints: [["maxPacketSize": 65_536]])]
          )
        ], "maxPacketSize"
      ),
      (
        "endpoint with an unknown key",
        [
          Self.mode(
            "x",
            match: ["interfaceSignature": Self.signature(endpoints: [["interval": 1]])]
          )
        ], "interval"
      ),
    ]
    for (name, modes, fragment) in cases {
      let problem = try Self.problem(modes)
      #expect(
        problem?.contains(fragment) == true,
        Comment(rawValue: "\(name): \(problem ?? "accepted")")
      )
    }
  }

  /// A record without a `default` mode leaves a device that matches none of its modes unsupported.
  @Test
  func aRecordWithoutADefaultModeLeavesAnUnmatchedDeviceUnsupported() async throws {
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(Self.model.vendorID), "productID": Int(Self.model.productID),
      "modes": [Self.mode("named", match: ["product": "Wireless Controller"])],
    ]
    let validated = try #require(
      try ControllerRecordSet.validate(JSONSerialization.data(withJSONObject: record)).record
    )
    let catalog = DeviceCatalog(
      records: ControllerRecordSet(records: [Self.model: validated], userFiles: [])
    )
    let profile = validated.profile
    #expect(!profile.hasDefaultMode)
    let reader = CountingProbeReader()
    let matching = Self.device(product: "Wireless Controller")
    let other = Self.device(product: "Other")
    let matched = await Self.select(profile, matching, reader: reader)
    let unmatched = await Self.select(profile, other, reader: reader)
    #expect(matched == .matched("named"))
    #expect(unmatched == .noModeMatched)
    #expect(reader.readCount == 0)
    #expect(
      ProtocolClassifier.classify(
        matching,
        backend: .hid,
        catalog: catalog,
        modeID: matched.modeID
      ) != .unsupported(.noModeMatched)
    )
    #expect(
      ProtocolClassifier.classify(
        other,
        backend: .hid,
        catalog: catalog,
        modeID: unmatched.modeID
      ) == .unsupported(.noModeMatched)
    )
    #expect(ProtocolBindingReason.noModeMatched.explanationKey == "ui.controllers.noModeMatched")
  }

  @Test
  func theDecoderRejectsAModeListWithTwoDefaults() throws {
    func decode(_ modes: [[String: Any]]?) throws -> String? {
      var record: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": 1, "productID": 2,
      ]
      record["modes"] = modes
      do {
        _ = try ControllerRecordSet.validate(JSONSerialization.data(withJSONObject: record))
        return nil
      } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
    }
    let other = Self.mode("x", match: ["link": "USB"])
    let plainDefault: [String: Any] = ["id": "default", "protocol": ["family": "SonySixaxis"]]
    #expect(try decode(nil) != nil)
    #expect(try decode([]) != nil)
    #expect(try decode([other]) == nil)
    #expect(
      try decode([plainDefault, plainDefault])?.contains("at most one mode with the id default")
        == true
    )
    #expect(
      try decode([plainDefault, other, other])?.contains("mode IDs must be unique") == true
    )
  }

  @Test
  func interfaceAndSessionApplyOnlyToHIDModes() throws {
    let write: [String: Any] = [
      "report": ["kind": "Feature", "id": 1, "length": 2], "bytes": "01 02",
    ]
    let rawDefault: [String: Any] = ["id": "default", "protocol": ["family": "XboxGIP"]]
    for (name, extras) in [
      ("interface", ["interface": ["first": 0, "last": 1]]),
      ("session", ["session": ["startup": [write]]]),
    ] as [(String, [String: Any])] {
      var record: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": 1, "productID": 2,
      ]
      record["modes"] = [rawDefault.merging(extras) { $1 }]
      #expect(throws: (any Error).self, Comment(rawValue: name)) {
        try ControllerRecordSet.validate(JSONSerialization.data(withJSONObject: record))
      }
    }
  }

  /// Vader 5S: the GIP mode is the default and the XUSB mode is keyed on `FF/5D/01`.
  @Test
  func theVader5SRunsGIPOrXUSBFromItsInterfaceSignature() async throws {
    let vader = ControllerModelID(vendorID: 0x37D7, productID: 0x2801)
    let profile = try #require(ControllerRecordSet.bundled.records[vader]?.profile)
    func run(_ triple: (UInt8, UInt8, UInt8)?) async -> (PhysicalProtocolID, [String]) {
      let interfaces = triple.map {
        [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            interfaceClass: $0.0,
            interfaceSubclass: $0.1,
            interfaceProtocol: $0.2,
            hostTransport: .usb
          )
        ]
      }
      let lines = Locked<[String]>([])
      let selection = await ControllerModeSelector.select(
        from: profile,
        model: vader,
        backend: .rawUSB,
        reader: CountingProbeReader(),
        device: PhysicalDevice(
          vendorID: vader.vendorID,
          productID: vader.productID,
          interfaces: interfaces
        )
      ) { line in lines.withLock { $0.append(line) } }
      let running = profile.applying(modeID: selection.modeID)
      return (running?.physicalProtocolID ?? .hidDescriptor, lines.withLock { $0 })
    }
    let gip = await run((0xFF, 0x47, 0xD0))
    let xusb = await run((0xFF, 0x5D, 0x01))
    let neither = await run((0x03, 0x00, 0x00))
    #expect(gip.0 == .xboxGIP)
    #expect(gip.1.contains { $0.contains("interface classes seen: FF/47/D0") })
    #expect(xusb.0 == .xboxXUSB)
    #expect(xusb.1.contains { $0.contains("selected mode xusb") })
    #expect(neither.0 == .xboxGIP)
    #expect(neither.1.contains { $0.contains("interface classes seen: 03/00/00") })
  }
}
