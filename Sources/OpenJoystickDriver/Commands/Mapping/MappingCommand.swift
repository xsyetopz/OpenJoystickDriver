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
        throw MappingCommandError.invalidArguments("Could not connect to the installed main app.")
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
    "--digital-threshold", "--turbo-rate", "--turbo-duty",
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
    default: throw MappingCommandError.invalidArguments("Unknown map command '\(command)'.")
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
    return render(
      try await client.update(updated, expectedCurrent: profile),
      profileID: profile.id
    )
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
    return render(
      try await client.update(updated, expectedCurrent: profile),
      profileID: profile.id
    )
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
    return render(
      try await client.update(updated, expectedCurrent: profile),
      profileID: profile.id
    )
  }

  private func delete(client: any MappingServiceClient) async throws -> String {
    let selector = try soleArgument("map delete <uuid-or-name>")
    let profile = try await resolve(selector, client: client)
    return MappingRenderer.snapshot(try await client.delete(id: profile.id))
  }

  private func importProfile(client: any MappingServiceClient) async throws -> String {
    let path = try soleArgument("map import <file>")
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
    let profile = try await resolve(soleArgument("map enable <uuid-or-name>"), client: client)
    return MappingRenderer.snapshot(try await client.activate(id: profile.id))
  }

  private func deactivate(client: any MappingServiceClient) async throws -> String {
    let options = try MappingOptions(arguments)
    try options.validate(allowed: ["--vid", "--pid"])
    let vendorID = try MappingSyntax.identifier(options.required("--vid"), option: "--vid")
    let productID = try MappingSyntax.identifier(options.required("--pid"), option: "--pid")
    return MappingRenderer.snapshot(
      try await client.deactivate(vendorID: vendorID, productID: productID)
    )
  }

  private func permission(client: any MappingServiceClient) async throws -> String {
    let operation = try soleArgument("map permission status|request")
    guard operation == "status" || operation == "request" else {
      throw MappingCommandError.invalidArguments("map permission status|request")
    }
    return try await client.access(request: operation == "request").rawValue
  }

  private func resolve(_ selector: String, client: any MappingServiceClient) async throws
    -> RemappingProfile
  {
    if let id = UUID(uuidString: selector) { return try await client.profile(id: id) }
    let matches = try await client.snapshot().profiles.filter {
      $0.name.caseInsensitiveCompare(selector) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw MappingCommandError.profileNotFound("No profile named '\(selector)'.")
    }
    guard matches.count == 1, let profile = matches.first else {
      throw MappingCommandError.ambiguousProfile("Profile name '\(selector)' is ambiguous.")
    }
    return profile
  }

  private func selectorArguments() throws -> (String, [String]) {
    guard let selector = arguments.first, !selector.hasPrefix("--") else {
      throw MappingCommandError.invalidArguments("A profile UUID or name is required.")
    }
    return (selector, Array(arguments.dropFirst()))
  }

  private func soleArgument(_ usage: String) throws -> String {
    guard arguments.count == 1, let value = arguments.first else {
      throw MappingCommandError.invalidArguments("Usage: \(usage)")
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

  static let help = """
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
      disable --vid <id> --pid <id>
      permission status | request

    Source: button:<name> | dpad:<direction> | axis:<name>[:negative|positive]
    Target: key:<key>[:mods=command,control,option,shift] | mouse:<button> |
      move:x|y | scroll:x|y

    Axis options:
      --deadzone <0...0.95> --gain <0.1...10>
      --invert --response-curve <linear|ease_in|ease_out|smooth_step>
      --digital-threshold <0.01...1>

    Turbo options (keyboard and mouse buttons only):
      --turbo-rate <1...60> --turbo-duty <0.05...0.95>

    <profile> accepts a UUID or an exact, case-insensitive profile name.
    <id> accepts decimal or 0x-prefixed hexadecimal.
    """
}
