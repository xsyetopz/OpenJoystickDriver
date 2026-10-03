import Darwin
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

/// Runs `ojd` with standard input from `/dev/null`, as a script or a pipeline does.
@Suite(.serialized)
struct StandardInputTests {
  /// Leaves the sweep skips, because they act on the system instead of the fake service.
  private static let systemCommands: Set<[String]> = [
    ["service", "start"], ["service", "stop"], ["extension", "activate"],
    ["extension", "deactivate"], ["update", "check"], ["log", "show"], ["log", "export"],
    ["controller", "watch"], ["diagnose"],
  ]

  /// A patch of the bundled `xbox.gip` record `366C:0005`.
  private static let patch = Data(
    """
    {"$schema": "\(ControllerRecordSet.overrideSchemaID)", "operation": "patch",
     "vendorID": 13932, "productID": 5, "set": {"usb": {"postHandshakeSettleMs": 5}}}
    """.utf8
  )

  @Test(.timeLimit(.minutes(2)))
  func noCommandPromptsAndEveryConfirmationNeedsForce() async throws {
    let binding = RemappingBinding(
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: [])
    )
    let library = FakeProfileLibrary([FakeProfileLibrary.profile("Pad", bindings: [binding])])
    let service = try FakeService(devices: [], respond: library.respond)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-stdin-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Self.patch.write(to: directory.appendingPathComponent("366c-0005.json"))

    let leaves = CLICommandTree.leafPaths.filter { !Self.systemCommands.contains($0) }
      .map { $0 + CLICommandTree.sampleOperands(for: $0) }
    let gated = [
      ["profile", "delete", "Pad"], ["binding", "clear", "Pad", "--all"],
      ["record", "remove", "366C:0005"], ["virtual", "reset", "--all"],
      ["profile", "edit", "Pad"],
    ]
    try await Self.withStandardInputFromNull {
      for arguments in gated {
        let result = await RecordStore.$directory.withValue(directory) {
          await service.run(arguments)
        }
        let text = "ojd \(arguments.joined(separator: " ")): \(result.standardError)"
        #expect(result.code == 64, "\(text)")
        #expect(!result.standardError.contains("[y/N]"), "\(text)")
        #expect(
          result.standardError.contains("--force") || result.standardError.contains("terminal"),
          "\(text)"
        )
      }
      #expect(library.stored.map(\.bindings) == [[binding]])
      let records = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      #expect(records == ["366c-0005.json"])
      for arguments in leaves {
        let result = await RecordStore.$directory.withValue(directory) {
          await service.run(arguments)
        }
        #expect(!result.standardError.contains("[y/N]"), "ojd \(arguments.joined(separator: " "))")
      }
    }
  }

  /// Points file descriptor 0 at `/dev/null` for `body`, then restores it.
  private static func withStandardInputFromNull(
    _ body: () async throws -> Void
  ) async throws {
    let saved = dup(STDIN_FILENO)
    let null = open("/dev/null", O_RDONLY)
    try #require(saved >= 0 && null >= 0)
    dup2(null, STDIN_FILENO)
    close(null)
    defer {
      dup2(saved, STDIN_FILENO)
      close(saved)
    }
    try await body()
  }
}
