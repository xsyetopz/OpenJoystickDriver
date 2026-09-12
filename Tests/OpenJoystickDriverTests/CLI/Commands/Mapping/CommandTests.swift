import Foundation
import Testing

@testable import OpenJoystickDriver
@testable import OpenJoystickDriverKit

@Suite(.serialized)
struct MappingCommandTests {
  @Test(arguments: [
    ("button:south", RemappingSource.button(.south)), ("dpad:left", RemappingSource.dpad(.left)),
    ("axis:left_stick_x", RemappingSource.axis(.leftStickX)),
    ("axis:right_trigger:positive", RemappingSource.axisDirection(.rightTrigger, .positive)),
    ("trigger:left:soft", RemappingSource.triggerStage(.left, .soft)),
    ("trigger:right:full", RemappingSource.triggerStage(.right, .full)),
    ("motion:lean:left", RemappingSource.motionLean(.left)),
    ("motion:lean:right", RemappingSource.motionLean(.right)),
    ("touch:left:contact", RemappingSource.touchContact(.left)),
    (
      "touch:right:grid:2:3:1:2",
      RemappingSource.touchGrid(
        RemappingTouchGridSource(surface: .right, columns: 2, rows: 3, column: 1, row: 2)
      )
    ),
    (
      "touch:primary:swipe:left:0.25",
      RemappingSource.touchSwipe(
        RemappingTouchSwipeSource(surface: .primary, direction: .left, minimumDistance: 0.25)
      )
    ),
  ])
  func parsesEverySourceFamily(raw: String, expected: RemappingSource) throws {
    #expect(try MappingSyntax.source(raw) == expected)
  }

  @Test
  func touchOptionsAndSourcesReachCreateUpdateAndRendering() async throws {
    let createClient = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Touch", "--vid", "1", "--pid", "2", "--global", "--virtual-gamepad", "mapped",
      "--touch-surface", "right", "--touch-mode", "right_stick", "--touch-stick-radius", "0.4",
    ]).execute(client: createClient)
    let created = try #require(await createClient.submittedProfile)
    #expect(created.touchMappings.first?.mode == .rightStick)
    #expect(created.touchMappings.first?.stickRadius == 0.4)

    let updateClient = MockMappingClient(snapshotValue: snapshot([created]))
    _ = try await MappingInvocation(arguments: [
      "update", created.id.uuidString, "--touch-surface", "right", "--touch-mode", "pointer",
      "--touch-pointer-sensitivity", "900",
    ]).execute(client: updateClient)
    let updated = try #require(await updateClient.submittedProfile)
    #expect(updated.touchMappings.first?.mode == .pointer)
    #expect(updated.touchMappings.first?.pointerSensitivity == 900)

    let bindClient = MockMappingClient(snapshotValue: snapshot([updated]))
    _ = try await MappingInvocation(arguments: [
      "bind", updated.id.uuidString, "--source", "touch:right:grid:3:2:2:1", "--target",
      "key:space",
    ]).execute(client: bindClient)
    let bound = try #require(await bindClient.submittedProfile)
    #expect(MappingRenderer.profile(bound).contains("touch:right:grid:3:2:2:1"))
    #expect(MappingRenderer.profile(bound).contains("touch:right mode:pointer"))
  }

  @Test(arguments: [
    ("key:a", RemappingDestination.keyboard(key: .a, modifiers: [])),
    ("mouse:forward", RemappingDestination.mouseButton(.forward)),
    ("move:x", RemappingDestination.mouseMovement(.x)),
    ("scroll:y", RemappingDestination.scroll(.y)),
  ])
  func parsesEveryDestinationFamily(raw: String, expected: RemappingDestination) throws {
    #expect(try MappingSyntax.destination(raw) == expected)
  }

  @Test(arguments: ["chord", "sequence", "layer"])
  func nestedCommandsResolveProfileAfterAction(command: String) async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let options: [String]
    if command == "layer" {
      options = ["--name", "Layer", "--activator", "button:west", "--mode", "hold"]
    } else {
      options =
        ["--sources", "button:south,button:east", "--target", "key:space"]
        + (command == "sequence" ? ["--window", "200"] : [])
    }
    _ = try await MappingInvocation(
      arguments: [command, command == "layer" ? "create" : "add", profile.id.uuidString] + options
    ).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.id == profile.id)
    #expect(await client.lastExpectedCurrent == profile)
    #expect(submitted.chords.count + submitted.sequences.count + submitted.layers.count == 1)
  }

  @Test
  func layerMotionCommandPersistsOverrideAndRejectsInvalidMutation() async throws {
    let initial = makeProfile()
    let creator = MockMappingClient(snapshotValue: snapshot([initial]))
    _ = try await MappingInvocation(arguments: [
      "layer", "create", initial.id.uuidString, "--name", "Aim", "--activator", "button:west",
      "--mode", "hold",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    let layer = try #require(profile.layers.first)
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let prefix = ["layer", "motion", profile.id.uuidString, "--layer", layer.id.uuidString]
    _ = try await MappingInvocation(arguments: prefix + ["--motion-yaw-sensitivity", "0.5"])
      .execute(client: client)
    let edited = try #require(await client.submittedProfile)
    #expect(edited.layers.first?.motionTuning?.yawSensitivity == 0.5)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: RemappingMotionTuningError.self) {
      try await MappingInvocation(arguments: prefix + ["--motion-yaw-sensitivity", "-1"]).execute(
        client: client
      )
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: prefix + ["--clear", "--motion-yaw-sensitivity", "2"])
        .execute(client: client)
    }
    #expect(await client.mutationCount == 1)
    let clearer = MockMappingClient(snapshotValue: snapshot([edited]))
    _ = try await MappingInvocation(arguments: prefix + ["--clear"]).execute(client: clearer)
    #expect(await clearer.submittedProfile?.layers.first?.motionTuning == nil)
    #expect(await clearer.lastExpectedCurrent == edited)
  }

  @Test
  func simultaneousChordOptionsReachValidatedProfile() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let arguments = [
      "chord", "add", profile.id.uuidString, "--sources", "button:south,button:east", "--target",
      "key:space", "--mode", "simultaneous", "--window-ms",
    ]
    _ = try await MappingInvocation(arguments: arguments + ["75"]).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.chords.first?.mode == .simultaneous)
    #expect(submitted.chords.first?.windowMs == 75)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: RemappingValidationError.chordWindowOutOfRange(index: 0)) {
      try await MappingInvocation(arguments: arguments + ["0"]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
  }

  @Test
  func parsesAndCanonicallyRendersModifiers() throws {
    let destination = try MappingSyntax.destination("key:f1:mods=shift,command,option,control")
    #expect(MappingRenderer.destination(destination) == "key:f1:mods=command,control,option,shift")
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.destination("key:a:mods=shift,shift")
    }
  }

  @Test(arguments: ["status", "start", "pause", "reset"])
  func calibrationSelectsExactControllerAndPropagatesServiceErrors(operation: String) async throws {
    let client = MockMappingClient(snapshotValue: snapshot([]))
    let identifier = "045e:028e:location:2"
    await #expect(
      throws: ApplicationServiceRemappingRPCError(code: .controllerUnavailable, message: identifier)
    ) {
      try await MappingInvocation(arguments: ["calibration", operation, "--controller", identifier])
        .execute(client: client)
    }
    #expect(await client.calibrationCalls == 1)
    #expect(
      await client.calibrationCommand == RemappingMotionCalibrationCommand(rawValue: operation)
    )
    #expect(await client.mutationCount == 0)
  }

  @Test
  func malformedCalibrationCommandsDoNotReachService() async throws {
    let client = MockMappingClient(snapshotValue: snapshot([]))
    for arguments in [
      ["calibration"], ["calibration", "stop"], ["calibration", "start"],
      ["calibration", "start", "--controller", ""],
      ["calibration", "start", "--controller", String(repeating: "é", count: 257)],
      ["calibration", "start", "--controller", "one", "--unknown", "value"],
    ] {
      await #expect(throws: MappingCommandError.self) {
        try await MappingInvocation(arguments: arguments).execute(client: client)
      }
    }
    #expect(await client.calibrationCalls == 0)
  }

  @Test
  func nestedLayerBindingAcceptsActionCollection() async throws {
    let initial = makeProfile()
    let createClient = MockMappingClient(snapshotValue: snapshot([initial]))
    _ = try await MappingInvocation(arguments: [
      "layer", "create", initial.id.uuidString, "--name", "Layer", "--activator", "button:west",
      "--mode", "hold",
    ]).execute(client: createClient)
    let profile = try #require(await createClient.submittedProfile)
    let layer = try #require(profile.layers.first)
    let actions = [RemappingAction(destination: .keyboard(key: .b, modifiers: []))]
    let json = try #require(String(data: JSONEncoder().encode(actions), encoding: .utf8))
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "layer", "bind", profile.id.uuidString, "--layer", layer.id.uuidString, "--source",
      "button:south", "--target", "key:a", "--actions-json", json,
    ]).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.layers.first?.bindings.first?.additionalActions == actions)
    #expect(await client.lastExpectedCurrent == profile)
    _ = try await MappingInvocation(arguments: ["layer", "list", profile.id.uuidString]).execute(
      client: client
    )
    #expect(await client.mutationCount == 1)
  }

  @Test
  func numericIdentifiersAcceptDecimalAndPrefixedHexOnly() throws {
    #expect(try MappingSyntax.identifier("1118", option: "--vid") == 1118)
    #expect(try MappingSyntax.identifier("0x045e", option: "--vid") == 1118)
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.identifier("045e", option: "--vid")
    }
    #expect(throws: MappingCommandError.self) {
      try MappingSyntax.identifier("65536", option: "--vid")
    }
  }

  @Test
  func outputPolicyOptionsReachCreateAndUpdate() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "create", "Virtual", "--vid", "1118", "--pid", "654", "--global", "--virtual-gamepad",
      "passthrough", "--physical-input", "exclusive",
    ]).execute(client: client)
    #expect(
      await client.submittedProfile?.outputPolicy
        == RemappingOutputPolicy(virtualGamepad: .passthrough, physicalInput: .exclusive)
    )
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--virtual-gamepad", "mapped",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.outputPolicy.virtualGamepad == .mapped)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--virtual-gamepad", "invalid",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 2)
  }

  @Test
  func gyroOptionsCreatePreserveAndRejectInvalidUpdates() async throws {
    let creator = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Gyro", "--vid", "1", "--pid", "2", "--global", "--gyro-output", "mouse",
      "--gyro-pointer-points-per-degree", "4.5", "--gyro-activation", "toggle",
      "--gyro-activation-source", "button:south",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    #expect(profile.gyroOutput.mode == .mouse)
    #expect(profile.gyroOutput.pointerPointsPerDegree == 4.5)
    #expect(profile.gyroOutput.activationMode == .toggle)
    #expect(profile.gyroOutput.activationSource == .button(.south))
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--name", "Renamed",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.gyroOutput == profile.gyroOutput)
    await #expect(throws: RemappingGyroOutputError.invalidField("pointer_points_per_degree")) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--gyro-pointer-points-per-degree", "-1",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
    #expect(await client.lastExpectedCurrent == profile)
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--gyro-activation", "always",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.gyroOutput.activationMode == .always)
    #expect(await client.submittedProfile?.gyroOutput.activationSource == nil)
  }

  @Test
  func stickCommandsCreatePreserveRemoveAndRejectInvalidEdits() async throws {
    let creator = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Flick", "--vid", "1", "--pid", "2", "--global", "--stick-source", "right",
      "--stick-mode", "flick", "--stick-pointer-points-per-degree", "4",
    ]).execute(client: creator)
    let profile = try #require(await creator.submittedProfile)
    #expect(
      profile.stickMappings == [
        RemappingStickMapping(source: .right, mode: .flick, pointerPointsPerDegree: 4)
      ]
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--name", "Renamed",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.stickMappings == profile.stickMappings)
    #expect(await client.lastExpectedCurrent == profile)
    await #expect(throws: RemappingStickMappingError.invalidField("flick_duration_ms")) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--stick-source", "right", "--stick-flick-duration-ms",
        "-1",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
    _ = try await MappingInvocation(arguments: [
      "update", profile.id.uuidString, "--stick-source", "right", "--stick-mode", "none",
    ]).execute(client: client)
    #expect(await client.submittedProfile?.stickMappings.isEmpty == true)
    #expect(await client.lastExpectedCurrent == profile)
  }

  @Test
  func motionOptionsReachCreateAndValidatedUpdate() async throws {
    let createClient = MockMappingClient(snapshotValue: snapshot([]))
    _ = try await MappingInvocation(arguments: [
      "create", "Motion", "--vid", "1118", "--pid", "654", "--global", "--motion-space", "world",
      "--motion-pitch-sensitivity", "3", "--motion-invert-yaw", "true",
      "--motion-smoothing-half-time-ms", "25",
    ]).execute(client: createClient)
    let original = try #require(await createClient.submittedProfile)
    #expect(original.motionTuning.space == .world)
    #expect(original.motionTuning.pitchSensitivity == 3)
    #expect(original.motionTuning.invertYaw)
    let client = MockMappingClient(snapshotValue: snapshot([original]))
    _ = try await MappingInvocation(arguments: [
      "update", original.id.uuidString, "--motion-invert-yaw", "false", "--motion-yaw-sensitivity",
      "4",
    ]).execute(client: client)
    let updated = try #require(await client.submittedProfile)
    #expect(updated.motionTuning.space == .world)
    #expect(updated.motionTuning.pitchSensitivity == 3)
    #expect(updated.motionTuning.smoothingHalfTimeMs == 25)
    #expect(updated.motionTuning.yawSensitivity == 4)
    #expect(!updated.motionTuning.invertYaw)
    #expect(await client.lastExpectedCurrent == original)
    await #expect(throws: RemappingMotionTuningError.invalidField("yaw_sensitivity")) {
      try await MappingInvocation(arguments: [
        "update", original.id.uuidString, "--motion-yaw-sensitivity", "101",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
  }

  @Test
  func bindingBehaviorCanBeAuthoredAndInvalidValuesDoNotMutate() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    _ = try await MappingInvocation(arguments: [
      "bind", profile.id.uuidString, "--source", "button:south", "--target", "key:space",
      "--behavior", "toggle",
    ]).execute(client: client)
    let submitted = try #require(await client.submittedProfile)
    #expect(submitted.bindings.first?.behavior == .toggle)
    let preserved = try MappingProfileEditor.replacingBinding(
      in: submitted,
      source: .button(.south),
      destination: .mouseButton(.left),
      options: MappingOptions([])
    )
    #expect(preserved.bindings.first?.behavior == .toggle)
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "bind", profile.id.uuidString, "--source", "button:south", "--target", "key:space",
        "--behavior", "invalid",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 1)
  }

  @Test
  func applicationScopeAndDeviceIdentifiersAreEditable() throws {
    let profile = makeProfile()
    let options = try MappingOptions([
      "--vid", "0x054c", "--pid", "3302", "--target-app", "com.example.Game",
    ])
    let updated = try MappingProfileEditor.updating(profile, options: options)
    #expect(updated.device.vendorID == 1356)
    #expect(updated.device.productID == 3302)
    #expect(updated.applicationScope == .application(bundleIdentifier: "com.example.Game"))
  }

  @Test
  func allAxisFieldsAndGainAreApplied() throws {
    let options = try MappingOptions(
      [
        "--deadzone", "0.2", "--gain", "1.5", "--invert", "--response-curve", "smooth_step",
        "--digital-threshold", "0.7", "--source", "axis:left_stick_x", "--target", "move:x",
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

  @Test
  func turboRequiresPairAndRejectsContinuousOutputs() throws {
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

  @Test
  func replacePreservesIdentityAndUnbindRemovesIt() throws {
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

  @Test
  func repeatedUnknownAndMalformedOptionsAreRejectedBeforeRPC() async throws {
    #expect(throws: MappingCommandError.self) { try MappingOptions(["--vid", "1", "--vid", "2"]) }
    let client = MockMappingClient(snapshotValue: snapshot([makeProfile()]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["create", "Test", "--unknown", "x"]).execute(
        client: client
      )
    }
    #expect(await client.mutationCount == 0)
  }

  @Test
  func obsoleteMappingAliasesAreRejectedBeforeRPC() async throws {
    let profile = makeProfile()
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: ["status"]).execute(client: client)
    }
    await #expect(throws: MappingCommandError.self) {
      try await MappingInvocation(arguments: [
        "bind", profile.id.uuidString, "--source", "axis:left_stick_x", "--target", "move:x",
        "--sensitivity", "1.5",
      ]).execute(client: client)
    }
    #expect(await client.mutationCount == 0)
  }

  @Test
  func helpIsRecognizedAndRenderedWithoutAServiceOperation() async throws {
    let invocation = try MappingInvocation(arguments: ["--help"])
    let client = MockMappingClient(snapshotValue: snapshot([]))

    #expect(invocation.isHelp)
    #expect(try await invocation.execute(client: client) == MappingInvocation.help)
    #expect(await client.mutationCount == 0)
  }

  @Test
  func selectorsDistinguishUUIDMissingAndAmbiguousNames() async throws {
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

  @Test
  func jsonIsPrettySortedAndDeterministic() throws {
    let profile = makeProfile(name: "JSON")
    let first = try MappingRenderer.json(profile)
    #expect(first == (try MappingRenderer.json(profile)))
    #expect(first.contains("\n  \"application_scope\""))
    let keys = try #require(JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
    #expect(keys["name"] as? String == "JSON")
  }

  @Test
  func mutationAndPermissionCommandsRouteThroughInjectedClient() async throws {
    let profile = makeProfile(name: "Desktop")
    let client = MockMappingClient(snapshotValue: snapshot([profile]))
    let commands = [
      ["create", "New", "--vid", "1118", "--pid", "654", "--global"],
      ["update", profile.id.uuidString, "--name", "Renamed"],
      ["bind", profile.id.uuidString, "--source", "button:south", "--target", "key:a"],
      ["delete", profile.id.uuidString], ["enable", profile.id.uuidString],
      ["disable", "--vid", "1118", "--pid", "654"],
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

  @Test
  func staleUpdateConflictIsPropagatedWithoutRetryOrOverwrite() async throws {
    let profile = makeProfile(name: "Desktop")
    let conflict = ApplicationServiceRemappingRPCError(
      code: .profileUpdateConflict,
      message: "The profile changed since it was read."
    )
    let client = MockMappingClient(snapshotValue: snapshot([profile]), updateError: conflict)

    await #expect(throws: conflict) {
      try await MappingInvocation(arguments: [
        "update", profile.id.uuidString, "--name", "Stale edit",
      ]).execute(client: client)
    }

    #expect(await client.updateAttempts == 1)
    #expect(await client.lastExpectedCurrent == profile)
    #expect(client.snapshotValue.profiles == [profile])
  }

  @Test
  func editBindAndUnbindPassTheExactProfileTheyRead() async throws {
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
        "--deadzone", "0.2",
      ], ["unbind", profile.id.uuidString, "--source", "button:south"],
    ]

    for arguments in commands {
      _ = try await MappingInvocation(arguments: arguments).execute(client: client)
    }

    #expect(await client.expectedProfiles == [profile, profile, profile])
  }

  @Test
  func adapterUsesAuthenticatedRPCClientFlow() async throws {
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

  @Test
  func calibrationStatusRoundTripsThroughAuthenticatedCLIAdapter() async throws {
    let socketPath = "/tmp/com.openjoystickdriver.calibration-cli.\(UUID().uuidString).rpc"
    let identifier = "045e:028e:location:2"
    let payload = Data(
      """
      {"hasMotionBaseline":true,"isCollecting":false,
       "offsetDegreesPerSecond":{"x":1.25,"y":-2.5,"z":0.125}}
      """.utf8
    )
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { $0 == getpid() },
      handler: { request, completion in
        #expect(request.method == "remappingMotionCalibration")
        do {
          let arguments = try JSONDecoder().decode(
            ApplicationServiceMotionCalibrationArguments.self,
            from: request.arguments
          )
          #expect(arguments.runtimeIdentifier == identifier)
          #expect(arguments.command == nil)
          completion(LocalServiceRPCResponse(result: payload, error: nil))
        } catch {
          completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
        }
      }
    )
    try server.start()
    defer { server.stop() }
    let rpcClient = ApplicationServiceClient(socketPath: socketPath)
    rpcClient.connect()
    defer { rpcClient.disconnect() }
    let output = try await MappingInvocation(arguments: [
      "calibration", "status", "--controller", identifier,
    ]).execute(client: ApplicationMappingServiceClient(client: rpcClient))
    let status = try JSONDecoder().decode(
      RemappingMotionCalibrationStatus.self,
      from: Data(output.utf8)
    )
    #expect(status.hasMotionBaseline)
    #expect(!status.isCollecting)
    #expect(status.offsetDegreesPerSecond == ControllerMotionVector(x: 1.25, y: -2.5, z: 0.125))
  }

  @Test
  func importAndExportUseFilesWhileMutationsUseClient() async throws {
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
      "export", profile.id.uuidString, "--output", output.path,
    ]).execute(client: client)
    #expect(await client.mutationCount == 1)
    #expect(
      try JSONDecoder().decode(RemappingProfile.self, from: Data(contentsOf: output)) == profile
    )
  }

  private func makeProfile(
    name: String = "Desktop",
    bindings: [RemappingBinding] = []
  ) -> RemappingProfile {
    RemappingProfile(
      name: name,
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: bindings
    )
  }

  private func snapshot(
    _ profiles: [RemappingProfile]
  ) -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: profiles,
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }
}

actor MockMappingClient: MappingServiceClient {
  let snapshotValue: ApplicationServiceRemappingSnapshotPayload
  let updateError: ApplicationServiceRemappingRPCError?
  var mutationCount = 0
  private(set) var submittedProfile: RemappingProfile?
  private(set) var updateAttempts = 0
  private(set) var lastExpectedCurrent: RemappingProfile?
  private(set) var expectedProfiles: [RemappingProfile] = []
  private(set) var calibrationCalls = 0
  private(set) var calibrationCommand: RemappingMotionCalibrationCommand?
  var pairRequest: (left: String, right: String, profileID: UUID)?
  var unpairedSessionID: UUID?

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
    submittedProfile = profile
    mutationCount += 1
    return snapshotValue
  }
  func update(
    _ profile: RemappingProfile,
    expectedCurrent: RemappingProfile
  ) throws -> ApplicationServiceRemappingSnapshotPayload {
    mutationCount += 1
    submittedProfile = profile
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
  func motionCalibration(
    runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand?
  ) throws -> RemappingMotionCalibrationStatus {
    calibrationCalls += 1
    calibrationCommand = command
    throw ApplicationServiceRemappingRPCError(
      code: .controllerUnavailable,
      message: runtimeIdentifier
    )
  }
}
