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
    "--digital-threshold", "--turbo-rate", "--turbo-duty", "--long-hold", "--double-tap"
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
    try options.validate(allowed: ["--vid", "--pid", "--target-app", "--global"])
    let profile = RemappingProfile(
      name: name,
      device: RemappingDeviceScope(
        vendorID: try MappingSyntax.identifier(options.required("--vid"), option: "--vid"),
        productID: try MappingSyntax.identifier(options.required("--pid"), option: "--pid")
      ),
      applicationScope: try MappingProfileEditor.applicationScope(options),
      bindings: []
    )
    try profile.validate()
    return render(try await client.create(profile), profileID: profile.id)
  }

  private func update(client: any MappingServiceClient) async throws -> String {
    let (selector, trailing) = try selectorArguments()
    let options = try MappingOptions(trailing, flags: ["--global"])
    try options.validate(allowed: ["--name", "--vid", "--pid", "--target-app", "--global"])
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
    let path = try soleArgument(
      CLILocalized.text("cli.mapping.usage.import", "map import <file>")
    )
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

  private func chord(client: any MappingServiceClient) async throws -> String {
    guard let action = arguments.first, !action.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.usage.chord", "Usage: map chord <profile> add|delete ...")
      )
    }
    switch action {
    case "add":
      let (selector, opts) = try selectorArguments()
      let options = try MappingOptions(opts)
      try options.validate(allowed: ["--sources", "--target"])
      let profile = try await resolve(selector, client: client)
      let sources = try MappingSyntax.sourceList(try options.required("--sources"))
      let destination = try MappingSyntax.destination(try options.required("--target"))
      let updated = try MappingProfileEditor.addingChord(
        in: profile,
        sources: sources,
        destination: destination
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
          "Usage: map sequence <profile> add|delete ..."
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
          "Usage: map layer <profile> create|delete|bind|unbind|list ..."
        )
      )
    }
    switch action {
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
          "Unknown layer action '%@'. Expected: create | delete | bind | unbind | list",
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

  private func resolve(_ selector: String, client: any MappingServiceClient) async throws
    -> RemappingProfile
  {
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

  private func selectorArguments() throws -> (String, [String]) {
    guard let selector = arguments.first, !selector.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.text("cli.mapping.profile_required", "A profile UUID or name is required.")
      )
    }
    return (selector, Array(arguments.dropFirst()))
  }

  private func soleArgument(_ usage: String) throws -> String {
    guard arguments.count == 1, let value = arguments.first else {
      throw MappingCommandError.invalidArguments(
        CLILocalized.format("cli.mapping.usage_prefix", "Usage: %@", usage)
      )
    }
    return value
  }

  private func render(_ snapshot: ApplicationServiceRemappingSnapshotPayload, profileID: UUID)
    -> String
  {
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
      chord <profile> add --sources <s1>,<s2>,... --target <destination>
      chord <profile> delete --id <chord-id>
      sequence <profile> add --sources <s1>,<s2>,... --window <ms> --target <destination>
      sequence <profile> delete --id <sequence-id>
      layer <profile> create --name <name> --activator <source> --mode hold|toggle
      layer <profile> delete --id <layer-id>
      layer <profile> bind --layer <layer-id> --source <s> --target <t> [binding options]
      layer <profile> unbind --layer <layer-id> --source <s>
      layer <profile> list

    Source: button:<name> | dpad:<direction> | axis:<name>[:negative|positive]
    Target: key:<key>[:mods=command,control,option,shift] | mouse:<button> |
      move:x|y | scroll:x|y

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
    """
  )
}
