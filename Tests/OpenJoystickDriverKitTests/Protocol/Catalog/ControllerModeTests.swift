import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A reader that answers each report from a table and counts its reads.
///
/// It implements only the read, like every ``ControllerModeProbeReader``.
private final class ScriptedProbeReader: ControllerModeProbeReader {
  private let replies: [UInt8: PhysicalHIDReportResult<Data>]
  private let reads = Locked<[UInt8]>([])

  init(_ replies: [UInt8: PhysicalHIDReportResult<Data>]) { self.replies = replies }

  var readReports: [UInt8] { reads.withLock { $0 } }

  func readFeatureReport(
    _ request: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    reads.withLock { $0.append(request.reportID) }
    return replies[request.reportID] ?? .unavailable
  }
}

private let stall = PhysicalHIDReportResult<Data>.failed(.declined)
private let timeout = PhysicalHIDReportResult<Data>.failed(.timedOut)

struct ControllerModeTests {
  private static let model = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  /// A model whose default mode is `HIDDescriptor` with two alternatives, each with one probe.
  private static var twoModes: [[String: Any]] {
    [
      mode(
        "dualshock",
        family: "SonyDualShock4",
        probe: ["report": 160, "length": 8, "expect": "Answers"]
      ),
      mode(
        "dualsense",
        family: "SonyDualSense",
        probe: ["report": 161, "length": 8, "expect": "Bytes", "offset": 1, "bytes": "0A FF"]
      ),
    ]
  }

  private static func mode(
    _ id: String,
    family: String,
    probe: [String: Any]
  ) -> [String: Any] {
    ["id": id, "protocol": ["family": family], "match": ["probes": [probe]]]
  }

  private static func recordData(
    modes: [[String: Any]]?,
    family: String,
    extras: [String: Any] = [:]
  ) throws -> Data {
    var record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(model.vendorID), "productID": Int(model.productID),
    ]
    record["modes"] = [["id": "default", "protocol": ["family": family]]] + (modes ?? [])
    return try PropertyListFixture.data(tree: record.merging(extras) { $1 })
  }

  private static func profile(
    modes: [[String: Any]]?,
    family: String = "HIDDescriptor"
  ) throws
    -> DeviceRuntimeProfile
  {
    try #require(try ControllerRecordSet.validate(recordData(modes: modes, family: family)).record)
      .profile
  }

  /// The text of the problem a record with these modes is rejected for, or nil when accepted.
  private static func problem(
    modes: [[String: Any]]?,
    family: String,
    extras: [String: Any]
  ) -> String? {
    do {
      _ = try ControllerRecordSet.validate(recordData(modes: modes, family: family, extras: extras))
      return nil
    } catch { return ControllerRecordSet.problemDescription(error, document: "record") }
  }

  private static func select(
    _ profile: DeviceRuntimeProfile,
    reader: ScriptedProbeReader,
    log: Locked<[String]> = Locked([])
  ) async -> ControllerModeSelection {
    await ControllerModeSelector.select(
      from: profile,
      model: model,
      backend: .hid,
      reader: reader
    ) { line in log.withLock { $0.append(line) } }
  }

  @Test
  func aRecordWithTwoModesPicksEachByItsProbe() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let answered = Data([0x00, 0x0A, 0xFF, 0x00])

    let first = await Self.select(profile, reader: ScriptedProbeReader([160: .success(answered)]))
    #expect(first == .matched("dualshock"))
    #expect(profile.applying(modeID: first.modeID)?.physicalProtocolID == .sonyDualShock4)

    let second = await Self.select(
      profile,
      reader: ScriptedProbeReader([160: stall, 161: .success(answered)])
    )
    #expect(second == .matched("dualsense"))
    #expect(profile.applying(modeID: second.modeID)?.physicalProtocolID == .sonyDualSense)
    #expect(profile.applying(modeID: second.modeID)?.modeID == "dualsense")
  }

  @Test
  func differentProbeRepliesChooseEachRecordOfOneVendorAndProduct() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let wrongBytes = Data([0x00, 0x0B, 0xFF, 0x00])
    let shortReply = Data([0x00])
    let cases: [(String, [UInt8: PhysicalHIDReportResult<Data>], ControllerModeSelection)] = [
      ("first mode answers", [160: .success(Data([1]))], .matched("dualshock")),
      (
        "second mode's bytes match", [160: stall, 161: .success(Data([0, 0x0A, 0xFF]))],
        .matched("dualsense")
      ),
      ("bytes differ", [160: stall, 161: .success(wrongBytes)], .noModeMatched),
      ("reply too short for the pattern", [160: stall, 161: .success(shortReply)], .noModeMatched),
      ("nothing answers but both refuse", [160: stall, 161: stall], .noModeMatched),
    ]
    for (name, replies, expected) in cases {
      let selection = await Self.select(profile, reader: ScriptedProbeReader(replies))
      #expect(selection == expected, Comment(rawValue: name))
    }
    // The record the runtime binds is the default one unless a mode was selected.
    #expect(profile.applying(modeID: nil)?.physicalProtocolID == .hidDescriptor)
    #expect(profile.applying(modeID: "missing") == nil)
  }

  @Test
  func aModeRequiresEveryProbeAndReadsEachReportOnce() async throws {
    let profile = try Self.profile(modes: [
      [
        "id": "both",
        "protocol": ["family": "SonyDualShock4"],
        "match": [
          "probes": [
            ["report": 160, "length": 8, "expect": "Answers"],
            ["report": 160, "length": 8, "expect": "Bytes", "offset": 0, "bytes": "01"],
          ]
        ],
      ]
    ])
    let reader = ScriptedProbeReader([160: .success(Data([1, 2]))])
    #expect(await Self.select(profile, reader: reader) == .matched("both"))
    #expect(reader.readReports == [160])
  }

  @Test
  func aProbeWithoutAReplyFallsBackToTheDefaultModeAndLogsIt() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let replies: [(String, PhysicalHIDReportResult<Data>)] = [
      ("timeout", timeout),
      ("unavailable", .unavailable),
      ("not responding", .failed(.notResponding)),
    ]
    for (name, reply) in replies {
      let log = Locked<[String]>([])
      let selection = await Self.select(
        profile,
        reader: ScriptedProbeReader([160: reply, 161: .success(Data([0, 0x0A, 0xFF]))]),
        log: log
      )
      // The second mode's probe would hold, but a probe that said nothing ends the selection.
      #expect(selection == .probeInconclusive(reportID: 160), Comment(rawValue: name))
      #expect(selection.modeID == nil)
      let lines = log.withLock { $0 }
      #expect(lines.count == 1)
      #expect(lines.first?.contains("1234:ABCD") == true)
      #expect(lines.first?.contains("report=160") == true)
      #expect(lines.first?.contains("default mode") == true)
      // The controller stays enabled: its default profile still binds.
      #expect(profile.applying(modeID: selection.modeID)?.physicalProtocolID == .hidDescriptor)
    }
  }

  /// Two pads of one model differ only by location, so each mode line names it.
  @Test
  func modeLinesNameTheDeviceLocation() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let log = Locked<[String]>([])
    let reader = ScriptedProbeReader([160: .success(Data([1]))])
    let selection = await ControllerModeSelector.select(
      from: profile,
      model: Self.model,
      backend: .hid,
      reader: reader,
      device: PhysicalDevice(physicalLocationIdentifier: 0x0013_0000)
    ) { line in log.withLock { $0.append(line) } }
    #expect(selection == .matched("dualshock"))
    #expect(
      log.withLock { $0 } == [
        "[DeviceManager] Mode keys of 1234:ABCD at location 0x00130000 selected mode dualshock"
      ]
    )
  }

  @Test
  func aStallSatisfiesAStallsProbeAndAnAnswerSatisfiesItNot() async throws {
    let profile = try Self.profile(modes: [
      Self.mode(
        "quiet",
        family: "SonyDualShock4",
        probe: ["report": 5, "length": 4, "expect": "Stalls"]
      )
    ])
    #expect(
      await Self.select(profile, reader: ScriptedProbeReader([5: stall])) == .matched("quiet")
    )
    #expect(
      await Self.select(profile, reader: ScriptedProbeReader([5: .success(Data([5]))]))
        == .noModeMatched
    )
  }

  @Test
  func aStallWhereAnAnswerIsExpectedFallsBackToTheDefaultMode() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let log = Locked<[String]>([])
    let selection = await Self.select(
      profile,
      reader: ScriptedProbeReader([160: stall, 161: stall]),
      log: log
    )
    #expect(selection == .noModeMatched)
    #expect(selection.modeID == nil)
    #expect(log.withLock { $0 }.last?.contains("default mode") == true)
    #expect(profile.applying(modeID: selection.modeID)?.physicalProtocolID == .hidDescriptor)
  }

  @Test
  func onlyTheDevicesOwnRefusalIsAStall() async throws {
    let profile = try Self.profile(modes: [
      Self.mode(
        "quiet",
        family: "SonyDualShock4",
        probe: ["report": 5, "length": 4, "expect": "Stalls"]
      )
    ])
    let unsupported = PhysicalHIDReportResult<Data>.failed(.declined)
    #expect(
      await Self.select(profile, reader: ScriptedProbeReader([5: unsupported])) == .matched("quiet")
    )
    let notTheDevices: [PhysicalHIDFailure] = [
      .timedOut, .busy, .notResponding, .hostStatus(1), .hostStatus(2),
    ]
    for code in notTheDevices {
      let log = Locked<[String]>([])
      let selection = await Self.select(
        profile,
        reader: ScriptedProbeReader([5: .failed(code)]),
        log: log
      )
      #expect(selection == .probeInconclusive(reportID: 5), "\(code)")
      #expect(log.withLock { $0 }.count == 1)
    }
  }

  @Test
  func aDeviceOffTheIOHIDRouteIsNotProbed() async throws {
    let profile = try Self.profile(modes: Self.twoModes)
    let reader = ScriptedProbeReader([160: .success(Data([1]))])
    let log = Locked<[String]>([])
    let selection = await ControllerModeSelector.select(
      from: profile,
      model: Self.model,
      backend: .gatt,
      reader: reader
    ) { line in log.withLock { $0.append(line) } }
    #expect(selection == .noProbeRoute)
    #expect(selection.modeID == nil)
    #expect(reader.readReports.isEmpty)
    #expect(log.withLock { $0 }.first?.contains("GATT") == true)
  }

  @Test
  func aReadIsGivenTheDeadlineItWasAskedFor() async {
    let deadlines = Locked<[TimeInterval]>([])
    let reads = BoundedHIDRead { timeout, action in
      deadlines.withLock { $0.append(timeout) }
      action()
    }
    let release = DispatchSemaphore(value: 0)
    _ = await reads.run(key: UUID(), timeout: 0.75) {
      release.wait()
      return .success(Data([1]))
    }
    release.signal()

    #expect(deadlines.withLock { $0 } == [0.75])
  }

  @Test(.timeLimit(.minutes(1)))
  func aReadThatNeverReturnsGivesUpAtTheDeadline() async {
    let release = DispatchSemaphore(value: 0)
    let reads = BoundedHIDRead()
    let device = UUID()
    // The read blocks until released, so only the deadline can end the call.
    let result = await reads.run(key: device, timeout: 0.05) {
      release.wait()
      return .success(Data([1]))
    }
    guard case .failed(.timedOut) = result else {
      Issue.record("expected a timeout")
      return
    }
    // A read inside the deadline keeps its own answer, and a timeout is no stall.
    release.signal()
    let other = await reads.run(key: UUID(), timeout: 5) { .success(Data([7])) }
    let fast = other
    guard case .success(let data) = fast else {
      Issue.record("expected the answer")
      return
    }
    #expect(data == Data([7]))
    #expect(
      ControllerModeProbe(reportID: 1, length: 1, expectation: .stalls).verdict(for: result)
        == .inconclusive
    )
  }

  @Test
  func aDeviceWithAReadOutstandingIsNotReadAgain() async {
    let release = DispatchSemaphore(value: 0)
    let reads = BoundedHIDRead()
    let device = UUID()
    let calls = Locked(0)
    let first = await reads.run(key: device, timeout: 0.05) {
      calls.withLock { $0 += 1 }
      release.wait()
      return .success(Data([1]))
    }
    guard case .failed(.timedOut) = first else {
      Issue.record("expected a timeout")
      return
    }
    // The first read has not returned, so the same device is refused without a read, and the
    // refusal is no stall.
    let second = await reads.run(key: device, timeout: 0.05) {
      calls.withLock { $0 += 1 }
      return .success(Data([2]))
    }
    guard case .failed(.busy) = second else {
      Issue.record("expected a refusal")
      return
    }
    #expect(calls.withLock { $0 } == 1)
    #expect(
      ControllerModeProbe(reportID: 1, length: 1, expectation: .stalls).verdict(for: second)
        == .inconclusive
    )
    // Another device is unaffected.
    let other = await reads.run(key: UUID(), timeout: 5) { .success(Data([3])) }
    #expect(other.value == Data([3]))
    // Once the blocked read returns, the device can be read again.
    release.signal()
    var again: PhysicalHIDReportResult<Data> = second
    await waitUntil("the released device can be read again") {
      again = await reads.run(key: device, timeout: 5) { .success(Data([4])) }
      return again.value != nil
    }
    #expect(again.value == Data([4]))
  }

  @Test
  func aRecordWithoutModesReadsNothing() async throws {
    let profile = try Self.profile(modes: nil)
    let reader = ScriptedProbeReader([:])
    #expect(await Self.select(profile, reader: reader) == .noModes)
    #expect(reader.readReports.isEmpty)
    #expect(profile.modes.isEmpty)
  }

  @Test
  func theDualShock3EFProbeIsDecodedFromTheBundledRecord() async throws {
    let ds3 = ControllerModelID(vendorID: 0x054C, productID: 0x0268)
    let profile = try #require(ControllerRecordSet.bundled.records[ds3]?.profile)
    #expect(profile.modes.map(\.id) == ["bluetooth", "feature-ef-answers"])
    let mode = try #require(profile.modes.last)
    #expect(mode.probes == [ControllerModeProbe(reportID: 0xEF, length: 49, expectation: .answers)])
    #expect(mode.physicalProtocolID == .sonySixaxis)

    let answering = await ControllerModeSelector.select(
      from: profile,
      model: ds3,
      backend: .hid,
      reader: ScriptedProbeReader([0xEF: .success(Data(repeating: 0, count: 49))])
    ) { _ in }
    #expect(answering == .matched(mode.id))
    let stalling = await ControllerModeSelector.select(
      from: profile,
      model: ds3,
      backend: .hid,
      reader: ScriptedProbeReader([0xEF: stall])
    ) { _ in }
    #expect(stalling == .noModeMatched)
    #expect(stalling.modeID == nil)
  }

  @Test
  func recordsWithoutModesAreUnchangedByTheirAbsence() throws {
    let record = try #require(
      ControllerRecordSet.bundled.records.values.first { $0.profile.modes.isEmpty }
    )
    #expect(record.profile.applying(modeID: nil) == record.profile)
  }

  @Test
  func aUserPatchMayReplaceTheModes() throws {
    let patch = try PropertyListFixture.data(
      tree: ControllerPatch.document(
        selector: .identity(ControllerModelID(vendorID: 0x2C22, productID: 0x2000)),
        body: [
          "modes": [["id": "default", "protocol": ["family": "HIDDescriptor"]]] + Self.twoModes
        ]
      )
    )
    let patched = try #require(try ControllerRecordSet.validate(patch).record).profile
    #expect(patched.modes.map(\.id) == ["dualshock", "dualsense"])
  }

  @Test
  func invalidModesAreRejected() {
    let probe: [String: Any] = ["report": 160, "length": 8, "expect": "Answers"]
    func mode(
      _ id: String,
      family: String = "SonyDualShock4",
      probe: [String: Any] = probe
    )
      -> [String: Any]
    { Self.mode(id, family: family, probe: probe) }
    struct Case {
      let name: String
      let modes: [[String: Any]]?
      var family = "HIDDescriptor"
      var extras: [String: Any] = [:]
      let expected: String
    }
    let layout: [String: Any] = [
      "layouts": [
        [
          "report": ["length": ["atLeast": 8]],
          "buttons": [["control": "South", "bitOffset": 0, "bitSize": 1]],
        ]
      ]
    ]
    let rumble: [String: Any] = [
      "rumble": [
        "report": ["kind": "Output", "id": 2, "length": 8],
        "lowFrequency": ["byte": 3],
      ]
    ]
    let needsLayout =
      "a HIDReportLayout mode needs the record's input layout"
    let rejected: [Case] = [
      Case(
        name: "duplicate ID",
        modes: [mode("a"), mode("a")],
        expected: "mode IDs must be unique"
      ),
      Case(
        name: "default with a match",
        modes: [mode("default")],
        expected: "the default mode has no match"
      ),
      Case(
        name: "uppercase ID",
        modes: [mode("Mode")],
        expected: "a mode id is lowercase words joined by hyphens"
      ),
      Case(
        name: "ID with a trailing newline",
        modes: [mode("abc\n")],
        expected: "a mode id is lowercase words joined by hyphens"
      ),
      Case(
        name: "bytes with a trailing newline",
        modes: [
          mode(
            "a",
            probe: ["report": 1, "length": 8, "expect": "Bytes", "offset": 0, "bytes": "AB\n"]
          )
        ],
        expected: "probe bytes are uppercase hex pairs that fit the read length"
      ),
      Case(
        name: "unknown write key",
        modes: [mode("a", probe: probe.merging(["write": "01"]) { $1 })],
        expected: "unknown field(s): write"
      ),
      Case(
        name: "lowercase hex",
        modes: [
          mode(
            "a",
            probe: ["report": 1, "length": 8, "expect": "Bytes", "offset": 0, "bytes": "ab"]
          )
        ],
        expected: "probe bytes are uppercase hex pairs that fit the read length"
      ),
      Case(
        name: "bytes past length",
        modes: [
          mode(
            "a",
            probe: ["report": 1, "length": 2, "expect": "Bytes", "offset": 1, "bytes": "01 02"]
          )
        ],
        expected: "probe bytes are uppercase hex pairs that fit the read length"
      ),
      Case(
        name: "offset on answers",
        modes: [mode("a", probe: probe.merging(["offset": 0]) { $1 })],
        expected: "a probe expects Answers, Stalls, or Bytes; only Bytes carries offset and bytes"
      ),
      Case(
        name: "report above 255",
        modes: [mode("a", probe: probe.merging(["report": 256]) { $1 })],
        expected: "a probe reads report 0...255 with a length of 1...65535"
      ),
      Case(
        name: "input layout beside a HIDDescriptor mode",
        modes: [mode("a", family: "HIDDescriptor")],
        family: "HIDReportLayout",
        extras: ["input": layout],
        expected: "a HIDDescriptor mode reads a usage map, not input layouts"
      ),
      Case(
        name: "HIDReportLayout mode without the input layout",
        modes: [mode("a", family: "HIDReportLayout")],
        family: "SonySixaxis",
        expected: needsLayout
      ),
      Case(
        name: "rumble template under a mode whose driver does not encode it",
        modes: [
          mode("a", family: "SonySixaxis").merging(["session": rumble]) { first, _ in first }
        ],
        family: "SonySixaxis",
        expected: "rumble templates require a driver that encodes them"
      ),
      Case(
        name: "rumble resend interval beside a session keepAlive",
        modes: [
          [
            "id": "a", "protocol": ["family": "XboxXUSB", "variant": "Wired"],
            "match": ["probes": [probe]],
            "session": [
              "keepAlive": ["intervalMilliseconds": 500, "writes": [["bytes": "01"]]],
              "rumble": [
                "report": ["kind": "USB", "length": 8], "lowFrequency": ["byte": 3],
                "resendIntervalMilliseconds": 100,
              ],
            ],
          ]
        ],
        expected: "a rumble resendIntervalMilliseconds cannot be combined with a session keepAlive"
      ),
      Case(
        name: "rumble resend interval in a family with a keep-alive",
        modes: [
          [
            "id": "a",
            "protocol": [
              "family": "VendorGameSir", "variant": "EnhancedHID",
              "parameters": ["innerGrips": true],
            ],
            "match": ["probes": [probe]],
            "session": [
              "rumble": [
                "report": ["kind": "Output", "id": 2, "length": 8], "lowFrequency": ["byte": 3],
                "resendIntervalMilliseconds": 100,
              ]
            ],
          ]
        ],
        expected: "a rumble resendIntervalMilliseconds needs a family "
          + "whose description declares no keepAlive"
      ),
      Case(
        name: "present controls that no mode driver declares",
        modes: [mode("a", family: "SonySixaxis")],
        family: "SonySixaxis",
        extras: [
          "capabilities": [
            "present": ["LeftPaddle1", "RightPaddle1", "Auxiliary1", "Auxiliary2"]
          ]
        ],
        expected: "capabilities must be deltas the driver of some mode declares"
      ),
    ]
    for rejection in rejected {
      let problem = Self.problem(
        modes: rejection.modes,
        family: rejection.family,
        extras: rejection.extras
      )
      #expect(
        problem?.contains(rejection.expected) == true,
        Comment(rawValue: "\(rejection.name): \(problem ?? "accepted")")
      )
    }
  }
}
