import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct EndpointOutputTests {
  /// A client granted `scopes`, welcomed with them.
  private func welcomed(
    _ server: EndpointServer,
    scopes: [EndpointScope] = [.control]
  ) async throws -> EndpointTestClient {
    try server.setEnabled(true)
    try server.grant(EndpointFixture.tool, path: "/Tool", scopes: scopes)
    let client = try await EndpointTestClient(path: server.socketPath)
    let names = scopes.map { #""\#($0.rawValue)""# }.joined(separator: ",")
    await client.send(clientLine("Hello", #","scopes":[\#(names)]"#))
    #expect(try await client.readObject()["kind"] as? String == "Welcome")
    return client
  }

  /// The next line, which must satisfy the schema.
  private func schemaLine(_ client: EndpointTestClient) async throws -> [String: Any] {
    let line = try #require(await client.readLine())
    #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    return try client.object(line)
  }

  private func automation() -> FakeAutomation {
    let automation = FakeAutomation()
    automation.devices = [.fixture(id: "A", name: "Pad A", unit: "P")]
    return automation
  }

  /// The members of an `OutputRequest` for the controller `A`.
  private func request(_ members: String, controller: String = token("A")) -> String {
    clientLine("OutputRequest", #","controller":"\#(controller)",\#(members)"#)
  }

  @Test
  func aRumbleRequestRunsTheMotorsAndTheConnectionStaysOpen() async throws {
    let automation = automation()
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)

      await client.send(request(#""action":"Rumble","left":200,"duration":1.5"#))
      let answer = try await schemaLine(client)
      #expect(answer["kind"] as? String == "OutputResult", "\(answer)")
      #expect(answer["controller"] as? String == token("A"))
      let results = try #require(answer["results"] as? [[String: Any]])
      #expect(results.map { $0["command"] as? String } == ["rumble"])
      #expect(results.map { $0["outcome"] as? String } == ["Delivered"])
      guard case .setRumble(let intensities, let duration)? = automation.sentOutputs.first else {
        Issue.record("no rumble command: \(automation.sentOutputs)")
        return
      }
      #expect(intensities.lowFrequency == UnipolarValue(byte: 200))
      #expect(intensities.highFrequency == .min)
      #expect(duration == .milliseconds(1500))

      await client.send(request(#""action":"Player","player":2"#))
      #expect(try await schemaLine(client)["kind"] as? String == "OutputResult")
      #expect(automation.sentOutputs.last == .setPlayerIndicator(.player2))
    }
  }

  @Test
  func aRumbleRequestThatNamesNoMotorRunsBothMainMotorsAtTheDefault() async throws {
    let automation = automation()
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)
      await client.send(request(#""action":"Rumble""#, controller: "045E:028E"))
      #expect(try await schemaLine(client)["kind"] as? String == "OutputResult")
      guard case .setRumble(let intensities, let duration)? = automation.sentOutputs.first else {
        Issue.record("no rumble command: \(automation.sentOutputs)")
        return
      }
      #expect(intensities.lowFrequency == UnipolarValue(byte: 180))
      #expect(intensities.highFrequency == UnipolarValue(byte: 180))
      #expect(duration == .milliseconds(450))
    }
  }

  @Test
  func aRumbleRequestOfZeroIntensityStopsTheRumble() async throws {
    let automation = automation()
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)
      await client.send(request(#""action":"Rumble","left":0,"right":0"#))
      #expect(try await schemaLine(client)["kind"] as? String == "OutputResult")
      #expect(automation.sentOutputs == [.stopRumble])
    }
  }

  @Test
  func aLightRequestSendsTheColorThenTheBrightness() async throws {
    let automation = automation()
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)
      await client.send(request(##""action":"Light","color":"#FF8000","brightness":9"##))
      let answer = try await schemaLine(client)
      let results = try #require(answer["results"] as? [[String: Any]])
      #expect(results.map { $0["command"] as? String } == ["color", "brightness"])
      #expect(
        automation.sentOutputs == [
          .setRGB(ControllerColor(red: 255, green: 128, blue: 0)),
          .setLightBrightness(UnipolarValue(byte: 9)),
        ]
      )
    }
  }

  @Test
  func anOutputTheControllerLacksIsRefusedWithTheCodeOjdPrintsAndTheConnectionStaysOpen()
    async throws
  {
    let automation = automation()
    automation.outputOutcome = .unsupportedCapability
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)
      await client.send(request(#""action":"Light","color":"FF8000""#))
      let refusal = try await schemaLine(client)
      #expect(refusal["kind"] as? String == "Status")
      #expect(refusal["code"] as? String == ErrorCode.controllerRequestFailed.rawValue)
      #expect((refusal["message"] as? String)?.contains("Pad A") == true)

      automation.outputOutcome = .delivered
      await client.send(request(#""action":"Player","player":0"#))
      #expect(try await schemaLine(client)["kind"] as? String == "OutputResult")
    }
  }

  @Test
  func eachOutcomeThatDoesNotDeliverIsRefusedWithTheControllerRequestFailedCode() async throws {
    for outcome in [
      ControllerOutputResult.Outcome.notReady, .notFound, .invalidValue, .writeFailed, .cancelled,
    ] {
      let automation = automation()
      automation.outputOutcome = outcome
      try await withEndpointServer(automation: automation) { server, _ in
        let client = try await welcomed(server)
        await client.send(request(#""action":"Player","player":1"#))
        #expect(
          try await schemaLine(client)["code"] as? String
            == ErrorCode.controllerRequestFailed.rawValue,
          "\(outcome)"
        )
      }
    }
  }

  @Test
  func aRumbleThatNoMotorOfTheControllerRanIsRefused() async throws {
    let automation = automation()
    automation.outputOutcome = .delivered
    automation.droppedChannels = [.lowFrequency, .highFrequency, .leftHaptic, .rightHaptic]
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)
      await client.send(request(#""action":"Rumble","left":9"#))
      #expect(
        try await schemaLine(client)["code"] as? String
          == ErrorCode.controllerRequestFailed.rawValue
      )
    }
  }

  @Test
  func anUnknownOrAmbiguousControllerIsRefusedWithNotFound() async throws {
    let automation = automation()
    automation.devices.append(.fixture(id: "B", name: "Pad B", unit: "Q"))
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)
      for controller in [token("Z"), "045E:028E", "not a controller", "FFFF:FFFF"] {
        await client.send(request(#""action":"Player","player":1"#, controller: controller))
        #expect(
          try await schemaLine(client)["code"] as? String == ErrorCode.notFound.rawValue,
          "\(controller)"
        )
      }
      #expect(automation.sentOutputs.isEmpty)
    }
  }

  @Test
  func anOutputRequestNeedsTheControlScope() async throws {
    let automation = automation()
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server, scopes: [.read])
      await client.send(request(#""action":"Player","player":1"#))
      #expect(try await schemaLine(client)["code"] as? String == ErrorCode.notGranted.rawValue)
      #expect(await client.readLine() == nil)
      #expect(automation.sentOutputs.isEmpty)
    }
  }

  @Test
  func aMalformedOutputRequestEndsTheConnectionWithInvalidMessage() async throws {
    let members = [
      #""action":"Speaker""#,
      #""action":"rumble""#,
      #""action":"Rumble","left":256"#,
      #""action":"Rumble","left":-1"#,
      #""action":"Rumble","duration":0"#,
      #""action":"Rumble","duration":5.01"#,
      #""action":"Rumble","duration":"1""#,
      #""action":"Player""#,
      #""action":"Player","player":5"#,
      #""action":"Light""#,
      #""action":"Light","color":"FF80""#,
      #""action":"Light","color":"GG8000""#,
      #""action":"Light","brightness":256"#,
    ]
    for member in members {
      let automation = automation()
      try await withEndpointServer(automation: automation) { server, _ in
        let client = try await welcomed(server)
        await client.send(request(member))
        #expect(
          try await schemaLine(client)["code"] as? String == ErrorCode.invalidMessage.rawValue,
          "\(member)"
        )
        #expect(await client.readLine() == nil, "\(member)")
        #expect(automation.sentOutputs.isEmpty, "\(member)")
      }
    }
  }

  @Test
  func anOutputRequestWithoutAControllerEndsTheConnection() async throws {
    try await withEndpointServer(automation: automation()) { server, _ in
      let client = try await welcomed(server)
      await client.send(clientLine("OutputRequest", #","action":"Player","player":1"#))
      #expect(
        try await schemaLine(client)["code"] as? String == ErrorCode.invalidMessage.rawValue
      )
    }
  }
}
