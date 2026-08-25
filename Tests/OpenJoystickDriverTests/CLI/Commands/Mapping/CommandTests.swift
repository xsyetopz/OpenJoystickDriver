import Foundation
import Testing

@testable import OpenJoystickDriver
@testable import OpenJoystickDriverKit

@Suite(.serialized) struct MappingCommandTests {
  @Test(arguments: [
    ("button:south", RemappingSource.button(.south)), ("dpad:left", RemappingSource.dpad(.left)),
    ("axis:left_stick_x", RemappingSource.axis(.leftStickX)),
    ("axis:right_trigger:positive", RemappingSource.axisDirection(.rightTrigger, .positive))
  ]) func parsesEverySourceFamily(raw: String, expected: RemappingSource) throws {
    #expect(try MappingSyntax.source(raw) == expected)
  }

  @Test(arguments: [
    ("key:a", RemappingDestination.keyboard(key: .a, modifiers: [])),
    ("mouse:forward", RemappingDestination.mouseButton(.forward)),
    ("move:x", RemappingDestination.mouseMovement(.x)),
    ("scroll:y", RemappingDestination.scroll(.y))
  ]) func parsesEveryDestinationFamily(raw: String, expected: RemappingDestination) throws {
    #expect(try MappingSyntax.destination(raw) == expected)
  }

  @Test func parsesAndCanonicallyRendersModifiers() throws {
    let destination = try MappingSyntax.destination("key:f1:mods=shift,command,option,control")
    #expect(MappingRenderer.destination(destination) == "key:f1:mods=command,control,option,shift")
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.destination("key:a:mods=shift,shift")
    }
  }

  @Test func numericIdentifiersAcceptDecimalAndPrefixedHexOnly() throws {
    #expect(try MappingSyntax.identifier("1118", option: "--vid") == 1118)
    #expect(try MappingSyntax.identifier("0x045e", option: "--vid") == 1118)
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.identifier("045e", option: "--vid")
    }
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.identifier("65536", option: "--vid")
    }
  }

  @Test func applicationScopeAndDeviceIdentifiersAreEditable() throws {
    let profile = makeProfile()
    let options = try MappingOptions([
      "--vid", "0x054c", "--pid", "3302", "--target-app", "com.example.Game"
    ])
    let updated = try MappingProfileEditor.updating(profile, options: options)
    #expect(updated.device.vendorID == 1356)
    #expect(updated.device.productID == 3302)
    #expect(updated.applicationScope == .application(bundleIdentifier: "com.example.Game"))
  }

  @Test func allAxisFieldsAndGainAreApplied() throws {
    let options = try MappingOptions(
      [
        "--deadzone", "0.2", "--gain", "1.5", "--invert", "--response-curve", "smooth_step",
        "--digital-threshold", "0.7", "--source", "axis:left_stick_x", "--target", "move:x"
      ],
      flags: ["--invert"]
    )
    let updated = try MappingProfileEditor.replacingBinding(
      in: makeProfile(),
      source: .axis(.leftStickX),
      destination: .mouseMovement(.x),
      options: options
    )
    let tuning = try #require(updated.bindings.first?.axisTuning)
    #expect(tuning.deadzone == 0.2)
    #expect(tuning.gain == 1.5)
    #expect(tuning.inverted)
    #expect(tuning.responseCurve == .smoothStep)
    #expect(tuning.digitalActivationThreshold == 0.7)
  }

  @Test func turboRequiresPairAndRejectsContinuousOutputs() throws {
    let partial = try MappingOptions(["--turbo-rate", "20"])
    #expect(throws: MappingCommandError.self) {
      try MappingProfileEditor.replacingBinding(
        in: makeProfile(),
        source: .button(.south),
        destination: .keyboard(key: .space, modifiers: []),
        options: partial
      )
    }
    let complete = try MappingOptions(["--turbo-rate", "20", "--turbo-duty", "0.4"])
    let updated = try MappingProfileEditor.replacingBinding(
      in: makeProfile(),
      source: .button(.south),
      destination: .keyboard(key: .space, modifiers: []),
      options: complete
    )
    #expect(updated.bindings.first?.turbo == RemappingTurbo(repeatRateHz: 20, dutyCycle: 0.4))
    #expect(throws: MappingCommandError.self) {
      try MappingProfileEditor.replacingBinding(
        in: makeProfile(),
        source: .axis(.leftStickX),
        destination: .scroll(.x),
        options: complete
      )
    }
  }

  @Test func replacePreservesIdentityAndUnbindRemovesIt() throws {
    let bindingID = UUID()
    let profile = makeProfile(bindings: [
      RemappingBinding(
        id: bindingID,
        source: .button(.south),
        destination: .keyboard(key: .a, modifiers: [])
      )
    ])
    let replaced = try MappingProfileEditor.replacingBinding(
      in: profile,
      source: .button(.south),
      destination: .mouseButton(.left),
      options: MappingOptions([])
    )
    #expect(replaced.bindings.first?.id == bindingID)
    #expect(
      try MappingProfileEditor.removingBinding(from: replaced, source: .button(.south)).bindings
        .isEmpty
    )
  }

  @Test func repeatedUnknownAndMalformedOptionsAreRejectedBeforeRPC() async throws {
    #expect(throws: MappingCommandError.self) { try MappingOptions(["--vid", "1", "--vid", "2"]) }
    let client = MockMappingClient(snapshotValue: snapshot([makeProfile()]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["create", "Test", "--unknown", "x"]).execute(
        client: client
      )
    }
    #expect(await client.mutationCount == 0)
  }

  @Test func retiredAliasesAreRejectedBeforeRPC() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["status"]).execute(client: client)
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "bind", profile.id.uuidString, "--source", "axis:left_stick_x", "--target", "move:x",
        "--sensitivity", "1.5"
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 0)
  }

  @Test func helpIsRecognizedAndRenderedWithoutAServiceOperation() async throws {
    let invocation = try MappingInvocation(arguments: ["--help"])
    let client = MockMappingClient(snapshotValue: snapshot([]))

    #expect(invocation.isHelp)
    #expect(try await invocation.execute(client: client) == MappingInvocation.help)
    #expect(await client.mutationCount == 0)
  }

  @Test func selectorsDistinguishUUIDMissingAndAmbiguousNames() async throws {
    let first = makeProfile(name: "Same")
    let second = makeProfile(name: "same")
    let client = MockMappingClient(snapshotValue: snapshot([first, second]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["show", "Same"]).execute(client: client)
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["show", "Missing"]).execute(client: client)
    }
    let byID = try await MappingInvocation(arguments: ["show", first.id.uuidString]).execute(
      client: client
    )
    #expect(byID.contains(first.id.uuidString))
  }

  @Test func jsonIsPrettySortedAndDeterministic() throws {
    let profile = makeProfile(name: "JSON")
    let first = try MappingRenderer.json(profile)
    #expect(first == (try MappingRenderer.json(profile)))
    #expect(first.contains("\n  \"application_scope\""))
    let keys = try #require(JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
    #expect(keys["name"] as? String == "JSON")
  }

  @Test func mutationAndPermissionCommandsRouteThroughInjectedClient() async throws {
    let profile = makeProfile(name: "Desktop")
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let commands = [
      ["create", "New", "--vid", "1118", "--pid", "654", "--global"],
      ["update", profile.id.uuidString, "--name", "Renamed"],
      ["bind", profile.id.uuidString, "--source", "button:south", "--target", "key:a"],
      ["delete", profile.id.uuidString], ["enable", profile.id.uuidString],
      ["disable", "--vid", "1118", "--pid", "654"]
    ]
    for arguments in commands {
      _ = try await MappingInvocation(arguments: arguments).execute(client: client)
    }
    #expect(
      try await MappingInvocation(arguments: ["permission", "status"]).execute(client: client)
        == "granted"
    )
    #expect(
      try await MappingInvocation(arguments: ["permission", "request"]).execute(client: client)
        == "granted"
    )
    #expect(await client.mutationCount == commands.count)
  }

  @Test func staleUpdateConflictIsPropagatedWithoutRetryOrOverwrite() async throws {
    let profile = makeProfile(name: "Desktop")
    let conflict = ApplicationServiceRemappingRPCError(
      code: .profileUpdateConflict,
      message: "The profile changed since it was read."
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]), updateError: conflict)

    await #expect(throws: conflict) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--name", "Stale edit"
      ]).execute(client: client)
    }

    #expect(await client.updateAttempts == 1)
    #expect(await client.lastExpectedCurrent == profile)
    #expect(client.snapshotValue.profiles == [profile])
  }

  @Test func editBindAndUnbindPassTheExactProfileTheyRead() async throws {
    let profile = makeProfile(
      name: "Desktop",
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let commands = [
      ["update", profile.id.uuidString, "--name", "Renamed"],
      [
        "bind", profile.id.uuidString, "--source", "axis:left_stick_x", "--target", "move:x",
        "--deadzone", "0.2"
      ], ["unbind", profile.id.uuidString, "--source", "button:south"]
    ]

    for arguments in commands {
      _ = try await MappingInvocation(arguments: arguments).execute(client: client)
    }

    #expect(await client.expectedProfiles == [profile, profile, profile])
  }

  @Test func adapterUsesAuthenticatedRPCClientFlow() async throws {
    let socketPath = "/tmp/com.openjoystickdriver.mapping-cli.\(UUID().uuidString).rpc"
    let profile = makeProfile(name: "RPC")
    let expected = snapshot([profile])
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { processID in processID == getpid() },
      handler: { request, completion in
        #expect(request.method == "getRemappingSnapshot")
        do {
          completion(
            LocalServiceRPCResponse(result: try JSONEncoder().encode(expected), error: nil)
          )
        } catch {
          completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
        }
      }
    )
    try server.start()
    defer { server.stop() }
    let rpcClient = ApplicationServiceClient(socketPath: socketPath)
    rpcClient.connect()
    #expect(rpcClient.isConnected)
    let output = try await MappingInvocation(arguments: ["list", "--json"]).execute(
      client: ApplicationMappingServiceClient(client: rpcClient)
    )
    #expect(output.contains("RPC"))
  }

  @Test func importAndExportUseFilesWhileMutationsUseClient() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("input.json")
    let output = directory.appendingPathComponent("output.json")
    let profile = makeProfile(name: "Portable")
    try Data(try MappingRenderer.json(profile).utf8).write(to: input)
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: ["import", input.path]).execute(client: client)
    _ = try await MappingInvocation(arguments: [
      "export", profile.id.uuidString, "--output", output.path
    ]).execute(client: client)
    #expect(await client.mutationCount == 1)
    #expect(
      try JSONDecoder().decode(RemappingProfile.self, from: Data(contentsOf: output)) == profile
    )
  }

  private func makeProfile(name: String = "Desktop", bindings: [RemappingBinding] = [])
    -> RemappingProfile
  {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: bindings
    )
  }

  private func snapshot(_ profiles: [RemappingProfile])
    -> ApplicationServiceRemappingSnapshotPayload
  {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }
}

private actor MockMappingClient: MappingServiceClient {
  let snapshotValue: ApplicationServiceRemappingSnapshotPayload
  let updateError: ApplicationServiceRemappingRPCError?
  private(set) var mutationCount = 0
  private(set) var updateAttempts = 0
  private(set) var lastExpectedCurrent: RemappingProfile?
  private(set) var expectedProfiles: [RemappingProfile] = []

  init(
    snapshotValue: ApplicationServiceRemappingSnapshotPayload,
    updateError: ApplicationServiceRemappingRPCError? = nil
  ) {
    self.snapshotValue = snapshotValue
    self.updateError = updateError
  }

  func snapshot() -> ApplicationServiceRemappingSnapshotPayload { snapshotValue }
  func profile(id: UUID) throws -> RemappingProfile {
    guard let profile = snapshotValue.profiles.first(where: { $0.id == id }) else {
      throw MappingCommandError.profileNotFound(id.uuidString)
    }
    return profile
  }
  func create(_ profile: RemappingProfile) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }
  func update(_ profile: RemappingProfile, expectedCurrent: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    mutationCount += 1
    updateAttempts += 1
    lastExpectedCurrent = expectedCurrent
    expectedProfiles.append(expectedCurrent)
    if let updateError { throw updateError }
    return snapshotValue
  }
  func importProfile(_ profile: RemappingProfile) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }
  func delete(id: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }
  func activate(id: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }
  func deactivate(vendorID: UInt16, productID: UInt16) -> ApplicationServiceRemappingSnapshotPayload
  {
    mutationCount += 1
    return snapshotValue
  }
  func deactivate(profileID: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    return snapshotValue
  }
  func access(request: Bool) -> RemappingPostEventAccessState { .granted }
}
