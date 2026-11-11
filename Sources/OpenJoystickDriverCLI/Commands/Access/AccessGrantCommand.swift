public import ArgumentParser
import Foundation
public import OpenJoystickDriverKit

/// A client that `ojd access grant` or `revoke` names: a program path, or an ID from
/// `ojd access list`.
struct AccessClient {
  /// The code signature identity of the program.
  let identity: CodeSigningIdentity
  /// The path of the program.
  let path: String

  /// Reads the signature at a path, or looks up an ID among the granted and refused clients.
  static func resolve(
    _ text: String,
    status: @Sendable () async throws -> AccessStatusPayload
  )
    async throws -> Self
  {
    if text.contains("/") || FileManager.default.fileExists(atPath: text) {
      let url = URL(fileURLWithPath: text).standardizedFileURL
      guard let signed = PlatformHosts.current.codeSigningIdentity(ofPath: url) else {
        throw CLIFailure(
          .unsignedClient,
          CLILocalized.format(
            "cli.access.group.clientUnsigned",
            url.path
          )
        )
      }
      return Self(identity: signed, path: url.path)
    }
    let payload = try await status()
    if let grant = payload.grants.first(where: { $0.id == text }) {
      return Self(
        identity: CodeSigningIdentity(
          kind: grant.publisher.kind,
          identifier: grant.identifier,
          publisherID: grant.publisher.id
        ),
        path: grant.path
      )
    }
    if let client = payload.refused.first(where: { $0.id == text }) {
      return Self(identity: client.identity, path: client.path ?? "")
    }
    throw CLIFailure(
      .notFound,
      CLILocalized.format(
        "cli.access.group.clientUnknown",
        text
      )
    )
  }
}

/// The `ojd access grant` command: grants a program or a named token access to the service.
struct AccessGrantCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "grant",
    abstract: CLILocalized.text(
      "cli.access.grant.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.grant.discussion"
    ) + "\n\n" + CLILocalized.text("cli.access.grant.examples")
  )

  /// The program path or ID of the client to grant; omitted with `--token`.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.access.group.client"),
      valueName: "client"
    )
  )
  var client: String?

  /// `--token`: the name of the token to create, instead of a client.
  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.grant.token"
      ),
      valueName: "name"
    )
  )
  var token: String?

  /// `--origin`: a web origin that the token accepts; needs `--token`.
  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.grant.origin"
      ),
      valueName: "url"
    )
  )
  var origin: [String] = []

  /// `--scope`: the scopes to grant; `read` when omitted.
  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.grant.scope"
      ),
      valueName: "scope"
    )
  )
  var scope: [EndpointScope] = [.read]

  /// `-f`, `--force`: skip the confirmation.
  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.shared.option.force"))
  )
  var force = false

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Checks that the options fit together.
  ///
  /// Exactly one of the client and `--token` is required, `--origin` needs `--token`, and an origin
  /// cannot carry the `control` scope.
  ///
  /// - Throws: ``ValidationError`` for any other combination.
  func validate() throws {
    guard (client == nil) != (token == nil) else {
      throw ValidationError(
        CLILocalized.text("cli.access.grant.clientOrToken")
      )
    }
    guard token != nil || origin.isEmpty else {
      throw ValidationError(
        CLILocalized.text("cli.access.grant.originNeedsToken")
      )
    }
    guard origin.isEmpty || !scope.contains(.control) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.access.grant.originControl"
        )
      )
    }
  }

  /// Runs the command.
  func run() async throws {
    try await global.run {
      if let token {
        try await grantToken(named: token)
        return
      }
      let resolved = try await AccessClient.resolve(client ?? "") {
        try await ServiceConnection.request { try await $0.accessStatus() }
      }
      let identity = resolved.identity
      guard identity.kind != .adHoc else {
        throw CLIFailure(
          .unsignedClient,
          CLILocalized.format(
            "platform.macos.cli.access.grant.adHoc",
            identity.identifier
          )
        )
      }
      try CLITerminal.confirm(
        question(for: identity),
        force: force,
        needsForce: AccessText.needsForce
      )
      let scopes = scope
      let grant = try await ServiceConnection.request {
        try await $0.grantAccess(identity, path: resolved.path, scopes: scopes)
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(grant)
      case .plain: CLIOutput.plain([[grant.id, grant.identifier, AccessText.scopes(grant.scopes)]])
      case .human:
        CLIOutput.success(
          CLILocalized.format(
            "cli.access.grant.success",
            AccessText.scopes(grant.scopes),
            grant.identifier,
            grant.id
          )
        )
      }
    }
  }

  /// Grants the token `name` its scopes and origins through the service and prints the token.
  ///
  /// The command asks for a confirmation first, with a warning when the scopes include `control`.
  private func grantToken(named name: String) async throws {
    var lines = [
      origin.isEmpty
        ? CLILocalized.format(
          "platform.macos.cli.access.grant.tokenConfirm",
          name,
          AccessText.scopes(scope)
        )
        : CLILocalized.format(
          "platform.macos.cli.access.grant.tokenWebConfirm",
          name,
          AccessText.scopes(scope),
          origin.joined(separator: ", ")
        )
    ]
    if scope.contains(.control) { lines.insert(Self.controlWarning, at: 0) }
    try CLITerminal.confirm(
      lines.joined(separator: "\n"),
      force: force,
      needsForce: AccessText.needsForce
    )
    let (origins, scopes) = (origin, scope)
    let result = try await ServiceConnection.request {
      try await $0.grantTokenAccess(name: name, origins: origins, scopes: scopes)
    }
    switch CLIContext.current.format {
    case .json: try CLIOutput.json(result, kind: "AccessToken")
    case .plain:
      CLIOutput.plain([[result.token, result.grant.id, AccessText.scopes(result.grant.scopes)]])
    case .human:
      CLIOutput.success(
        CLILocalized.format(
          "cli.access.grant.tokenSuccess",
          AccessText.scopes(result.grant.scopes),
          result.grant.name,
          result.grant.id
        )
      )
      CLIOutput.raw(result.token)
    }
  }

  /// The warning for a grant that includes the `control` scope.
  private static var controlWarning: String {
    CLILocalized.text(
      "cli.access.grant.controlWarning"
    )
  }

  /// Returns the confirmation text for granting access to the client `identity`.
  ///
  /// It adds a warning for a platform binary and one for the `control` scope.
  private func question(for identity: CodeSigningIdentity) -> String {
    var lines = [
      CLILocalized.format(
        "cli.access.grant.confirm",
        identity.identifier,
        AccessText.signer(identity.kind, identity.publisherID),
        AccessText.scopes(scope)
      )
    ]
    if identity.kind == .platform {
      lines.insert(
        CLILocalized.text(
          "platform.macos.cli.access.grant.platformWarning"
        ),
        at: 0
      )
    }
    if scope.contains(.control) { lines.insert(Self.controlWarning, at: 0) }
    return lines.joined(separator: "\n")
  }
}

/// The `ojd access revoke` command: removes the access of a client or a token.
struct AccessRevokeCommand: AsyncParsableCommand {
  /// The name, help text and subcommands of the command.
  static let configuration = CommandConfiguration(
    commandName: "revoke",
    abstract: CLILocalized.text(
      "cli.access.revoke.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.revoke.discussion"
    )
  )

  /// The program path or ID of the client, or the `token:` ID of a token.
  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.revoke.client"
      ),
      valueName: "client"
    )
  )
  var client: String

  /// `--scope`: the scopes to revoke; every scope when omitted.
  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.revoke.scope"
      ),
      valueName: "scope"
    )
  )
  var scope: [EndpointScope] = []

  /// The global options.
  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  /// Runs the command.
  func run() async throws {
    try await global.run {
      let id =
        client.hasPrefix("token:")
        ? client
        : try await AccessClient.resolve(client) {
          try await ServiceConnection.request { try await $0.accessStatus() }
        }.identity.accessID
      let scopes = scope.isEmpty ? nil : scope
      let result = try await ServiceConnection.request {
        try await $0.revokeAccess(id: id, scopes: scopes)
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(CLIStatus(details: result))
      case .plain:
        CLIOutput.plain([
          [
            result.id, (result.grant?.scopes ?? result.token?.scopes).map(AccessText.scopes) ?? "",
            String(result.closedConnections),
          ]
        ])
      case .human:
        CLIOutput.success(
          (result.grant?.scopes ?? result.token?.scopes).map {
            CLILocalized.format(
              "cli.access.revoke.partial",
              result.id,
              AccessText.scopes($0),
              String(result.closedConnections)
            )
          }
            ?? CLILocalized.format(
              "cli.access.revoke.success",
              result.id,
              String(result.closedConnections)
            )
        )
      }
    }
  }
}

extension EndpointScope: ExpressibleByArgument {
  /// A scope on the command line is its lowercase kebab-case name: `read` or `control`.
  public init?(argument: String) {
    guard let scope = CommandLineName.value(of: argument, in: Self.self) else { return nil }
    self = scope
  }

  /// The scope names that the command line accepts.
  public static var allValueStrings: [String] { allCases.map(\.commandLineName) }
}
