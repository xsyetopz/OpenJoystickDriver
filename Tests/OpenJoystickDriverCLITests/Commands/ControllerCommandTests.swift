import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ControllerCommandTests {
  private static func delivered(dropping dropped: [PhysicalRumbleMotor] = []) -> FakeService.Respond
  {
    { method, _ in
      method == .sendControllerOutput
        ? encoded(ControllerOutputResult(.delivered, droppedRumbleChannels: dropped)) : nil
    }
  }

  private static func sentCommands(_ service: FakeService) throws -> [ControllerOutputCommand] {
    try service.arguments(of: .sendControllerOutput).map {
      try JSONDecoder().decode(LocalServiceRPCControllerOutputArguments.self, from: $0).command
    }
  }

  @Test
  func listPrintsEachControllerInJSONAndPlainRows() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let jsonRun = await service.run(["controller", "list", "--json"])
    let plainRun = await service.run(["controller", "list", "--plain"])

    #expect(jsonRun.code == 0, "\(jsonRun.standardError)")
    let controllers = try #require(try jsonRun.json()["controllers"] as? [[String: Any]])
    #expect(controllers.map { $0["id"] as? String } == ["pad-1"])
    #expect(plainRun.code == 0, "\(plainRun.standardError)")
    let row = plainRun.standardOutput.split(separator: "\t").map(String.init)
    #expect(row.prefix(2) == ["pad-1", "045E:028E"])
  }

  @Test
  func anUnknownSelectorFailsAndListsTheConnectedControllers() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let result = await service.run(["controller", "show", "pad-9"])
    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("'pad-9'"))
    #expect(result.standardError.contains("pad-1  045E:028E  Test Pad"))
  }

  @Test
  func aModelSelectorMatchingTwoControllersFailsAndListsBoth() async throws {
    let service = try FakeService(devices: [
      FakeService.device(id: "pad-1", outputs: .dualMainRumble),
      FakeService.device(id: "pad-2", outputs: .dualMainRumble),
    ])
    let result = await service.run(["controller", "show", "045e:028e"])
    #expect(result.code == 1)
    #expect(result.standardError.contains("pad-1"))
    #expect(result.standardError.contains("pad-2"))
  }

  @Test
  func aModelSelectorMatchingOneControllerResolvesIt() async throws {
    let service = try FakeService(
      devices: [
        FakeService.device(id: "pad-1"),
        FakeService.device(id: "pad-2", vendorID: 0x054C, productID: 0x0CE6),
      ],
      respond: Self.delivered()
    )
    let result = await service.run(["controller", "player", "054C:0CE6", "2", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["controller"] as? String == "pad-2")
    let arguments = try #require(service.arguments(of: .sendControllerOutput).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCControllerOutputArguments.self,
      from: arguments
    )
    #expect(sent.runtimeIdentifier == "pad-2")
  }

  @Test
  func rumbleWarnsAboutAMissingTriggerMotorAndSucceedsWhenAMainMotorRan() async throws {
    let service = try FakeService(
      devices: [FakeService.device(id: "pad-1")],
      respond: Self.delivered(dropping: [.leftTrigger, .leftHaptic, .rightHaptic])
    )
    let result = await service.run([
      "controller", "rumble", "pad-1", "--left", "100", "--left-trigger", "100",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardError.contains("warning:"))
    #expect(result.standardError.contains("has no left-trigger motor"))
    #expect(result.standardError.contains("Rumbled left-main on"))
    #expect(!result.standardError.contains("aptic"))
    guard case .setRumble(let intensities, _) = try Self.sentCommands(service).first else {
      Issue.record("expected setRumble")
      return
    }
    #expect(intensities.leftMain == UnipolarValue(byte: 100))
    #expect(intensities.leftHaptic == UnipolarValue(byte: 100))
  }

  @Test
  func playerNamesTheControllerLikeTheOtherOutputMessages() async throws {
    let service = try FakeService(
      devices: [FakeService.device(id: "pad-1")],
      respond: Self.delivered()
    )
    let result = await service.run(["controller", "player", "pad-1", "1"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardError.contains("Sent player to Test Pad."))
  }

  @Test
  func rumbleFailsWhenNoRequestedMotorRan() async throws {
    let service = try FakeService(
      devices: [FakeService.device(id: "pad-1")],
      respond: Self.delivered(dropping: [.leftTrigger])
    )
    let result = await service.run(["controller", "rumble", "pad-1", "--left-trigger", "100"])
    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func rumbleWithEveryIntensityAtZeroStopsTheMotors() async throws {
    let service = try FakeService(
      devices: [FakeService.device(id: "pad-1")],
      respond: Self.delivered()
    )
    let result = await service.run(["controller", "rumble", "pad-1", "--left", "0", "--right", "0"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try Self.sentCommands(service) == [.stopRumble])
  }

  @Test
  func anUnsupportedOutputFailsWithExitOne() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      method == .sendControllerOutput
        ? encoded(ControllerOutputResult(.unsupportedCapability)) : nil
    }
    let result = await service.run(["controller", "light", "pad-1", "--color", "#00FF00"])
    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func watchFirstPressPrintsTheFirstNewlyPressedControl() async throws {
    let reads = Counter()
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      guard method == .getControllerState else { return nil }
      // A control held at the start does not count; face-south is the new press.
      let state =
        reads.next() < 2
        ? ControllerState(pressed: [.menu]) : ControllerState(pressed: [.menu, .faceSouth])
      return doubleEncoded(state)
    }
    let result = await service.run([
      "controller", "watch", "pad-1", "--first-press", "--duration", "3", "--json",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["control"] as? String == "face-south")
  }

  @Test
  func watchFirstPressFailsWhenTheDurationPassesFirst() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      method == .getControllerState ? doubleEncoded(ControllerState.neutral) : nil
    }
    let result = await service.run([
      "controller", "watch", "pad-1", "--first-press", "--duration", "0.2",
    ])
    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains(0.2.durationText))
  }

  @Test
  func suspendingASuspendedControllerSucceedsWithoutAChange() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      method == .suspendController
        ? doubleEncoded(ControllerSuspendResult(state: .suspended, failure: .alreadySuspended))
        : nil
    }
    let result = await service.run(["controller", "suspend", "pad-1", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["session"] as? String == "suspended")
    #expect(json["changed"] as? Bool == false)
  }

  @Test
  func showPrintsTheControllerReport() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let result = await service.run(["controller", "show", "pad-1", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let controller = try #require(try result.json()["controller"] as? [String: Any])
    #expect(controller["id"] as? String == "pad-1")
  }

  @Test
  func showLabelsOwnershipInTheSameStyleAsTheOtherValues() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let result = await service.run(["controller", "show", "pad-1"])
    #expect(result.code == 0, "\(result.standardError)")
    let ownership = result.standardOutput.split(separator: "\n").first { $0.hasPrefix("Ownership") }
    #expect(ownership?.hasSuffix("  route raw-usb, physical unknown, HID input unknown") == true)
  }

  @Test
  func outputChecksNameTheControllerByIDWhenAnotherSharesItsModel() async throws {
    let service = try FakeService(devices: [
      FakeService.device(id: "pad-1", outputs: .dualMainRumble),
      FakeService.device(id: "pad-2", outputs: .dualMainRumble),
    ])
    let shared = await service.run(["controller", "show", "pad-2", "--json"])
    #expect(shared.code == 0, "\(shared.standardError)")
    #expect(shared.standardOutput.contains("ojd controller rumble pad-2 "))
    #expect(!shared.standardOutput.contains("045E:028E --"))
    let alone = try FakeService(devices: [
      FakeService.device(id: "pad-1", outputs: .dualMainRumble)
    ])
    let single = await alone.run(["controller", "show", "pad-1", "--json"])
    #expect(single.standardOutput.contains("ojd controller rumble 045E:028E "))
  }

  @Test(arguments: [
    ("exclusiveRawUSB", "exclusive-raw-usb"), ("leftMain", "left-main"), ("raw-usb", "raw-usb"),
    ("playerIndicator", "player-indicator"), ("driverKitOwnedUSB", "driver-kit-owned-usb"),
  ])
  func kebabCaseMatchesTheControlNames(value: String, expected: String) {
    #expect(ControllerShowCommand.kebabCase(value) == expected)
  }

  /// `controller show` for a `366C:0005` pad, with the user directory holding `userRecord` if any.
  private static func show(
    _ flags: [String],
    userRecord: Data? = nil,
    vendorID: UInt16 = 0x366C,
    productID: UInt16 = 0x0005
  ) async throws -> (result: CLIRun, file: String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-show-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("366c-0005.json")
    if let userRecord {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try userRecord.write(to: file)
    }
    let service = try FakeService(devices: [
      FakeService.device(id: "pad-1", vendorID: vendorID, productID: productID)
    ])
    let result = await RecordStore.$directory.withValue(directory) {
      await service.run(["controller", "show", "pad-1"] + flags)
    }
    return (result, "\(directory.lastPathComponent)/366c-0005.json")
  }

  /// The value of the `Record` row of the human `controller show` output.
  private static func recordRow(_ result: CLIRun) -> String? {
    result.standardOutput.split(separator: "\n").first { $0.hasPrefix("Record ") }
      .map { $0.dropFirst("Record".count).trimmingCharacters(in: .whitespaces) }
  }

  private static let userPatch = Data(
    """
    {"$schema": "\(ControllerRecordSet.overrideSchemaID)", "operation": "patch",
     "vendorID": 13932, "productID": 5, "set": {"usb": {"postHandshakeSettleMs": 5}}}
    """.utf8
  )

  @Test
  func showReportsABundledRecord() async throws {
    let json = try await Self.show(["--json"])
    let human = try await Self.show([])
    let plain = try await Self.show(["--plain"])

    #expect(json.result.code == 0, "\(json.result.standardError)")
    let controller = try #require(try json.result.json()["controller"] as? [String: Any])
    #expect(controller["record"] as? [String: String] == ["layer": "bundled"])
    #expect(Self.recordRow(human.result) == "bundled")
    #expect(plain.result.standardOutput.contains("record\tbundled\t\n"))
  }

  @Test
  func showReportsAUserRecordAndItsFile() async throws {
    let json = try await Self.show(["--json"], userRecord: Self.userPatch)
    let human = try await Self.show([], userRecord: Self.userPatch)
    let plain = try await Self.show(["--plain"], userRecord: Self.userPatch)

    #expect(json.result.code == 0, "\(json.result.standardError)")
    let controller = try #require(try json.result.json()["controller"] as? [String: Any])
    #expect((controller["record"] as? [String: String])?.keys.sorted() == ["file", "layer"])
    #expect((controller["record"] as? [String: String])?["layer"] == "user")
    #expect((controller["record"] as? [String: String])?["file"]?.hasSuffix(json.file) == true)
    #expect(Self.recordRow(human.result)?.hasPrefix("your record, /") == true)
    #expect(Self.recordRow(human.result)?.hasSuffix(human.file) == true)
    #expect(plain.result.standardOutput.contains("record\tuser\t/"))
    #expect(plain.result.standardOutput.contains("\(plain.file)\n"))
  }

  @Test
  func showReportsWhenNoRecordMatches() async throws {
    let json = try await Self.show(["--json"], vendorID: 0x1234, productID: 0x5678)
    let human = try await Self.show([], vendorID: 0x1234, productID: 0x5678)
    let plain = try await Self.show(["--plain"], vendorID: 0x1234, productID: 0x5678)

    #expect(json.result.code == 0, "\(json.result.standardError)")
    let controller = try #require(try json.result.json()["controller"] as? [String: Any])
    #expect(controller["record"] == nil)
    #expect(Self.recordRow(human.result) == "none (no record matches)")
    #expect(plain.result.standardOutput.contains("record\tnone\t\n"))
  }

  @Test(arguments: [
    ["controller", "rumble", "pad-1", "--left", "100"],
    ["controller", "light", "pad-1", "--color", "#00FF00"],
  ])
  func outputCommandsReportEachDeliveredCommand(arguments: [String]) async throws {
    let service = try FakeService(
      devices: [FakeService.device(id: "pad-1")],
      respond: Self.delivered()
    )
    let result = await service.run(arguments + ["--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let results = try #require(try result.json()["results"] as? [[String: Any]])
    #expect(results.allSatisfy { $0["outcome"] as? String == "delivered" })
  }

  @Test
  func resumeAndDisconnectReportTheSession() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      switch method {
      case .resumeController: doubleEncoded(ControllerResumeResult(state: .active))
      case .disconnectWirelessController:
        doubleEncoded(WirelessControllerDisconnectResult(state: .active))
      default: nil
      }
    }
    let resume = await service.run(["controller", "resume", "pad-1", "--json"])
    let disconnect = await service.run(["controller", "disconnect", "pad-1", "--json"])
    #expect(resume.code == 0, "\(resume.standardError)")
    #expect(try resume.json()["session"] as? String == "active")
    #expect(disconnect.code == 0, "\(disconnect.standardError)")
    #expect(try disconnect.json()["session"] as? String == "disconnected")
  }

  @Test
  func capturePrintsEachNewPacketAsAJSONLine() async throws {
    let reads = Counter()
    let packet = #"{"direction":"rx","hex":"01 02","length":2,"timestamp":1.5}"#
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      guard method == .getPacketLog else { return nil }
      return encoded(Data((reads.next() == 0 ? "[]" : "[\(packet)]").utf8))
    }
    let result = await service.run([
      "controller", "capture", "pad-1", "--duration", "0.3", "--json",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput == packet + "\n")
  }

  @Test
  func watchPrintsTheStateAsJSONLines() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      method == .getControllerState ? doubleEncoded(ControllerState(pressed: [.faceSouth])) : nil
    }
    let result = await service.run(["controller", "watch", "pad-1", "--duration", "0.2", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(!result.standardOutput.isEmpty)
  }

  @Test(arguments: [
    ["controller", "rumble", "pad-1", "--duration", "9"], ["controller", "player", "pad-1", "7"],
    ["controller", "light", "pad-1"], ["controller", "light", "pad-1", "--color", "red"],
    ["controller", "watch", "pad-1", "--duration", "0"],
  ])
  func invalidOperandsExitSixtyFourBeforeAnyRequest(arguments: [String]) async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let result = await service.run(arguments)
    #expect(result.code == 64, "\(arguments)")
    #expect(service.arguments(of: .getStatus).isEmpty)
  }
}

/// A thread-safe count of calls.
final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  /// The number of earlier calls.
  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }
}
