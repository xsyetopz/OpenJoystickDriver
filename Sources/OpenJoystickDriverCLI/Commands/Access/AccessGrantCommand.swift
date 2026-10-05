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
          .failure,
          CLILocalized.format(
            "cli.access.client.unsigned",
            "%@ holds no signed program. Grant the program's app bundle or executable.",
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
          kind: grant.kind,
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
      .failure,
      CLILocalized.format(
        "cli.access.client.unknown",
        "No program at %@ and no client with that ID. See the IDs with 'ojd access list'.",
        text
      )
    )
  }
}

struct AccessGrantCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "grant",
    abstract: CLILocalized.text(
      "cli.access.grant.abstract",
      "Allow a signed program, or a new token, to use the endpoint."
    ),
    discussion: CLILocalized.text(
      "cli.access.grant.discussion",
      "CLIENT is the program's path or an ID from 'ojd access list'. The grant names the "
        + "program's signature, so it stays valid when the program is updated or moved. "
        + "Ad-hoc signed and unsigned programs cannot be granted. With --token instead of "
        + "CLIENT, creates a token that a client signs the service's challenge with in its hello: "
        + "on the socket, on the WebSocket from a page at one of the --origin values, or, for a "
        + "token without --origin, on the WebSocket from a program that sends no Origin header, "
        + "such as a sandboxed app. A page cannot use the control scope. The token is shown "
        + "only once. "
        + "Asks for confirmation first."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.access.client", "The program's path, or a client ID."),
      valueName: "client"
    )
  )
  var client: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.grant.token",
        "Create a token with this name instead of granting a program."
      ),
      valueName: "name"
    )
  )
  var token: String?

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.grant.origin",
        "A web origin, such as http://127.0.0.1:8080, whose pages may use the token on the "
          + "WebSocket. Repeat for more. The overlay pages that the WebSocket serves have the "
          + "origin http://127.0.0.1:PORT, with the port that 'ojd access status' shows."
      ),
      valueName: "url"
    )
  )
  var origin: [String] = []

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.grant.scope",
        "A scope to grant: read or control. Repeat for both."
      ),
      valueName: "scope"
    )
  )
  var scope: [EndpointScope] = [.read]

  @Flag(
    name: [.short, .long],
    help: ArgumentHelp(CLILocalized.text("cli.option.force", "Do not ask for confirmation."))
  )
  var force = false

  @OptionGroup
  var global: GlobalOptions

  func validate() throws {
    guard (client == nil) != (token == nil) else {
      throw ValidationError(
        CLILocalized.text("cli.access.grant.client_or_token", "Give either CLIENT or --token NAME.")
      )
    }
    guard token != nil || origin.isEmpty else {
      throw ValidationError(
        CLILocalized.text("cli.access.grant.origin_needs_token", "--origin needs --token.")
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
          .failure,
          CLILocalized.format(
            "cli.access.grant.ad_hoc",
            "%@ is ad-hoc signed or unsigned, so any local program can claim its signature. "
              + "Sign it with a Developer ID or Apple Development certificate, then grant it.",
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
            "Granted %@ to %@ (ID %@).",
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
          "Create the token %@ with %@, for programs on this Mac?",
          name,
          AccessText.scopes(scope)
        )
        : CLILocalized.format(
          "cli.access.grant.token_web_confirm",
          "Create the token %@ with %@, for programs on this Mac and for pages from %@?",
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
    case .json: try CLIOutput.json(result)
    case .plain:
      CLIOutput.plain([[result.token, result.grant.id, AccessText.scopes(result.grant.scopes)]])
    case .human:
      CLIOutput.success(
        CLILocalized.format(
          "cli.access.grant.token_success",
          "Granted %@ to the token %@ (ID %@). Keep the token secret; it is not shown again:",
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
      "cli.access.grant.control_warning",
      "The control scope lets the program press buttons on a virtual gamepad, which games "
        + "and apps treat as your input."
    )
  }

  private func question(for identity: CodeSigningIdentity) -> String {
    var lines = [
      CLILocalized.format(
        "cli.access.grant.confirm",
        "Allow %@, signed %@, to use the endpoint with %@?",
        identity.identifier,
        AccessText.signer(identity.kind, identity.teamIdentifier),
        AccessText.scopes(scope)
      )
    ]
    if identity.kind == .apple {
      lines.insert(
        CLILocalized.text(
          "cli.access.grant.apple_warning",
          "Apple signed this program. If it runs scripts, such as python3 or osascript, every "
            + "script it runs gets this access."
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
      "cli.access.revoke.abstract",
      "Remove a program's grant, or some of its scopes."
    ),
    discussion: CLILocalized.text(
      "cli.access.revoke.discussion",
      "CLIENT is the program's path, an ID from 'ojd access list', or token:NAME for a token. "
        + "Without --scope, removes the whole grant. Connections that lose a scope are closed."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.revoke.client",
        "The program's path, a client ID, or token:NAME."
      ),
      valueName: "client"
    )
  )
  var client: String

  @Option(
    name: .long,
    help: ArgumentHelp(
      CLILocalized.text(
        "cli.access.revoke.scope",
        "A scope to remove: read or control. Repeat for both."
      ),
      valueName: "scope"
    )
  )
  var scope: [EndpointScope] = []

  @OptionGroup
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
      case .json: try CLIOutput.json(result)
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
              "Client %@ keeps %@. Closed connections: %@.",
              result.id,
              AccessText.scopes($0),
              String(result.closedConnections)
            )
          }
            ?? CLILocalized.format(
              "cli.access.revoke.success",
              "Removed the grant of client %@. Closed connections: %@.",
              result.id,
              String(result.closedConnections)
            )
        )
      }
    }
  }
}

extension EndpointScope: ExpressibleByArgument {}
