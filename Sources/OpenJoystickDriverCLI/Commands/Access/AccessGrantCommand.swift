import ArgumentParser
import Foundation
import OpenJoystickDriverKit

/// A client that `ojd access grant` or `revoke` names: a program path, or an ID from
/// `ojd access list`.
struct AccessClient {
  let identity: CodeSigningIdentity
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
      guard let identity = CodeSigningIdentity.of(path: url) else {
        throw CLIFailure(
          .unsignedClient,
          CLILocalized.format(
            "cli.access.client.unsigned",
            url.path
          )
        )
      }
      return Self(identity: identity, path: url.path)
    }
    let status = try await status()
    if let grant = status.grants.first(where: { $0.id == text }) {
      return Self(
        identity: CodeSigningIdentity(
          kind: grant.identityKind.kind,
          identifier: grant.identifier,
          teamIdentifier: grant.teamIdentifier
        ),
        path: grant.path
      )
    }
    if let client = status.refused.first(where: { $0.id == text }) {
      return Self(identity: client.identity, path: client.path ?? "")
    }
    throw CLIFailure(
      .notFound,
      CLILocalized.format(
        "cli.access.client.unknown",
        text
      )
    )
  }
}

struct AccessGrantCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "grant",
    abstract: CLILocalized.text(
      "cli.access.grant.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.grant.discussion"
    ) + "\n\n" + CLILocalized.text("cli.access.grant.examples")
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.access.client"),
      valueName: "client"
    )
  )
  var client: String?

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

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force"))
  )
  var force = false

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

  func validate() throws {
    guard (client == nil) != (token == nil) else {
      throw ValidationError(
        CLILocalized.text("cli.access.grant.client_or_token")
      )
    }
    guard token != nil || origin.isEmpty else {
      throw ValidationError(
        CLILocalized.text("cli.access.grant.origin_needs_token")
      )
    }
    guard origin.isEmpty || !scope.contains(.control) else {
      throw ValidationError(
        CLILocalized.text(
          "cli.access.grant.origin_control"
        )
      )
    }
  }

  func run() async throws {
    try await global.run {
      if let token {
        try await grantToken(named: token)
        return
      }
      let client = try await AccessClient.resolve(client ?? "") {
        try await ServiceConnection.request { try await $0.accessStatus() }
      }
      let identity = client.identity
      guard identity.kind != .adHoc else {
        throw CLIFailure(
          .unsignedClient,
          CLILocalized.format(
            "cli.access.grant.ad_hoc",
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
        try await $0.grantAccess(identity, path: client.path, scopes: scopes)
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

  private func grantToken(named name: String) async throws {
    var lines = [
      origin.isEmpty
        ? CLILocalized.format(
          "cli.access.grant.token_confirm",
          name,
          AccessText.scopes(scope)
        )
        : CLILocalized.format(
          "cli.access.grant.token_web_confirm",
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
          "cli.access.grant.token_success",
          AccessText.scopes(result.grant.scopes),
          result.grant.name,
          result.grant.id
        )
      )
      CLIOutput.stdout(result.token)
    }
  }

  private static var controlWarning: String {
    CLILocalized.text(
      "cli.access.grant.control_warning"
    )
  }

  private func question(for identity: CodeSigningIdentity) -> String {
    var lines = [
      CLILocalized.format(
        "cli.access.grant.confirm",
        identity.identifier,
        AccessText.signer(identity.kind, identity.teamIdentifier),
        AccessText.scopes(scope)
      )
    ]
    if identity.kind == .apple {
      lines.insert(
        CLILocalized.text(
          "cli.access.grant.apple_warning"
        ),
        at: 0
      )
    }
    if scope.contains(.control) { lines.insert(Self.controlWarning, at: 0) }
    return lines.joined(separator: "\n")
  }
}

struct AccessRevokeCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "revoke",
    abstract: CLILocalized.text(
      "cli.access.revoke.abstract"
    ),
    discussion: CLILocalized.text(
      "cli.access.revoke.discussion"
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.revoke.client"
      ),
      valueName: "client"
    )
  )
  var client: String

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

  @OptionGroup(visibility: GlobalOptions.subcommandVisibility)
  var global: GlobalOptions

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

extension EndpointScope: ExpressibleByArgument {}
