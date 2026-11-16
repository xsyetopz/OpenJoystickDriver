import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// Runs `Scripts/SDK/reference_client.py`, the client that the repository ships, against a real
/// ``EndpointServer`` on a Unix socket.
@Suite(.serialized)
struct EndpointReferenceClientTests {
  private static let client = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // Endpoint
    .deletingLastPathComponent()  // Runtime
    .deletingLastPathComponent()  // OpenJoystickDriverServiceTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // repository root
    .appendingPathComponent("Scripts/SDK/reference_client.py").path

  @Test
  func clientSubscribesAndReceivesControllerFrame() async throws {
    try await withEndpointServer(identity: nil) { server, fixture in
      fixture.source.set(devices: ["pad-1"], state: ControllerState(pressed: [.south]))
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "driver", origins: [], scopes: [.read])

      let result = await Self.run(
        ["--socket", server.socketPath, "watch", "--count", "2"],
        token: granted.token
      )

      #expect(result.status == 0, "\(result.error)")
      let lines = result.output.split(separator: "\n").map(String.init)
      #expect(lines.count == 2)
      for line in lines {
        #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
      }
      let objects = try lines.map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
      }
      #expect(objects.first?["type"] as? String == "ADDED")
      let pressed = objects.compactMap {
        (($0["object"] as? [String: Any])?["input"] as? [String: Any])?["pressed"] as? [String]
      }
      #expect(pressed == [["South"]])
    }
  }

  @Test
  func clientFeedsFrameToVirtualGamepad() async throws {
    let factory = FakeFeedFactory()
    try await withEndpointServer(identity: nil, feeds: factory.registry()) { server, _ in
      try server.setEnabled(true)
      let granted = try server.grantToken(name: "driver", origins: [], scopes: [.control])

      let result = await Self.run(["--socket", server.socketPath, "feed"], token: granted.token)

      #expect(result.status == 0, "\(result.error)")
      let device = try #require(factory.devices.first)
      #expect(device.profile == .generic)
      #expect(device.sent.contains { $0.buttons.contains(.south) })
    }
  }

  @Test
  func clientWithWrongTokenExitsWithEndpointsError() async throws {
    try await withEndpointServer(identity: nil) { server, _ in
      try server.setEnabled(true)
      _ = try server.grantToken(name: "driver", origins: [], scopes: [.read])

      let result = await Self.run(
        ["--socket", server.socketPath, "watch"],
        token: "ojd_wrong"
      )

      #expect(result.status != 0)
      #expect(result.error.contains("E1002"))
    }
  }

  private struct Result: Sendable {
    let status: Int32
    let output: String
    let error: String
  }

  /// Runs the client off the cooperative pool, so the server's tasks keep running.
  private static func run(_ arguments: [String], token: String) async -> Result {
    let searchPath = "/usr/bin:/bin:/usr/local/bin"
    guard
      searchPath.split(separator: ":").contains(where: {
        FileManager.default.isExecutableFile(atPath: "\($0)/python3")
      })
    else {
      return Result(
        status: -1,
        output: "",
        error: "The reference client needs python3, and none is in \(searchPath)."
      )
    }
    return await offPool {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["python3", "-I", client] + arguments
      process.environment = ["OJD_TOKEN": token, "PATH": searchPath]
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString,
        isDirectory: true
      )
      defer { try? FileManager.default.removeItem(at: directory) }
      let outputURL = directory.appendingPathComponent("output")
      let errorURL = directory.appendingPathComponent("error")
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in [outputURL, errorURL] {
          FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        process.standardOutput = try FileHandle(forWritingTo: outputURL)
        process.standardError = try FileHandle(forWritingTo: errorURL)
        try process.run()
      } catch {
        return Result(status: -1, output: "", error: "\(error)")
      }
      process.waitUntilExit()
      return Result(
        status: process.terminationStatus,
        output: (try? String(contentsOf: outputURL, encoding: .utf8)) ?? "",
        error: (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
      )
    }
  }
}
