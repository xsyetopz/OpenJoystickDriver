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
      "Allow a signed program to use the endpoint."
    ),
    discussion: CLILocalized.text(
      "cli.access.grant.discussion",
      "CLIENT is the program's path or an ID from 'ojd access list'. The grant names the "
        + "program's signature, so it stays valid when the program is updated or moved. "
        + "Ad-hoc signed and unsigned programs cannot be granted. Asks for confirmation first."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.access.client", "The program's path, or a client ID."),
      valueName: "client"
    )
  )
  var client: String

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

  func run() async throws {
    try await global.run {
      let client = try await AccessClient.resolve(client) {
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
    if scope.contains(.control) {
      lines.insert(
        CLILocalized.text(
          "cli.access.grant.control_warning",
          "The control scope lets the program press buttons on a virtual gamepad, which games "
            + "and apps treat as your input."
        ),
        at: 0
      )
    }
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
      "CLIENT is the program's path or an ID from 'ojd access list'. Without --scope, removes "
        + "the whole grant. Connections that lose a scope are closed."
    )
  )

  @Argument(
    help: ArgumentHelp(
      CLILocalized.text("cli.access.client", "The program's path, or a client ID."),
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
      let client = try await AccessClient.resolve(client) {
        try await ServiceConnection.request { try await $0.accessStatus() }
      }
      let id = client.identity.accessID
      let scopes = scope.isEmpty ? nil : scope
      let result = try await ServiceConnection.request {
        try await $0.revokeAccess(id: id, scopes: scopes)
      }
      switch CLIContext.current.format {
      case .json: try CLIOutput.json(result)
      case .plain:
        CLIOutput.plain([
          [
            result.id, result.grant.map { AccessText.scopes($0.scopes) } ?? "",
            String(result.closedConnections),
          ]
        ])
      case .human:
        CLIOutput.success(
          result.grant.map {
            CLILocalized.format(
              "cli.access.revoke.partial",
              "Client %@ keeps %@. Closed connections: %@.",
              result.id,
              AccessText.scopes($0.scopes),
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
