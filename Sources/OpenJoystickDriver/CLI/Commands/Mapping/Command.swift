import Foundation
import OpenJoystickDriverKit

struct MappingCommand {
  func run(arguments: [String]) {
    do {
      let invocation = try MappingInvocation(arguments: arguments)
      if invocation.isHelp {
        print(MappingInvocation.help)
        return
      }
      let client = ApplicationServiceClient()
      client.connect()
      defer { client.disconnect() }
      guard client.isConnected else {
        throw MappingCommandError.invalidArguments(
          CLILocalized.text(
            "cli.mapping.app_unreachable",
            "Could not connect to the installed main app."
          )
        )
      }
      let result: Result<String, any Error> = runSyncResult {
        do {
          return .success(
            try await invocation.execute(client: ApplicationMappingServiceClient(client: client))
          )
        } catch { return .failure(error) }
      }
      print(try result.get())
    } catch {
      CLIOutput.error(error.localizedDescription)
      exit(1)
    }
  }
}

struct MappingInvocation {
  private static let bindingOptions: Set<String> = [
    "--source", "--target", "--deadzone", "--gain", "--invert", "--response-curve",
    "--digital-threshold", "--turbo-rate", "--turbo-duty", "--long-hold", "--double-tap",
    "--behavior", "--pulse-ms", "--actions-json",
  ]
  private let command: String
  private let arguments: [String]

  var isHelp: Bool { command == "help" || command == "--help" || command == "-h" }

  init(arguments: [String]) throws {
    guard let command = arguments.first else {
      throw MappingCommandError.invalidArguments(Self.help)
    }
    self.command = command
    self.arguments = Array(arguments.dropFirst())
  }

  func execute(client: any MappingServiceClient) async throws -> String {
    switch command {
    case "help", "--help", "-h": return Self.help
    case "list": return try await renderSnapshot(client: client)
    case "show": return try await show(client: client)
    case "create": return try await create(client: client)
    case "update": return try await update(client: client)
    case "bind": return try await bind(client: client)
    case "unbind": return try await unbind(client: client)
    case "delete": return try await delete(client: client)
    case "import": return try await importProfile(client: client)
    case "export": return try await export(client: client)
    case "enable": return try await activate(client: client)
    case "disable": return try await deactivate(client: client)
    case "permission": return try await permission(client: client)
    case "calibration": return try await calibration(client: client)
    case "joy-con": return try await joyCon(client: client)
    case "chord": return try await chord(client: client)
    case "sequence": return try await sequence(client: client)
    case "layer": return try await layer(client: client)
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.command_unknown", "Unknown map command '%@'.", command)
      )
    }
  }

  private func renderSnapshot(client: any MappingServiceClient) async throws -> String {
    let options = try MappingOptions(arguments, flags: ["--json"])
    try options.validate(allowed: ["--json"])
    let snapshot = try await client.snapshot()
    return try options.contains("--json")
      ? MappingRenderer.json(snapshot) : MappingRenderer.snapshot(snapshot)
  }

  private func show(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--json"])
    try options.validate(allowed: ["--json"])
    let profile = try await resolve(selector, client: client)
    return try options.contains("--json")
      ? MappingRenderer.json(profile) : MappingRenderer.profile(profile)
  }

  private func create(client: any MappingServiceClient) async throws -> String {
    let (name, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--global"])
    try options.validate(
      allowed: Set([
        "--vid", "--pid", "--target-app", "--global", "--virtual-gamepad", "--physical-input",
      ]).union(MappingProfileEditor.motionOptions).union(MappingProfileEditor.joyConPairOptions)
        .union(MappingProfileEditor.stickOptions).union(MappingProfileEditor.touchOptions)
        .union(MappingProfileEditor.triggerOptions)
    )
    let profile = RemappingProfile(
      name: name,
      device: RemappingDeviceScope(
        vendorID: try MappingSyntax.identifier(options.required("--vid"), option: "--vid"),
        productID: try MappingSyntax.identifier(options.required("--pid"), option: "--pid")
      ),
      applicationScope: try MappingProfileEditor.applicationScope(options),
      outputPolicy: try MappingProfileEditor.outputPolicy(options),
      motionTuning: try MappingProfileEditor.motionTuning(options),
      gyroOutput: try MappingProfileEditor.gyroOutput(options),
      joyConPair: try MappingProfileEditor.joyConPairSettings(options),
      stickMappings: try MappingProfileEditor.stickMappings(options),
      triggerMappings: try MappingProfileEditor.triggerMappings(options),
      touchMappings: try MappingProfileEditor.touchMappings(options),
      bindings: []
    )
    try profile.validate()
    return render(try await client.create(profile), profileID: profile.id)
  }

  private func update(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--global"])
    try options.validate(
      allowed: Set([
        "--name", "--vid", "--pid", "--target-app", "--global", "--virtual-gamepad",
        "--physical-input",
      ]).union(MappingProfileEditor.motionOptions).union(MappingProfileEditor.joyConPairOptions)
        .union(MappingProfileEditor.stickOptions).union(MappingProfileEditor.touchOptions)
        .union(MappingProfileEditor.triggerOptions)
    )
    let profile = try await resolve(selector, client: client)
    let updated = try MappingProfileEditor.updating(profile, options: options)
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  private func bind(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--invert"])
    try options.validate(allowed: Self.bindingOptions)
    let profile = try await resolve(selector, client: client)
    let updated = try MappingProfileEditor.replacingBinding(
      in: profile,
      source: try MappingSyntax.source(options.required("--source")),
      destination: try MappingSyntax.destination(options.required("--target")),
      options: options
    )
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  private func unbind(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing)
    try options.validate(allowed: ["--source"])
    let profile = try await resolve(selector, client: client)
    let updated = try MappingProfileEditor.removingBinding(
      from: profile,
      source: try MappingSyntax.source(options.required("--source"))
    )
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  private func delete(client: any MappingServiceClient) async throws -> String {
    let selector = try soleArgument(
      CLILocalized.text("cli.mapping.usage.delete", "map delete <uuid-or-name>")
    )
    let profile = try await resolve(selector, client: client)
    return MappingRenderer.snapshot(try await client.delete(id: profile.id))
  }

  private func importProfile(client: any MappingServiceClient) async throws -> String {
    let path = try soleArgument(CLILocalized.text("cli.mapping.usage.import", "map import <file>"))
    let profile = try RemappingProfileFileStore.load(from: URL(fileURLWithPath: path))
    return render(try await client.importProfile(profile), profileID: profile.id)
  }

  private func export(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing)
    try options.validate(allowed: ["--output"])
    let profile = try await resolve(selector, client: client)
    let text = try RemappingProfileFileStore.encodedJSON(profile)
    if let output = options["--output"] {
      try RemappingProfileFileStore.write(profile, to: URL(fileURLWithPath: output))
      return output
    }
    return text
  }

  private func activate(client: any MappingServiceClient) async throws -> String {
    let profile = try await resolve(
      soleArgument(CLILocalized.text("cli.mapping.usage.enable", "map enable <uuid-or-name>")),
      client: client
    )
    return MappingRenderer.snapshot(try await client.activate(id: profile.id))
  }

  private func deactivate(client: any MappingServiceClient) async throws -> String {
    let options = try MappingOptions(arguments)
    try options.validate(allowed: ["--vid", "--pid", "--profile"])
    if let profileSelector = options["--profile"] {
      let profile = try await resolve(profileSelector, client: client)
      return MappingRenderer.snapshot(try await client.deactivate(profileID: profile.id))
    }
    let vendorID = try MappingSyntax.identifier(options.required("--vid"), option: "--vid")
    let productID = try MappingSyntax.identifier(options.required("--pid"), option: "--pid")
    return MappingRenderer.snapshot(
      try await client.deactivate(vendorID: vendorID, productID: productID)
    )
  }

  private func permission(client: any MappingServiceClient) async throws -> String {
    let operation = try soleArgument(
      CLILocalized.text("cli.mapping.usage.permission", "map permission status|request")
    )
    guard operation == "status" || operation == "request" else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.usage.permission", "map permission status|request")
      )
    }
    return try await client.access(request: operation == "request").rawValue
  }

  private func calibration(client: any MappingServiceClient) async throws -> String {
    guard let operation = arguments.first,
      operation == "status" || RemappingMotionCalibrationCommand(rawValue: operation) != nil
    else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.usage.calibration",
          "Usage: map calibration status|start|pause|reset --controller <runtime-identifier>"
        )
      )
    }
    let options = try MappingOptions(Array(arguments.dropFirst()))
    try options.validate(allowed: ["--controller"])
    let identifier = try options.required("--controller")
    guard !identifier.isEmpty, identifier.utf8.count <= 512 else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.calibration.identifier_required",
          "A valid controller runtime identifier is required."
        )
      )
    }
    return try MappingRenderer.json(
      await client.motionCalibration(
        runtimeIdentifier: identifier,
        command: RemappingMotionCalibrationCommand(rawValue: operation)
      )
    )
  }

  private func joyCon(client: any MappingServiceClient) async throws -> String {
    guard let operation = arguments.first else {
      throw MappingCommandError.invalidArguments(
        "Usage: map joy-con pair <profile> --left <runtime-id> --right <runtime-id> | "
          + "unpair --session <uuid>"
      )
    }
    switch operation {
    case "pair":
      guard arguments.count >= 2 else {
        throw MappingCommandError.invalidArguments("A paired Joy-Con profile is required.")
      }
      let profile = try await resolve(arguments[1], client: client)
      let options = try MappingOptions(Array(arguments.dropFirst(2)))
      try options.validate(allowed: ["--left", "--right"])
      return MappingRenderer.snapshot(
        try await client.pairJoyCons(
          left: options.required("--left"),
          right: options.required("--right"),
          profileID: profile.id
        )
      )
    case "unpair":
      let options = try MappingOptions(Array(arguments.dropFirst()))
      try options.validate(allowed: ["--session"])
      let sessionID = try MappingSyntax.uuid(options.required("--session"), option: "--session")
      return MappingRenderer.snapshot(try await client.unpairJoyCons(sessionID: sessionID))
    default: throw MappingCommandError.invalidArguments("Expected joy-con pair or joy-con unpair.")
    }
  }

  private func chord(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.usage.chord", "Usage: map chord add|delete <profile> ...")
      )
    }
    switch action {
    case "add":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--sources", "--target", "--mode", "--window-ms"])
      let profile = try await resolve(selector, client: client)
      let sources = try MappingSyntax.sourceList(try options.required("--sources"))
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.addingChord(
        in: profile,
        sources: sources,
        destination: destination,
        mode: try MappingProfileEditor.chordMode(options),
        windowMs: try MappingProfileEditor.chordWindow(options)
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "delete":
      return try await deleteByID(client: client) { profile, id in
        try MappingProfileEditor.removingChord(from: profile, chordID: id)
      }
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.chord_action_unknown",
          "Unknown chord action '%@'. Expected: add | delete",
          action
        )
      )
    }
  }

  private func sequence(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.usage.sequence",
          "Usage: map sequence add|delete <profile> ..."
        )
      )
    }
    switch action {
    case "add":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--sources", "--window", "--target"])
      let profile = try await resolve(selector, client: client)
      let sources = try MappingSyntax.sourceList(try options.required("--sources"))
      let window = try MappingSyntax.finiteDouble(
        try options.required("--window"),
        option: "--window"
      )
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.addingSequence(
        in: profile,
        sources: sources,
        windowMs: window,
        destination: destination
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "delete":
      return try await deleteByID(client: client) { profile, id in
        try MappingProfileEditor.removingSequence(from: profile, sequenceID: id)
      }
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.sequence_action_unknown",
          "Unknown sequence action '%@'. Expected: add | delete",
          action
        )
      )
    }
  }

  private func layer(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text(
          "cli.mapping.usage.layer",
          "Usage: map layer create|delete|bind|unbind|motion|list <profile> ..."
        )
      )
    }
    switch action {
    case "motion":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts, flags: ["--clear"])
      let tuningOptions = MappingProfileEditor.motionOptions.filter { $0.hasPrefix("--motion-") }
      try options.validate(allowed: Set(tuningOptions).union(["--layer", "--clear"]))
      let profile = try await resolve(selector, client: client)
      let id = try MappingSyntax.uuid(try options.required("--layer"), option: "--layer")
      let updated = try MappingProfileEditor.settingLayerMotion(
        profile,
        layerID: id,
        options: options
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "create":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--name", "--activator", "--mode"])
      let profile = try await resolve(selector, client: client)
      let name = try options.required("--name")
      let activator = try MappingSyntax.source(try options.required("--activator"))
      let mode = try layerMode(try options.required("--mode"))
      let updated = try MappingProfileEditor.creatingLayer(
        in: profile,
        name: name,
        activator: activator,
        mode: mode
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "delete":
      return try await deleteByID(client: client) { profile, id in
        try MappingProfileEditor.deletingLayer(from: profile, layerID: id)
      }
    case "bind":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts, flags: ["--invert"])
      try options.validate(
        allowed: Set(["--layer", "--source", "--target"]).union(Self.bindingOptions)
      )
      let profile = try await resolve(selector, client: client)
      let layerID = try MappingSyntax.uuid(try options.required("--layer"), option: "--layer")
      let source = try MappingSyntax.source(try options.required("--source"))
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.bindingInLayer(
        in: profile,
        layerID: layerID,
        source: source,
        destination: destination,
        options: options
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "unbind":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--layer", "--source"])
      let profile = try await resolve(selector, client: client)
      let layerID = try MappingSyntax.uuid(try options.required("--layer"), option: "--layer")
      let source = try MappingSyntax.source(try options.required("--source"))
      let updated = try MappingProfileEditor.unbindingInLayer(
        from: profile,
        layerID: layerID,
        source: source
      )
      return render(
        try await client.update(updated, expectedCurrent: profile),
        profileID: profile.id
      )
    case "list":
      let selector = try soleArgument(
        CLILocalized.text("cli.mapping.usage.layer_list", "map layer list <profile>")
      )
      let profile = try await resolve(selector, client: client)
      return MappingRenderer.layers(profile)
    default:
      throw MappingCommandError.invalidArguments(
        CLILocalized.format(
          "cli.mapping.layer_action_unknown",
          "Unknown layer action '%@'. Expected: create | delete | bind | unbind | motion | list",
          action
        )
      )
    }
  }

  private func layerMode(_ raw: String) throws -> RemappingLayerActivation {
    guard let mode = RemappingLayerActivation(rawValue: raw) else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.mode_invalid", "--mode must be 'hold' or 'toggle'.")
      )
    }
    return mode
  }

  private func deleteByID(
    client: any MappingServiceClient,
    remove: (RemappingProfile, UUID) throws -> RemappingProfile
  ) async throws -> String {
    let (selector, opts) = try selectorArguments()
    let options = try MappingOptions(opts)
    try options.validate(allowed: ["--id"])
    let profile = try await resolve(selector, client: client)
    let id = try MappingSyntax.uuid(try options.required("--id"), option: "--id")
    let updated = try remove(profile, id)
    return render(try await client.update(updated, expectedCurrent: profile), profileID: profile.id)
  }

  private func resolve(
    _ selector: String,
    client: any MappingServiceClient
  ) async throws -> RemappingProfile {
    if let id = UUID(uuidString: selector) { return try await client.profile(id: id) }
    let matches = try await client.snapshot().profiles.filter {
      $0.name.caseInsensitiveCompare(selector) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw MappingCommandError.profileNotFound(
        CLILocalized.format("cli.mapping.profile_missing", "No profile named '%@'.", selector)
      )
    }
    guard matches.count == 1, let profile = matches.first else {
      throw MappingCommandError.ambiguousProfile(
        CLILocalized.format(
          "cli.mapping.profile_ambiguous",
          "Profile name '%@' is ambiguous.",
          selector
        )
      )
    }
    return profile
  }

  private var profileArguments: ArraySlice<String> {
    ["chord", "sequence", "layer"].contains(command) ? arguments.dropFirst() : arguments[...]
  }

  private func selectorArguments() throws -> (String, [String]) {
    guard let selector = profileArguments.first, !selector.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.profile_required", "A profile UUID or name is required.")
      )
    }
    return (selector, Array(profileArguments.dropFirst()))
  }

  private func soleArgument(_ usage: String) throws -> String {
    guard profileArguments.count == 1, let value = profileArguments.first else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.usage_prefix", "Usage: %@", usage)
      )
    }
    return value
  }

  private func render(
    _ snapshot: ApplicationServiceRemappingSnapshotPayload,
    profileID: UUID
  ) -> String {
    guard let profile = snapshot.profiles.first(where: { $0.id == profileID }) else {
      return MappingRenderer.snapshot(snapshot)
    }
    return MappingRenderer.profile(profile)
  }

  static let help = CLILocalized.text(
    "cli.mapping.help",
    """
    Usage: OpenJoystickDriver --headless map <command>

    Commands:
      list [--json]
      show <profile> [--json]
      create <name> --vid <id> --pid <id> (--target-app <bundle-id> | --global)
      update <profile> [--name <name>] [--vid <id>] [--pid <id>]
        [--target-app <bundle-id> | --global]
      bind <profile> --source <source> --target <target> [binding options]
      unbind <profile> --source <source>
      delete <profile>
      import <file>
      export <profile> [--output <file>]
      enable <profile>
      disable --vid <id> --pid <id> | --profile <uuid-or-name>
      permission status | request
      calibration status|start|pause|reset --controller <runtime-identifier>
      joy-con pair <profile> --left <runtime-identifier> --right <runtime-identifier>
      joy-con unpair --session <session-uuid>
      --gyro-output disabled|mouse|left_stick|right_stick
      --gyro-virtual-motion true|false
      --gyro-pointer-points-per-degree <0...1000>
      --gyro-full-stick-degrees-per-second <1...10000>
      --gyro-activation always|while_held|while_released|toggle
      --gyro-activation-source <source>
      --gyro-consume-activation true|false
      --gyro-trackball-source <source>|none --gyro-trackball-axes pitch|yaw|both
      --gyro-trackball-decay <halvings/s> --gyro-trackball-consume true|false
      chord add <profile> --sources <s1>,<s2>,... --target <destination>
        [--mode modifier|simultaneous] [--window-ms <1...1000>]
      chord delete <profile> --id <chord-id>
      sequence add <profile> --sources <s1>,<s2>,... --window <ms> --target <destination>
      sequence delete <profile> --id <sequence-id>
      layer create <profile> --name <name> --activator <source> --mode hold|toggle
      layer delete <profile> --id <layer-id>
      layer bind <profile> --layer <layer-id> --source <s> --target <t> [binding options]
      layer unbind <profile> --layer <layer-id> --source <s>
      layer list <profile>

    Source: button:<name> | dpad:<direction> | axis:<name>[:negative|positive] |
      touch:<surface>:contact | touch:<surface>:grid:<columns>:<rows>:<column>:<row> |
      touch:<surface>:swipe:<direction>:<minimum-distance>
    Target: key:<key>[:mods=command,control,option,shift] | mouse:<button> |
      move:x|y | scroll:x|y | gamepad:button:<name> | gamepad:dpad:<direction> |
      gamepad:axis:<name>

    Output options (create and update):
      --virtual-gamepad disabled|mapped|passthrough
      --physical-input shared|exclusive
      Virtual gamepad output requires exclusive physical input ownership.

    --behavior hold|toggle|tap_on_press|tap_on_release|pulse|press|release
    --pulse-ms <1...5000>
    --actions-json <JSON-array>

    Stick options (create and update; select one stick per command):
      --stick-source left|right --stick-mode aim|flick|flick_only|rotate_only|none
      --stick-inner-deadzone <0...0.95> --stick-outer-deadzone <0...0.95>
      --stick-response-exponent <0.1...10> --stick-invert-x true|false
      --stick-invert-y true|false --stick-aim-degrees-per-second <0...10000>
      --stick-pointer-points-per-degree <0...1000> --stick-flick-duration-ms <0...10000>
      --stick-flick-threshold <0.1...1> --stick-flick-hysteresis <0...0.5>
    Touch options (create and update; select one surface per command):
      --touch-surface primary|left|right
      --touch-mode pointer|left_stick|right_stick|none
      --touch-pointer-sensitivity <1...5000> --touch-stick-radius <0.01...1>
      --touch-deadzone <0...0.95>

    Paired Joy-Con profile option (create and update):
      --joy-con-pair-gyro left|right|disabled|none

    Axis options:
      --deadzone <0...0.95> --gain <0.1...10>
      --invert --response-curve <linear|ease_in|ease_out|smooth_step>
      --digital-threshold <0.01...1>

    Turbo options (keyboard and mouse buttons only):
      --turbo-rate <1...60> --turbo-duty <0.05...0.95>

    Activation options (keyboard and mouse buttons only, mutually exclusive with turbo):
      --long-hold <ms>:<target>     e.g. --long-hold 500:key:b
      --double-tap <ms>:<target>    e.g. --double-tap 300:key:c

    <profile> accepts a UUID or an exact, case-insensitive profile name.
    <id> accepts decimal or 0x-prefixed hexadecimal.

    map update <profile> --motion-space local|player|world
    --motion-pitch-sensitivity <0...100> --motion-yaw-sensitivity <0...100>
    --motion-invert-pitch true|false --motion-invert-yaw true|false
    --motion-smoothing-half-time-ms <0...1000>
    --motion-threshold-degrees-per-second <0...1000>
    --motion-automatic-bias true|false --motion-yaw-relaxation <0...10>
    --motion-side-reduction-threshold <0...1> --motion-gravity-correction-rate <0...100>
    """
  ) + "\n\n" + CLILocalized.text(
    "cli.mapping.advanced_stick_trigger_help",
    """
    Advanced stick, trigger, and lean options:
      --stick-source left|right
      --stick-mode pointer_area|pointer_ring|scroll_wheel|steering|none
      --stick-pointer-radius-points <1...10000> --stick-scroll-degrees-per-line <1...360>
      --stick-scroll-axis horizontal|vertical
      --stick-rotation-direction clockwise|counterclockwise
      --stick-steering-degrees-at-full-scale <45...1440>
      --stick-steering-return-degrees-per-second <0...10000>
      --stick-steering-output left_stick_x|right_stick_x --stick-passthrough true|false

      --trigger-source left|right
      --trigger-mode simultaneous|exclusive|prefer_full|prefer_full_combined|
        responsive_prefer_full|responsive_prefer_full_combined|none
      --trigger-soft-threshold <0.01...0.95> --trigger-full-threshold <0.05...1>
      --trigger-hysteresis <0...0.25> --trigger-skip-window-ms <1...1000>
      --trigger-passthrough true|false

      --motion-lean true|false --motion-lean-threshold-degrees <1...89>
      --motion-lean-hysteresis-degrees <0...30>
      --motion-steering-output left_stick_x|right_stick_x|none
      --motion-steering-deadzone-degrees <0...89>
      --motion-steering-full-scale-degrees <1...90>
      --motion-steering-response-exponent <0.1...10>
      --motion-steering-inverted true|false

    Sources:
      trigger:<left|right>:<soft|full> | motion:lean:<left|right>
    """
  ) + "\n\n" + CLILocalized.text(
    "cli.mapping.physical_output_help",
    """
    Physical controller targets:
      physical:rumble:<motor>:<0...1>
      physical:player:<0...4>
      physical:color:<red>:<green>:<blue>
      physical:brightness:<0...1>
      physical:adaptive:<left|right>:off
      physical:adaptive:<left|right>:resistance:<start-position>:<strength>
    """
  )
}
