import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct DiagnoseCommandTests {
  private static let healthyExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .present, registration: .active("enabled"))
  }

  private static let noAudit: @Sendable () -> SystemGamepadSupportAudit? = { nil }

  private static let brokenExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .missing, registration: .absent)
  }

  private func serve(
    socketPath: String,
    timings: ControllerFrameTimings = .fixture,
    onFrameTimings: @escaping @Sendable (Data) -> Void = { _ in }
  ) throws -> LocalServiceRPCServer {
    let statusResult = try JSONEncoder().encode(
      try JSONEncoder().encode(
        ApplicationServiceStatusPayload(
          inputRead: .granted,
          inputInject: .granted,
          connectedDevices: [],
          userSpaceVirtualDeviceEnabled: true
        )
      )
    )
    let timingsResult = try JSONEncoder().encode(
      try JSONEncoder().encode(
        ApplicationServiceFrameTimingsPayload(controllers: [timings])
      )
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        if request.method == ApplicationServiceRPCMethod.getStatus.rawValue {
          return LocalServiceRPCResponse(result: statusResult, error: nil)
        }
        if request.method == ApplicationServiceRPCMethod.getFrameTimings.rawValue {
          onFrameTimings(request.arguments)
          return LocalServiceRPCResponse(result: timingsResult, error: nil)
        }
        return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
      }
    )
    try server.start()
    return server
  }

  private func run(
    _ arguments: [String],
    socketPath: String,
    extensionStatus: @escaping @Sendable () -> ExtensionStatus = Self.healthyExtension,
    usb: @escaping @Sendable () async throws -> Int = { 1 },
    drops: @escaping @Sendable (Int32) -> [HIDInputDropObservation] = { _ in [] },
    records: URL = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
  ) async -> CLIRun {
    await RecordStore.$directory.withValue(records) {
      await runDiagnose(
        arguments,
        socketPath: socketPath,
        extensionStatus: extensionStatus,
        usb: usb,
        drops: drops
      )
    }
  }

  private func runDiagnose(
    _ arguments: [String],
    socketPath: String,
    extensionStatus: @escaping @Sendable () -> ExtensionStatus,
    usb: @escaping @Sendable () async throws -> Int,
    drops: @escaping @Sendable (Int32) -> [HIDInputDropObservation]
  ) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await StatusCommand.$extensionProbe.withValue(extensionStatus) {
        await DiagnoseCommand.$usbProbe.withValue(usb) {
          await DiagnoseCommand.$hidDropProbe.withValue(drops) {
            await DiagnoseCommand.$gameControllerAudit.withValue(Self.noAudit) {
              await CLIRun.run(["diagnose"] + arguments + testServerTimeout)
            }
          }
        }
      }
    }
  }

  private func statuses(_ run: CLIRun) throws -> [String: String] {
    let checks = try #require(try run.json()["checks"] as? [[String: String]])
    return Dictionary(uniqueKeysWithValues: checks.map { ($0["id"] ?? "", $0["status"] ?? "") })
  }

  @Test
  func everyCheckPassingExitsZeroAndSkipsOnlyTheSoakAndTheAbsentSwitchPad() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let statuses = try statuses(result)
    #expect(
      statuses.filter { $0.value == "Skip" }.keys.sorted() == [
        "runtime-health", "switch-placeholder-serial",
      ]
    )
    #expect(statuses.values.allSatisfy { $0 == "Pass" || $0 == "Skip" })
    #expect(try result.json()["output"] == nil)
  }

  @Test
  func jsonListsEveryStageTimestampOfTheNewestFrames() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let timings = try #require(try result.json()["timings"] as? [[String: Any]])
    let frames = try #require(timings.first?["frames"] as? [[String: Any]])
    let stages = try #require(frames.first?["stages"] as? [[String: Any]])
    #expect(timings.first?["controller"] as? String == "ctrl-1")
    #expect(
      stages.compactMap { $0["stage"] as? String } == [
        "Read", "Parse", "Dispatch", "DeliveryVirtualDevice", "DeliveryEndpoint",
      ]
    )
    #expect(stages.compactMap { $0["nanoseconds"] as? Int } == [100, 150, 200, 260, 900])
  }

  @Test
  func humanOutputListsDispatchAndDeliveryTimes() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.contains("dispatch=200"))
    #expect(result.standardOutput.contains("delivery-virtual-device=260"))
    #expect(result.standardOutput.contains("delivery-endpoint=900"))
    #expect(result.standardOutput.contains("ctrl-1"))
  }

  @Test
  func aStoppedServiceReportsNoTimings() async throws {
    let result = await run(["--json"], socketPath: temporarySocketPath())

    let timings = try #require(try result.json()["timings"] as? [Any])
    #expect(timings.isEmpty)
  }

  @Test
  func oneFailingCheckExitsOneAndStillPrintsTheTableAndJSON() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath, extensionStatus: Self.brokenExtension)
    let json = await run(["--json"], socketPath: socketPath, extensionStatus: Self.brokenExtension)
    let plain = await run(
      ["--plain"],
      socketPath: socketPath,
      extensionStatus: Self.brokenExtension
    )

    #expect(human.code == 1)
    #expect(human.standardOutput.contains("transport-extension-bundle"))
    #expect(!human.standardError.isEmpty)
    #expect(json.code == 1)
    #expect(try statuses(json)["transport-extension-bundle"] == "Fail")
    #expect(plain.code == 1)
    #expect(plain.standardOutput.contains("transport-extension-bundle\tfail\t"))
  }

  @Test
  func plainListsOneTabSeparatedRowPerRecordedStage() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let plain = await run(["--plain"], socketPath: socketPath)

    let rows = plain.standardOutput.split(separator: "\n").map(String.init)
    #expect(rows.contains("timing\tctrl-1\t4\tread\t100"), "\(rows)")
    #expect(rows.contains("timing\tctrl-1\t4\tdispatch\t200"), "\(rows)")
    #expect(rows.contains("timing\tctrl-1\t4\tdelivery-endpoint\t900"), "\(rows)")
  }

  @Test
  func plainListsTheWindowTheGapsAndTheStallsInAStableColumnOrder() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let plain = await run(["--plain"], socketPath: socketPath)

    let rows = plain.standardOutput.split(separator: "\n").map(String.init)
      .filter { $0.hasPrefix("timing-summary\t") }
    #expect(
      rows == [
        "timing-summary\tctrl-1\twindow\t120\t119000000\t10",
        "timing-summary\tctrl-1\tread-to-parse\t120\t50000\t90000\t120000",
        "timing-summary\tctrl-1\tread-to-read\t119\t1000000\t2500000\t12000000",
        "timing-summary\tctrl-1\tstalls\t3000000\t2",
      ],
      "\(rows)"
    )
  }

  @Test
  func humanOutputIsOneBlockPerControllerWithTheStallRule() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath)

    let lines = result.standardOutput.split(separator: "\n").map(String.init)
    let start = try #require(lines.firstIndex { $0.contains("ctrl-1") && $0.contains("119.000") })
    let block = Array(lines[start...].prefix(4))
    #expect(block.count == 4, "\(lines)")
    #expect(block[0].contains("Pad") && block[0].contains("120"), "\(block)")
    #expect(block[1].contains("read-to-parse") && block[1].contains("0.090"), "\(block)")
    #expect(
      block[2].contains("read-to-read") && block[2].contains("2.500")
        && block[2].contains("12.000"),
      "\(block)"
    )
    #expect(
      block[3].contains("3.000") && block[3].contains("3") && block[3].hasSuffix("2"),
      "\(block)"
    )
  }

  @Test
  func humanOutputOfTheWholeRingSaysThatStallsNeedFrames() async throws {
    let fixture = ControllerFrameTimings.fixture
    let summary = fixture.summary
    let ring = ControllerFrameTimings(
      controller: fixture.controller,
      name: fixture.name,
      frames: fixture.frames,
      summary: FrameTimingSummary(
        lastSeconds: nil,
        frames: summary.frames,
        spanNanoseconds: summary.spanNanoseconds,
        gaps: summary.gaps.filter { $0.gap != .readToRead },
        stalls: nil
      )
    )
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath, timings: ring)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath)

    let needFrames = CLILocalized.text("cli.diagnose.group.timingsSummaryStallsNeedFrames")
    #expect(result.standardOutput.contains(needFrames), "\(result.standardOutput)")
    #expect(!result.standardOutput.contains("read-to-read"))
  }

  @Test
  func jsonCarriesTheSummaryOfEachController() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let timings = try #require(try result.json()["timings"] as? [[String: Any]])
    let summary = try #require(timings.first?["summary"] as? [String: Any])
    #expect(summary["frames"] as? Int == 120)
    #expect(summary["spanNanoseconds"] as? Int == 119_000_000)
    let gaps = try #require(summary["gaps"] as? [[String: Any]])
    #expect(gaps.compactMap { $0["gap"] as? String } == ["ReadToParse", "ReadToRead"])
    #expect(gaps.last?["p50Nanoseconds"] as? Int == 1_000_000)
    #expect(gaps.last?["p99Nanoseconds"] as? Int == 2_500_000)
    #expect(gaps.last?["maxNanoseconds"] as? Int == 12_000_000)
    #expect(gaps.last?["samples"] as? Int == 119)
    let stalls = try #require(summary["stalls"] as? [String: Any])
    #expect(stalls["thresholdNanoseconds"] as? Int == 3_000_000)
    #expect(stalls["count"] as? Int == 2)
  }

  @Test
  func aStoppedServiceSkipsItsChecksAndNeverExits69() async throws {
    let result = await run(["--json"], socketPath: temporarySocketPath())

    #expect(result.code == 0, "\(result.standardError)")
    let statuses = try statuses(result)
    for id in ["input-read", "input-inject", "virtual-device", "hid-input-drops", "runtime-health"]
    {
      #expect(statuses[id] == "Skip", "\(id)")
    }
    #expect(statuses["service"] == "Warn")
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    #expect(checks.first { $0["id"] == "input-inject" }?["detail"]?.isEmpty == false)
  }

  @Test
  func aStoppedServiceStillFailsOnAnotherFailingCheck() async {
    let result = await run(
      ["--plain"],
      socketPath: temporarySocketPath(),
      extensionStatus: Self.brokenExtension
    )

    #expect(result.code == 1)
    #expect(result.standardOutput.contains("input-inject\tskip\t"))
  }

  @Test
  func aFailingUSBScanWarnsButDoesNotFail() async throws {
    struct ScanError: Error {}
    let failingScan: @Sendable () async throws -> Int = { throw ScanError() }
    let result = await run(["--json"], socketPath: temporarySocketPath(), usb: failingScan)

    #expect(result.code == 0)
    #expect(try statuses(result)["usb-access"] == "Warn")
  }

  @Test
  func droppedInputReportsWarnWithoutFailing() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }
    let drops: @Sendable (Int32) -> [HIDInputDropObservation] = { _ in
      [
        HIDInputDropObservation(
          productName: "PLAYSTATION(R)3 Controller",
          vendorID: 0x054C,
          productID: 0x0268,
          droppedReports: 458
        )
      ]
    }
    let result = await run(["--json"], socketPath: socketPath, drops: drops)

    #expect(result.code == 0, "\(result.standardError)")
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    let check = try #require(checks.first { $0["id"] == "hid-input-drops" })
    #expect(check["status"] == "Warn")
    #expect(check["detail"]?.contains("458") == true)
    #expect(check["detail"]?.contains("PLAYSTATION(R)3 Controller") == true)
  }

  @Test
  func noDroppedInputReportsPass() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(try statuses(result)["hid-input-drops"] == "Pass")
  }

  @Test
  func outputWritesAFileAndNamesItInJSON() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("support.json").path

    let result = await run(["--output", path, "--json"], socketPath: temporarySocketPath())

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["output"] as? String == path)
    #expect(FileManager.default.fileExists(atPath: path))
    #expect(result.standardError.contains(path))
  }

  @Test
  func outputReadsTheFiveStageStampsOfTheNewestFrames() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("support.json").path

    let result = await run(["--output", path, "--json"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    let bundle = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
        as? [String: Any]
    )
    let data = try #require(bundle["data"] as? [String: Any])
    let timings = try #require(data["frameTimings"] as? [[String: Any]])
    let frames = try #require(timings.first?["frames"] as? [[String: Any]])
    let stages = try #require(frames.first?["stages"] as? [[String: Any]])
    #expect(timings.first?["controller"] as? String == "ctrl-1")
    #expect(
      stages.compactMap { $0["stage"] as? String } == [
        "Read", "Parse", "Dispatch", "DeliveryVirtualDevice", "DeliveryEndpoint",
      ]
    )
    #expect(stages.compactMap { $0["nanoseconds"] as? Int } == [100, 150, 200, 260, 900])
  }

  @Test
  func outputWithAStoppedServiceHasNoTimings() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("support.json").path

    _ = await run(["--output", path, "--json"], socketPath: temporarySocketPath())

    let bundle = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
        as? [String: Any]
    )
    let data = try #require(bundle["data"] as? [String: Any])
    #expect((data["frameTimings"] as? [Any])?.isEmpty == true)
  }

  @Test
  func aMissingBundleParentIsAUsageError() async {
    let path = "/tmp/\(UUID().uuidString)/missing/support.json"

    let result = await run(["--output", path], socketPath: temporarySocketPath())

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: path))
  }

  @Test
  func badSoakValuesAreUsageErrors() async {
    let socketPath = temporarySocketPath()
    for arguments in [
      ["--soak", "0"], ["--soak", "86401"], ["--soak", "abc"],
      ["--soak", "5", "--interval-ms", "10"], ["--soak", "5", "--footprint-limit-mib", "-1"],
      ["--soak", "86400", "--interval-ms", "100"],
    ] {
      let result = await run(arguments, socketPath: socketPath)
      #expect(result.code == 64, "\(arguments)")
      #expect(result.standardOutput.isEmpty, "\(arguments)")
    }
  }

  @Test
  func badFramesValuesAreUsageErrors() async {
    let socketPath = temporarySocketPath()
    for value in ["0", "16", "-1", "abc"] {
      let result = await DiagnoseCommand.$frameWindowWait.withValue(
        { _ in },
        operation: { await run(["--frames", value], socketPath: socketPath) }
      )
      #expect(result.code == 64, "\(value)")
      #expect(result.standardOutput.isEmpty, "\(value)")
    }
  }

  @Test
  func framesWaitThenAskForOneSnapshotOfThatManySeconds() async throws {
    let socketPath = temporarySocketPath()
    let events = Locked<[String]>([])
    let server = try serve(socketPath: socketPath) { arguments in
      let seconds =
        (try? JSONDecoder().decode(LocalServiceRPCFrameTimingsArguments.self, from: arguments))?
        .lastSeconds
      events.withLock { $0.append("request \(seconds.map(String.init) ?? "nil")") }
    }
    defer { server.stop() }

    let result = await DiagnoseCommand.$frameWindowWait.withValue(
      { seconds in events.withLock { $0.append("wait \(seconds)") } },
      operation: { await run(["--frames", "10"], socketPath: socketPath) }
    )

    #expect(result.code == 0, "\(result.standardError)")
    #expect(events.withLock { $0 } == ["wait 10", "request 10"])
    #expect(
      result.standardError.contains(
        CLILocalized.format("cli.diagnose.group.framesProgress", Double(10).durationText)
      )
    )
    #expect(
      result.standardOutput.contains(
        CLILocalized.format("cli.diagnose.group.timingsWindow", Double(10).durationText)
      )
    )
  }

  @Test
  func withoutFramesTheRequestCoversTheWholeRingAndNothingWaits() async throws {
    let socketPath = temporarySocketPath()
    let requests = Locked<[Int?]>([])
    let server = try serve(socketPath: socketPath) { arguments in
      let decoded = try? JSONDecoder().decode(
        LocalServiceRPCFrameTimingsArguments.self,
        from: arguments
      )
      requests.withLock { $0.append(decoded?.lastSeconds) }
    }
    defer { server.stop() }

    let result = await DiagnoseCommand.$frameWindowWait.withValue(
      { _ in Issue.record("diagnose waited without --frames") },
      operation: { await run([], socketPath: socketPath) }
    )

    #expect(result.code == 0, "\(result.standardError)")
    #expect(requests.withLock { $0 } == [nil])
    #expect(!result.standardOutput.contains("Timing window"))
  }

  @Test
  func soakAddsARuntimeHealthCheckThatSamplesTheService() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath)
    defer { server.stop() }
    let recorded = Locked<[Int]>([])

    let sampler:
      @Sendable (Int32, Int, Int, RuntimeHealthPolicy) async throws -> RuntimeHealthSummary = {
        _,
        seconds,
        interval,
        _ in
        recorded.withLock { $0 = [seconds, interval] }
        throw RuntimeHealthSamplingError.invalidConfiguration
      }

    let result = await DiagnoseCommand.$soakSampler.withValue(sampler) {
      await run(["--soak", "7", "--interval-ms", "250", "--json"], socketPath: socketPath)
    }

    #expect(recorded.withLock { $0 } == [7, 250])
    #expect(try statuses(result)["runtime-health"] == "Fail")
    #expect(result.code == 1)
  }

  @Test
  func aSkippedControllerRecordWarnsButDoesNotFail() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-diagnose-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{".utf8).write(to: directory.appendingPathComponent("broken.plist"))

    let result = await run(["--json"], socketPath: temporarySocketPath(), records: directory)

    #expect(result.code == 0)
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    let records = try #require(checks.first { $0["id"] == "controller-records" })
    #expect(records["status"] == "Warn")
    #expect(
      records["detail"]?.contains("broken.plist (broken.plist is not an XML property list)")
        == true
    )
  }

  @Test
  func anIgnoredDefaultsFileOrSkippedVirtualDeviceWarnsButDoesNotFail() async throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-diagnose-\(UUID().uuidString)",
      isDirectory: true
    )
    let devices = support.appendingPathComponent("VirtualDevices", isDirectory: true)
    try FileManager.default.createDirectory(
      at: support.appendingPathComponent("Controllers"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    try Data("{".utf8).write(to: support.appendingPathComponent("Controllers/all.patch.plist"))
    try Data("{".utf8).write(to: devices.appendingPathComponent("broken.plist"))

    let result = await run(
      ["--json"],
      socketPath: temporarySocketPath(),
      records: support.appendingPathComponent("Controllers")
    )

    #expect(result.code == 0)
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    let config = try #require(checks.first { $0["id"] == "config-files" })
    #expect(config["status"] == "Warn")
    #expect(
      config["detail"]?.contains("all.patch.plist (all.patch.plist is not an XML property list)")
        == true
    )
    #expect(
      config["detail"]?.contains("broken.plist (virtual device is not an XML property list)")
        == true
    )
    let clean = await run(["--json"], socketPath: temporarySocketPath())
    let cleanChecks = try #require(try clean.json()["checks"] as? [[String: String]])
    #expect(cleanChecks.first { $0["id"] == "config-files" }?["status"] == "Pass")
  }

  @Test
  func aPersonasFolderWarnsButDoesNotFail() async throws {
    let support = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-diagnose-\(UUID().uuidString)",
      isDirectory: true
    )
    let unread = support.appendingPathComponent("Personas", isDirectory: true)
    try FileManager.default.createDirectory(at: unread, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: support) }
    try PropertyListFixture.data(json: "{}").write(
      to: unread.appendingPathComponent("1209-0001.plist")
    )

    let result = await run(
      ["--json"],
      socketPath: temporarySocketPath(),
      records: support.appendingPathComponent("Controllers")
    )

    #expect(result.code == 0)
    let checks = try #require(try result.json()["checks"] as? [[String: String]])
    let config = try #require(checks.first { $0["id"] == "config-files" })
    #expect(config["status"] == "Warn")
    let devices = support.appendingPathComponent("VirtualDevices").path
    #expect(config["detail"]?.contains("Personas (") == true, "\(config)")
    #expect(config["detail"]?.contains(devices) == true, "\(config)")
  }
}
